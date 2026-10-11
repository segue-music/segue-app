import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/equalizer_choice.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/language_choice.dart';
import 'package:segue/player/player.dart';
import 'package:segue/quality_choice.dart';
import 'package:segue/replay_gain_choice.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/theme_choice.dart';
import 'package:segue/ui/album/album_page.dart';
import 'package:segue/ui/album/albums_view.dart';
import 'package:segue/ui/artist/artists_view.dart';
import 'package:segue/ui/genre/genres_view.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/home/home_view.dart';
import 'package:segue/ui/playlist/playlists_view.dart';
import 'package:segue/ui/settings/settings_page.dart';
import 'package:segue/ui/app/shortcuts.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/app/theme_fade.dart';
import 'package:segue/ui/widgets/themed_icon.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';
import 'sections.dart';
import 'side_rail.dart';
import 'themed_icons.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response albumList(List<String> names) => subsonic({
  'albumList2': {
    'album': [
      for (final name in names) {'id': name, 'name': name, 'artist': 'Aerosmith'},
    ],
  },
});

/// The home page on a screen of [size], over a server whose latest released albums are [released],
/// whose most played are [mostPlayed] (null: it fails to list them) and whose latest added are
/// [latest], however many are asked for. In the app's themes, as [themeChoice] picks them, which the home switches, as
/// the app does (ThemeFade). [languageChoice] is the home's to pick, though the app stays in Portuguese. [packageInfo]
/// is the version the settings show. Returns the queries of the album lists the rows asked for; not the mixes', which
/// count the 500 most played (and find no genres there, nor any of the library's: the home has no mixes).
Future<List<Map<String, String>>> pumpHome(
  WidgetTester tester,
  Size size, {
  List<String> released = const ['Music from Another Dimension!'],
  List<String>? mostPlayed = const ['Pump', 'Toys in the Attic'],
  List<String> latest = const ['Night in the Ruts'],
  bool television = false,
  ThemeChoice? themeChoice,
  LanguageChoice? languageChoice,
  QualityChoice? qualityChoice,
  ReplayGainChoice? replayGainChoice,
  EqualizerChoice? equalizerChoice,
  PackageInfo? packageInfo,
  VoidCallback? onSignOut,
}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final asked = <Map<String, String>>[];
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      final query = request.url.queryParameters;

      if (request.url.path.endsWith('getAlbumList2.view')) {
        if (query['size'] != '500') {
          asked.add(query);
        }

        return switch (query['type']) {
          'frequent' when mostPlayed != null => albumList(mostPlayed),
          'newest' => albumList(latest),
          'byYear' => albumList(released),
          _ => http.Response('', 500),
        };
      }

      if (request.url.path.endsWith('getAlbum.view')) {
        return subsonic({
          'album': {
            'id': query['id'],
            'name': query['id'],
            'song': [
              {'id': 's1', 'title': 'Love in an Elevator', 'artist': 'Aerosmith'},
            ],
          },
        });
      }

      return http.Response('', 404);
    }),
  );
  final player = PlayerController(FakeEngine(), api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget app() {
    final ThemeSettings(:mode, :palette, :highContrast) = themeChoice?.value ?? const ThemeSettings();
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      theme: themeChoice == null ? null : segueTheme(Brightness.light, palette: palette, highContrast: highContrast),
      darkTheme: themeChoice == null ? null : segueTheme(Brightness.dark, palette: palette, highContrast: highContrast),
      themeMode: mode,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => ThemeFade(
        child: ServicesScope(
          services: services,
          child: DirectionalNavigation(enabled: television, child: child!),
        ),
      ),
      home: HomePage(
        onSignOut: onSignOut ?? () {},
        themeChoice: themeChoice,
        languageChoice: languageChoice,
        qualityChoice: qualityChoice,
        replayGainChoice: replayGainChoice,
        equalizerChoice: equalizerChoice,
        packageInfo: packageInfo,
      ),
    );
  }

  await tester.pumpWidget(
    themeChoice == null ? app() : ListenableBuilder(listenable: themeChoice, builder: (context, _) => app()),
  );
  await tester.pumpAndSettle();
  return asked;
}

/// The top bar's button that opens the settings.
final settingsButton = find.byTooltip('Configurações');

/// In the settings, the item that says [text].
Finder settingsItem(String text) =>
    find.descendant(of: find.byType(SettingsPage), matching: find.widgetWithText(ListTile, text));

/// In the settings, the option that says [text], in the sheet of a choice's options.
Finder option(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(ListTile, text));

/// Whether the option that says [text] has the check of the one picked.
bool checked(String text) =>
    find.descendant(of: option(text), matching: themedIcon(HugeIcons.strokeRoundedTick02)).evaluate().isNotEmpty;

/// Whether the settings' choice [choice] says that [picked] is the option picked, under its name.
bool says(String choice, String picked) =>
    find.descendant(of: settingsItem(choice), matching: find.text(picked)).evaluate().isNotEmpty;

/// In the settings, opens the sheet of the choice [choice]'s options.
Future<void> openChoice(WidgetTester tester, String choice) async {
  await tester.tap(settingsItem(choice));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget, reason: choice);
}

/// Picks the option that says [text] in a choice's sheet, which closes.
Future<void> pick(WidgetTester tester, String text) async {
  await tester.tap(option(text));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsNothing, reason: 'a pick closes the sheet');
}

/// Closes a choice's sheet without a pick, as Esc does.
Future<void> closeChoice(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsNothing);
}

/// Opens the settings, from the top bar's button.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(settingsButton);
  await tester.pumpAndSettle();
}

/// The rows' sideways lists, in order.
final rows = find.byWidgetPredicate((widget) => widget is ListView && widget.scrollDirection == Axis.horizontal);

Finder title(String text) => find.descendant(of: find.byType(AppBar), matching: find.text(text));

/// A text, where it shows.
Finder shown(String text) => find.text(text).hitTestable();

/// Where the side rail ends: the line between it and the section.
double railWidth(WidgetTester tester) => tester.getTopLeft(find.byType(VerticalDivider)).dx;

/// The side rail's button for [section], which its tooltip names.
Finder railButton(String section) =>
    find.descendant(of: find.byTooltip(section), matching: find.byWidgetPredicate((widget) => widget is InkResponse));

/// The name of the album that has the focus.
String? focusedAlbum() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<AlbumTile>()?.album.name;

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  // Where the theme picked is kept.
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  testWidgets('the app opens on the home: a row of the latest released albums, then the most played, then the latest '
      'added', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    expectHomeInRail();

    final released = tester.getRect(find.text('Lançamentos'));
    final another = tester.getRect(find.text('Music from Another Dimension!'));
    final mostPlayed = tester.getRect(find.text('Mais tocados'));
    final pump = tester.getRect(find.text('Pump'));
    final toys = tester.getRect(find.text('Toys in the Attic'));
    final latest = tester.getRect(find.text('Adicionados recentemente'));
    final ruts = tester.getRect(find.text('Night in the Ruts'));
    expect(another.top, greaterThan(released.bottom));
    expect(mostPlayed.top, greaterThan(another.bottom));
    expect(pump.top, greaterThan(mostPlayed.bottom));
    expect(toys.top, pump.top, reason: 'side by side, the most played first');
    expect(toys.left, greaterThan(pump.right));
    expect(latest.top, greaterThan(pump.bottom));
    expect(ruts.top, greaterThan(latest.bottom));

    await tester.tap(find.text('Pump'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AlbumPage), matching: find.text('Pump')), findsOneWidget);
    expect(find.text('Love in an Elevator'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('the side rail has the sections\' icons, each a button no bigger than its highlight, named on hover', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    expect(railWidth(tester), 56);
    expect(shown('Álbuns'), findsNothing);
    expect(shown('Artistas'), findsNothing);
    expect(shown('Gêneros'), findsNothing);
    expect(shown('Playlists'), findsNothing);
    expect(find.byTooltip('Recolher a barra lateral'), findsNothing, reason: 'it is always so');

    for (final section in ['Álbuns', 'Artistas', 'Gêneros', 'Playlists']) {
      expect(tester.getSize(railButton(section)), const Size(40, 40), reason: section);
    }

    await tester.tap(find.byTooltip('Álbuns'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Álbuns'), findsOneWidget);

    bool selected(String section) => tester
        .widget<IconButton>(find.ancestor(of: railButton(section), matching: find.byType(IconButton)))
        .isSelected!;

    expect(selected('Álbuns'), isTrue);
    expect(selected('Artistas'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a section\'s name shows beside its icon, level with it, rather than over the icon below', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(999, 699));
    addTearDown(mouse.removePointer);

    for (final section in ['Álbuns', 'Artistas', 'Gêneros', 'Playlists']) {
      final icon = tester.getRect(railButton(section));
      await mouse.moveTo(icon.center);
      await tester.pumpAndSettle();
      final name = tester.getRect(find.text(section));
      expect(name.left, greaterThan(icon.right), reason: '$section: to the right of its icon');
      expect(name.center.dy, moreOrLessEquals(icon.center.dy, epsilon: 1), reason: '$section: level with it');
      await mouse.moveTo(const Offset(999, 699));
      await tester.pumpAndSettle(const Duration(seconds: 2)); // the name goes away
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the app\'s icon, in the top left corner, goes to the home, which the side rail doesn\'t list', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    final logo = find.byTooltip('Início');
    expect(logo, findsOneWidget, reason: 'the app\'s icon alone');
    expect(find.descendant(of: logo, matching: find.byType(Image)), findsOneWidget);
    expect(themedIcon(HugeIcons.strokeRoundedHome01), findsNothing);
    final corner = tester.getRect(logo);
    expect(corner.left, lessThan(16));
    expect(corner.top, lessThan(16));
    expect(corner.right, lessThanOrEqualTo(railWidth(tester)), reason: 'over the side rail');

    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Artistas'), findsOneWidget);
    expect(shown('Lançamentos'), findsNothing);

    await tester.tap(logo);
    await tester.pumpAndSettle();
    expectHomeInRail();
    expect(shown('Lançamentos'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the app in the old theme fades away over the new one', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final choice = ThemeChoice();
    addTearDown(choice.dispose);
    await pumpHome(tester, const Size(1000, 700), themeChoice: choice);
    final old = find.byKey(ThemeFade.oldThemeKey);
    double opacity() => tester.widget<FadeTransition>(old).opacity.value;

    await openSettings(tester);
    await openChoice(tester, 'Tema');
    await tester.tap(option('Tema escuro'));
    await tester.pump();
    expect(Theme.of(tester.element(find.byType(HomePage))).brightness, Brightness.dark, reason: 'at once, under it');
    expect(old, findsOneWidget, reason: 'the app as it was, in the light theme');
    expect(tester.getRect(old), Offset.zero & const Size(1000, 700), reason: 'over all of it');
    expect(opacity(), 1);

    await tester.pump(ThemeFade.duration ~/ 4);
    final quarter = opacity();
    expect(quarter, lessThan(1));
    await tester.pump(ThemeFade.duration ~/ 4);
    expect(opacity(), moreOrLessEquals(0.5, epsilon: 0.01));
    expect(1 - quarter, lessThan(0.25), reason: 'slow at the start, fast through the middle, where it is gray');

    await tester.pumpAndSettle();
    expect(old, findsNothing, reason: 'faded away');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('where the system asks for less motion, the new theme shows at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final choice = ThemeChoice();
    addTearDown(choice.dispose);
    await pumpHome(tester, const Size(1000, 700), themeChoice: choice);
    await openSettings(tester);
    await openChoice(tester, 'Tema');
    await tester.tap(option('Tema escuro'));
    await tester.pump();
    expect(find.byKey(ThemeFade.oldThemeKey), findsNothing);
    expect(Theme.of(tester.element(find.byType(HomePage))).brightness, Brightness.dark);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the theme, the language, the version and signing out are in the settings, a page whose button '
    'comes after the hub\'s status; each choice says the option picked, and opens a sheet of them all',
    (tester) async {
      final (themeChoice, languageChoice) = (ThemeChoice(), LanguageChoice());
      addTearDown(themeChoice.dispose);
      addTearDown(languageChoice.dispose);
      // A phone tall enough for every item of the settings, which their list builds only near the screen.
      await pumpHome(
        tester,
        const Size(360, 800),
        themeChoice: themeChoice,
        languageChoice: languageChoice,
        packageInfo: PackageInfo(appName: 'Segue', packageName: 'segue', version: '0.1.0', buildNumber: '214'),
      );

      for (final tooltip in ['Tema escuro', 'Tema claro', 'Idioma', 'Sair']) {
        expect(find.byTooltip(tooltip), findsNothing, reason: 'no button of its own: $tooltip');
      }

      expect(
        tester.getRect(settingsButton).left,
        greaterThanOrEqualTo(tester.getRect(find.byTooltip('Sem hub: só toca neste aparelho')).right),
        reason: 'the hub\'s status in sight, before the settings',
      );
      expect(find.descendant(of: settingsButton, matching: themedIcon(HugeIcons.strokeRoundedSettings01)), findsOne);

      await openSettings(tester);
      expect(title('Configurações'), findsOneWidget);
      expect(find.byType(BackButton).hitTestable(), findsOneWidget, reason: 'a page of its own, which goes back');
      expect(find.byType(NavigationBar).hitTestable(), findsOneWidget, reason: 'in the page area, over the section');
      final texts = [
        'Aparência',
        'Tema',
        'Tema do sistema',
        'Cores',
        'Segue',
        'Alto contraste',
        'Idioma',
        'Idioma do sistema',
        'Sobre',
        'Versão',
        '0.1.0 (214)',
        'Licenças de código aberto',
        'Sair',
      ];
      final tops = [for (final text in texts) tester.getTopLeft(find.text(text)).dy];
      expect([...tops]..sort(), tops, reason: 'in this order, top to bottom');
      expect(find.text('Reprodução'), findsNothing, reason: 'with nothing in it to pick');
      expect(find.text('Tema claro'), findsNothing, reason: 'in the sheet of the themes alone');
      final lines = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Divider));
      expect(lines, findsNWidgets(2), reason: 'a line after each group');
      expect(
        tester.getCenter(lines.at(0)).dy,
        inExclusiveRange(tops[texts.indexOf('Idioma do sistema')], tops[texts.indexOf('Sobre')]),
        reason: 'between the appearance and the app\'s version, over the licenses',
      );
      expect(
        tester.getCenter(lines.at(1)).dy,
        inExclusiveRange(tops[texts.indexOf('Licenças de código aberto')], tops[texts.indexOf('Sair')]),
        reason: 'as before signing out',
      );

      for (final (item, data) in [
        ('Tema', HugeIcons.strokeRoundedContrast),
        ('Cores', HugeIcons.strokeRoundedPaintBoard),
        ('Alto contraste', HugeIcons.strokeRoundedView),
        ('Idioma', HugeIcons.strokeRoundedTranslate),
        ('Versão', HugeIcons.strokeRoundedInformationCircle),
        ('Licenças de código aberto', HugeIcons.strokeRoundedLicense),
        ('Sair', HugeIcons.strokeRoundedLogout01),
      ]) {
        expect(
          find.descendant(of: settingsItem(item), matching: themedIcon(data)),
          findsOneWidget,
          reason: item,
        );
      }

      expect(tester.widget<ListTile>(settingsItem('Versão')).onTap, isNull, reason: 'only shown');
      expect(says('Tema', 'Tema do sistema'), isTrue, reason: 'the system\'s theme and language, until a pick');
      expect(says('Cores', 'Segue'), isTrue, reason: 'the icon\'s pink, until a pick');
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Alto contraste')).value, isFalse);
      expect(says('Idioma', 'Idioma do sistema'), isTrue);

      // The themes, in a sheet over the window, under the choice's name.
      await openChoice(tester, 'Tema');
      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: find.text('Tema')), findsOneWidget);
      expect(tester.getRect(sheet).bottom, 800, reason: 'over the bars at the bottom too');
      final themes = ['Tema do sistema', 'Tema claro', 'Tema escuro'];
      final themeTops = [for (final text in themes) tester.getTopLeft(option(text)).dy];
      expect([...themeTops]..sort(), themeTops, reason: 'in this order, top to bottom');
      expect([for (final text in themes) checked(text)], [true, false, false]);
      expect(tester.widget<ListTile>(option('Tema do sistema')).selected, isTrue, reason: 'in the theme\'s color');
      expect(tester.widget<ListTile>(option('Tema claro')).selected, isFalse);
      await closeChoice(tester);

      await openChoice(tester, 'Idioma');
      final languages = ['Idioma do sistema', 'English', 'Español', 'Português'];
      final languageTops = [for (final text in languages) tester.getTopLeft(option(text)).dy];
      expect([...languageTops]..sort(), languageTops, reason: 'in this order, top to bottom');
      expect([for (final text in languages) checked(text)], [true, false, false, false]);
      await closeChoice(tester);

      expect(
        find.descendant(of: settingsItem('Sair'), matching: find.text('a em music.test')),
        findsOneWidget,
        reason: 'the account it signs out of',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
      expect(title('Segue Music'), findsOneWidget);

      await openSettings(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Biblioteca')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing, reason: 'a section picked closes it');
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(TabBar)), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a wide screen too, the settings are a page, in the page area, whose button comes after the hub\'s '
      'status: the top bar has no button of its own for the theme, the language, the quality or signing out', (
    tester,
  ) async {
    final (themeChoice, languageChoice, qualityChoice) = (ThemeChoice(), LanguageChoice(), QualityChoice());
    addTearDown(themeChoice.dispose);
    addTearDown(languageChoice.dispose);
    addTearDown(qualityChoice.dispose);
    var signedOut = false;
    await pumpHome(
      tester,
      const Size(1000, 700),
      themeChoice: themeChoice,
      languageChoice: languageChoice,
      qualityChoice: qualityChoice,
      onSignOut: () => signedOut = true,
    );

    for (final tooltip in ['Tema escuro', 'Tema claro', 'Idioma', 'Qualidade do áudio', 'Sair']) {
      expect(find.byTooltip(tooltip), findsNothing, reason: 'no button of its own: $tooltip');
    }

    expect(
      tester.getRect(settingsButton).left,
      greaterThanOrEqualTo(tester.getRect(find.byTooltip('Sem hub: só toca neste aparelho')).right),
      reason: 'the hub\'s status in sight, before the settings',
    );

    await openSettings(tester);
    final page = tester.getRect(find.byType(SettingsPage));
    expect(page.top, greaterThanOrEqualTo(tester.getRect(settingsButton).bottom), reason: 'under the top bar');
    expect(page.left, greaterThanOrEqualTo(tester.getRect(find.byType(VerticalDivider)).right), reason: 'by the rail');
    expect(find.byType(BackButton), findsNothing, reason: 'the top bar\'s arrow goes back');
    expect(says('Tema', 'Tema do sistema'), isTrue, reason: 'which the button had no way back to');
    expect(says('Qualidade do áudio', 'Qualidade original'), isTrue);
    await openChoice(tester, 'Qualidade do áudio');
    expect(checked('Qualidade original'), isTrue);
    expect(option('Qualidade baixa · 96 kbps'), findsOneWidget);
    expect(
      find.text('Qualidade automática', skipOffstage: false),
      findsNothing,
      reason: 'a computer has no mobile data, where it would stream other than the original',
    );
    await closeChoice(tester);
    expect(find.byType(SettingsPage), findsOneWidget, reason: 'Esc closes the sheet alone');
    final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable));

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);

    await openSettings(tester);
    await tester.scrollUntilVisible(settingsItem('Sair'), 100, scrollable: list);
    await tester.ensureVisible(settingsItem('Sair'));
    await tester.pumpAndSettle();
    await tester.tap(settingsItem('Sair'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, the settings open the licenses in the page area, with no arrow of their own, nor a '
      'package\'s: the top bar\'s goes back through them', (tester) async {
    LicenseRegistry.reset();
    LicenseRegistry.addLicense(() => Stream.value(const LicenseEntryWithLineBreaks(['segue'], 'MIT License')));
    addTearDown(LicenseRegistry.reset);
    await pumpHome(tester, const Size(1000, 700));
    await openSettings(tester);
    await tester.tap(settingsItem('Licenças de código aberto'));
    await tester.pumpAndSettle();
    expect(title('Licenças'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing, reason: 'the top bar\'s arrow goes back');

    await tester.tap(find.text('segue'));
    await tester.pumpAndSettle();
    expect(title('segue'), findsOneWidget);
    expect(shown('MIT License'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(title('Licenças'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(title('Configurações'), findsOneWidget);
    await tester.tap(find.byTooltip('Avançar'));
    await tester.pumpAndSettle();
    expect(title('Licenças'), findsOneWidget, reason: 'and forward to them again');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, Esc closes the settings, as the top bar\'s arrow does, also from a setting with the '
      'focus', (tester) async {
    final themeChoice = ThemeChoice();
    addTearDown(themeChoice.dispose);
    await pumpHome(tester, const Size(1000, 700), themeChoice: themeChoice);
    final settings = find.byType(SettingsPage);

    await openSettings(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(settings, findsNothing);

    await tester.tap(find.byTooltip('Avançar'));
    await tester.pumpAndSettle();
    expect(settings, findsOneWidget, reason: 'and forward to them again');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused?.findAncestorWidgetOfExactType<ListTile>(), isNotNull, reason: 'a setting has the focus');
    expect(focused?.findAncestorWidgetOfExactType<SettingsPage>(), isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(settings, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, where the top bar stays over the settings, its button goes back from them rather than '
      'opening them again', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    // The pages under the one on top too.
    final settings = find.byType(SettingsPage, skipOffstage: false);

    await openSettings(tester);
    expect(settings, findsOneWidget);

    await openSettings(tester);
    expect(settings, findsNothing, reason: 'back to the section');

    for (var i = 0; i < 3; i++) {
      await openSettings(tester);
    }

    expect(settings, findsOneWidget, reason: 'open, and once only, however many clicks');

    await openSettings(tester);
    await tester.tap(find.byTooltip('Avançar'));
    await tester.pumpAndSettle();
    expect(settings, findsOneWidget, reason: 'open again, going forward');

    await openSettings(tester);
    expect(settings, findsNothing, reason: 'going back from it too');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the settings pick the theme, the old one fading away, and the system\'s again', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final choice = ThemeChoice();
    addTearDown(choice.dispose);
    await pumpHome(tester, const Size(360, 640), themeChoice: choice);
    Brightness shown() => Theme.of(tester.element(find.byType(HomePage))).brightness;

    await openSettings(tester);
    await openChoice(tester, 'Tema');
    await tester.tap(option('Tema escuro'));
    await tester.pump();
    expect(shown(), Brightness.dark);
    expect(find.byKey(ThemeFade.oldThemeKey), findsOneWidget, reason: 'the app as it was, in the light theme');
    await tester.pumpAndSettle();
    expect(find.byKey(ThemeFade.oldThemeKey), findsNothing, reason: 'faded away');
    expect(find.byType(BottomSheet), findsNothing, reason: 'the pick closed the sheet');
    expect((await ThemeChoice.load()).value.mode, ThemeMode.dark, reason: 'kept for the next launch');
    expect(find.byType(SettingsPage), findsOneWidget, reason: 'still open');
    expect(says('Tema', 'Tema escuro'), isTrue);

    await openChoice(tester, 'Tema');
    expect([checked('Tema do sistema'), checked('Tema escuro')], [false, true], reason: 'the check moved');
    await pick(tester, 'Tema do sistema');
    expect(shown(), Brightness.light, reason: 'the system\'s again');
    expect((await ThemeChoice.load()).value.mode, ThemeMode.system);
    expect(says('Tema', 'Tema do sistema'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the settings pick the colors, each beside its own, and turn the high contrast on and off, the old theme '
      'fading away each time', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final choice = ThemeChoice();
    addTearDown(choice.dispose);
    await pumpHome(tester, const Size(360, 640), themeChoice: choice);
    ColorScheme shown() => Theme.of(tester.element(find.byType(HomePage))).colorScheme;
    final fading = find.byKey(ThemeFade.oldThemeKey);
    expect(shown().surface, iconBlack);

    await openSettings(tester);
    await openChoice(tester, 'Cores');
    final palettes = ['Segue', 'Vinho', 'Neutro'];
    final tops = [for (final text in palettes) tester.getTopLeft(option(text)).dy];
    expect([...tops]..sort(), tops, reason: 'in this order, top to bottom');
    expect([for (final text in palettes) checked(text)], [true, false, false]);
    expect(
      find.descendant(
        of: option('Vinho'),
        matching: find.text('O vinho de dentro do ícone no escuro, e fundos rosados no claro'),
      ),
      findsOneWidget,
      reason: 'what it is, under it',
    );

    // Beside each, its colors, in the theme shown: its background and its pink.
    for (final (text, palette) in [('Segue', Palette.segue), ('Vinho', Palette.wine), ('Neutro', Palette.neutral)]) {
      final colors = segueColors(Brightness.dark, palette: palette);
      // The circle, and the dot in it.
      final circles = find.descendant(
        of: option(text),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && (widget.decoration as BoxDecoration?)?.shape == BoxShape.circle,
        ),
      );
      final (swatch, dot) = (
        tester.widget<Container>(circles.first).decoration! as BoxDecoration,
        tester.widget<Container>(circles.last).decoration! as BoxDecoration,
      );
      expect(swatch.gradient?.colors.first, colors.surface, reason: text);
      expect(dot.color, colors.primary, reason: text);
    }

    await tester.tap(option('Vinho'));
    await tester.pump();
    expect(shown().surface, iconWine, reason: 'at once');
    expect(fading, findsOneWidget, reason: 'the app as it was, on the black');
    await tester.pumpAndSettle();
    expect(fading, findsNothing);
    expect(find.byType(BottomSheet), findsNothing, reason: 'the pick closed the sheet');
    expect(says('Cores', 'Vinho'), isTrue);
    expect((await ThemeChoice.load()).value.palette, Palette.wine, reason: 'kept for the next launch');

    final highContrast = find.widgetWithText(SwitchListTile, 'Alto contraste');
    await tester.tap(highContrast);
    await tester.pump();
    expect(shown(), segueColors(Brightness.dark, palette: Palette.wine, highContrast: true), reason: 'with the colors');
    expect(fading, findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(highContrast).value, isTrue);
    expect((await ThemeChoice.load()).value.highContrast, isTrue, reason: 'kept for the next launch');

    await tester.tap(highContrast);
    await tester.pumpAndSettle();
    expect(shown(), segueColors(Brightness.dark, palette: Palette.wine));
    expect((await ThemeChoice.load()).value, const ThemeSettings(palette: Palette.wine));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the quality is in the settings, after the language, under the playback, before signing out: the '
    'original first, picked until another is, then the automatic one, which a phone has mobile data for',
    (tester) async {
      final (themeChoice, languageChoice, qualityChoice) = (
        ThemeChoice(),
        LanguageChoice(),
        QualityChoice(mobileData: true),
      );
      addTearDown(themeChoice.dispose);
      addTearDown(languageChoice.dispose);
      addTearDown(qualityChoice.dispose);
      await pumpHome(
        tester,
        const Size(360, 640),
        themeChoice: themeChoice,
        languageChoice: languageChoice,
        qualityChoice: qualityChoice,
      );
      expect(find.byTooltip('Qualidade do áudio'), findsNothing, reason: 'no button of its own');

      await openSettings(tester);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Idioma'), lessThan(top('Reprodução')), reason: 'after the language');
      expect(top('Reprodução'), lessThan(top('Qualidade do áudio')), reason: 'under the playback');
      expect(says('Qualidade do áudio', 'Qualidade original'), isTrue);
      expect(
        find.descendant(
          of: settingsItem('Qualidade do áudio'),
          matching: themedIcon(HugeIcons.strokeRoundedAudioWave01),
        ),
        findsOneWidget,
      );

      // To its end, which stays clear of the bars at the bottom.
      final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable));
      await tester.fling(list, const Offset(0, -1000), 3000);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(settingsItem('Sair')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
      );

      await openChoice(tester, 'Qualidade do áudio');
      final texts = [
        'Qualidade original',
        'Qualidade automática',
        'Qualidade alta · 320 kbps',
        'Qualidade normal · 160 kbps',
        'Qualidade baixa · 96 kbps',
      ];
      final tops = [for (final text in texts) tester.getTopLeft(option(text)).dy];
      expect([...tops]..sort(), tops, reason: 'in this order, top to bottom, the original first');
      expect([for (final text in texts) checked(text)], [true, false, false, false, false]);
      expect(
        find.descendant(
          of: option('Qualidade automática'),
          matching: find.text('Original no Wi-Fi, 160 kbps nos dados móveis'),
        ),
        findsOneWidget,
        reason: 'what it does, under it',
      );

      await pick(tester, 'Qualidade normal · 160 kbps');
      expect(qualityChoice.value, StreamQuality.normal);
      expect((await QualityChoice.load(mobileData: true)).value, StreamQuality.normal);
      expect(says('Qualidade do áudio', 'Qualidade normal · 160 kbps'), isTrue);
      await openChoice(tester, 'Qualidade do áudio');
      expect([checked('Qualidade original'), checked('Qualidade normal · 160 kbps')], [false, true]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a phone, the volume\'s normalization is in the settings, after the quality, each way with what it '
      'does; a pick holds, and is kept', (tester) async {
    final (qualityChoice, replayGainChoice) = (QualityChoice(), ReplayGainChoice());
    addTearDown(qualityChoice.dispose);
    addTearDown(replayGainChoice.dispose);
    await pumpHome(tester, const Size(360, 640), qualityChoice: qualityChoice, replayGainChoice: replayGainChoice);

    await openSettings(tester);
    expect(
      tester.getTopLeft(find.text('Qualidade do áudio')).dy,
      lessThan(tester.getTopLeft(find.text('Normalização do volume')).dy),
      reason: 'after the quality',
    );
    expect(
      find.descendant(
        of: settingsItem('Normalização do volume'),
        matching: themedIcon(HugeIcons.strokeRoundedVolumeHigh),
      ),
      findsOneWidget,
    );
    expect(says('Normalização do volume', 'Desligada'), isTrue, reason: 'until a pick');

    await openChoice(tester, 'Normalização do volume');
    final ways = [
      ('Desligada', 'Cada música no volume do seu arquivo'),
      ('Automática', 'Por álbum quando um álbum toca em ordem, por música nas outras vezes'),
      ('Por música', 'Todas as músicas no mesmo volume'),
      ('Por álbum', 'Todos os álbuns no mesmo volume, e as músicas de cada um como são entre si'),
    ];
    final tops = [for (final (name, _) in ways) tester.getTopLeft(option(name)).dy];
    expect([...tops]..sort(), tops, reason: 'in this order, top to bottom, off first');
    expect(checked('Desligada'), isTrue);

    for (final (name, detail) in ways) {
      expect(
        find.descendant(of: option(name), matching: find.text(detail)),
        findsOneWidget,
        reason: name,
      );
    }

    await pick(tester, 'Por álbum');
    expect(replayGainChoice.value, ReplayGainMode.album);
    expect((await ReplayGainChoice.load()).value, ReplayGainMode.album);
    expect(says('Normalização do volume', 'Por álbum'), isTrue);
    await openChoice(tester, 'Normalização do volume');
    expect([checked('Desligada'), checked('Por álbum')], [false, true]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the equalizer is in the settings, after the volume\'s normalization, with the curve it plays '
    'with, and opens its page, whose changes it shows',
    (tester) async {
      final (replayGainChoice, equalizerChoice) = (ReplayGainChoice(), EqualizerChoice());
      addTearDown(replayGainChoice.dispose);
      addTearDown(equalizerChoice.dispose);
      await pumpHome(
        tester,
        const Size(360, 640),
        replayGainChoice: replayGainChoice,
        equalizerChoice: equalizerChoice,
      );

      await openSettings(tester);
      final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable));
      // To the end, so that the bars at the bottom leave it in sight.
      await tester.scrollUntilVisible(settingsItem('Sair'), 100, scrollable: list);
      expect(
        tester.getTopLeft(find.text('Equalizador')).dy,
        greaterThan(tester.getTopLeft(find.text('Normalização do volume')).dy),
        reason: 'after the volume\'s normalization',
      );
      expect(find.descendant(of: settingsItem('Equalizador'), matching: find.text('Desligado')), findsOneWidget);

      await tester.tap(settingsItem('Equalizador'));
      await tester.pumpAndSettle();
      expect(title('Equalizador'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Jazz'));
      await tester.pumpAndSettle();
      expect(equalizerChoice.value, const EqualizerSettings(on: true, preset: EqualizerPreset.jazz));

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: settingsItem('Equalizador'), matching: find.text('Jazz')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a phone, the settings sign out, and with nothing else to pick have only that and the licenses', (
    tester,
  ) async {
    var signedOut = false;
    await pumpHome(tester, const Size(360, 640), onSignOut: () => signedOut = true);
    await openSettings(tester);
    expect(find.descendant(of: find.byType(SettingsPage), matching: find.byType(ListTile)), findsNWidgets(2));
    expect(settingsItem('Licenças de código aberto'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget, reason: 'between them');

    await tester.tap(settingsItem('Sair'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the hub\'s status sits as far from the settings\' button as two buttons are from each other',
    (tester) async {
      await pumpHome(tester, const Size(1000, 700));

      Rect icon(HugeIconData icon) =>
          tester.getRect(find.descendant(of: find.byType(AppBar), matching: themedIcon(icon)));

      final (hub, settings) = (icon(HugeIcons.strokeRoundedUnlink02), icon(HugeIcons.strokeRoundedSettings01));
      final button = tester.getSize(
        find.ancestor(of: themedIcon(HugeIcons.strokeRoundedSettings01), matching: find.byType(IconButton)),
      );
      expect(settings.left - hub.right, button.width - settings.width);
      expect(hub.center.dy, settings.center.dy);
      await tester.pumpWidget(const SizedBox());
    },
    // Buttons are smaller on a desktop.
    variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.linux}),
  );

  for (final (device, kind, size) in [
    ('a finger, on a phone', PointerDeviceKind.touch, const Size(360, 640)),
    ('the mouse, on a computer', PointerDeviceKind.mouse, const Size(1000, 700)),
  ]) {
    testWidgets('dragged down from its top by $device, the home asks the server for its rows again', (tester) async {
      final asked = await pumpHome(tester, size);
      final rows = [for (final query in asked) query['type']];
      expect(rows, unorderedEquals(['byYear', 'frequent', 'newest']));

      final list = find.descendant(of: find.byType(HomeView), matching: find.byType(Scrollable)).first;
      await tester.dragFrom(tester.getTopLeft(list) + const Offset(300, 100), const Offset(0, 300), kind: kind);
      await tester.pumpAndSettle();
      expect([for (final query in asked.skip(rows.length)) query['type']], unorderedEquals(rows));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('on a phone, the app\'s icon is in the top left corner too, on the home, and the bar at the bottom keeps '
      'the home', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    final logo = find.descendant(of: find.byType(AppBar), matching: find.byTooltip('Início'));
    final bar = find.byType(NavigationBar);
    expect(tester.getRect(logo).left, lessThan(16));
    expect(find.descendant(of: bar, matching: find.text('Início')), findsOneWidget);

    expect(title('Segue Music'), findsOneWidget);

    // Elsewhere, what there is to use there takes its place, and the bar's home opens the home.
    await tester.tap(find.descendant(of: bar, matching: find.text('Biblioteca')));
    await tester.pumpAndSettle();
    expect(logo, findsNothing);
    expect(title('Biblioteca'), findsNothing);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(TabBar)), findsOneWidget);
    expect(
      tester.getTopLeft(find.descendant(of: find.byType(TabBar), matching: find.text('Álbuns'))).dx,
      16,
      reason: 'the first tab\'s name lined up with what the library shows under it',
    );

    await tester.tap(find.descendant(of: bar, matching: find.text('Início')));
    await tester.pumpAndSettle();
    expect(title('Segue Music'), findsOneWidget);
    expect(tester.getRect(logo).left, lessThan(16));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the bar at the bottom has the home, the search and the library, whose albums, artists and '
      'playlists are tabs at its top; it opens again on the one picked last', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    final bar = find.byType(NavigationBar);
    expect(
      [
        for (final destination in tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)))
          destination.label,
      ],
      ['Início', 'Buscar', 'Biblioteca'],
    );

    await tester.tap(find.descendant(of: bar, matching: find.text('Biblioteca')));
    await tester.pumpAndSettle();
    final tabs = find.byType(TabBar);
    expect(find.descendant(of: tabs, matching: find.byType(Tab)), findsNWidgets(3));
    expect(
      [for (final tab in tester.widgetList<Tab>(find.descendant(of: tabs, matching: find.byType(Tab)))) tab.text],
      ['Álbuns', 'Artistas', 'Playlists'],
    );
    expect(tester.widget<TabBar>(tabs).controller?.index, 0, reason: 'the albums first');
    expect(find.byType(AlbumsView), findsOneWidget);

    await tapLibraryTab(tester, 'Artistas');
    expect(find.byType(AlbumsView), findsNothing);
    expect(find.byType(ArtistsView), findsOneWidget);

    await tester.tap(find.descendant(of: bar, matching: find.text('Início')));
    await tester.pumpAndSettle();
    expect(tabs, findsNothing);
    await tester.tap(find.descendant(of: bar, matching: find.text('Biblioteca')));
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(tabs).controller?.index, 1);
    expect(find.byType(ArtistsView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a swipe goes from the home to the search and on through the library\'s tabs, and back', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 640));
    final bar = find.byType(NavigationBar);
    final tabs = find.byType(TabBar);
    int destination() => tester.widget<NavigationBar>(bar).selectedIndex;
    TabController tab() => tester.widget<TabBar>(tabs).controller!;
    Future<void> swipe(Finder from, double dx) async {
      await tester.drag(from, Offset(dx, 0));
      await tester.pumpAndSettle();
    }

    // From a row's title: along a row, a swipe goes along it.
    await swipe(find.text('Mais tocados'), -300);
    expect(destination(), 1);
    expect(find.byType(GenresView), findsOneWidget);
    expect(find.byType(HomeView), findsNothing);
    await swipe(find.byType(GenresView), -300);
    expect(destination(), 2);
    expect(tab().index, 0);
    expect(find.byType(AlbumsView), findsOneWidget);

    // Between two tabs, the line under them follows the swipe.
    final gesture = await tester.startGesture(tester.getCenter(find.byType(AlbumsView)));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-70, 0));
    await tester.pump();
    expect(tab().animation!.value, moreOrLessEquals(0.25, epsilon: 0.01));
    expect(tab().index, 0);
    await gesture.moveBy(const Offset(-180, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tab().index, 1);
    expect(tab().animation!.value, 1);
    expect(find.byType(ArtistsView), findsOneWidget);

    await swipe(find.byType(ArtistsView), -300);
    expect(tab().index, 2);
    expect(find.byType(PlaylistsView), findsOneWidget);
    await swipe(find.byType(PlaylistsView), -300);
    expect(find.byType(PlaylistsView), findsOneWidget, reason: 'the last');

    // A section picked in the bar, then swiped from.
    await tester.tap(find.descendant(of: bar, matching: find.text('Início')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: bar, matching: find.text('Biblioteca')));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistsView), findsOneWidget, reason: 'the tab swiped to last');
    await swipe(find.byType(PlaylistsView), 300);
    expect(tab().index, 1);
    await swipe(find.byType(ArtistsView), 300);
    await swipe(find.byType(AlbumsView), 300);
    expect(destination(), 1);
    await swipe(find.byType(GenresView), 300);
    expect(destination(), 0);
    expect(find.byType(HomeView), findsOneWidget);
    await swipe(find.text('Mais tocados'), 300);
    expect(find.byType(HomeView), findsOneWidget, reason: 'the first');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, up from the side rail goes to the app\'s icon, which goes to the home', (tester) async {
    await pumpHome(tester, const Size(960, 540), television: true);
    await tester.tap(find.byTooltip('Álbuns'));
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.descendant(of: find.byTooltip('Álbuns'), matching: find.byType(ThemedIcon))))
        .requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(Focus.of(tester.element(find.byType(Image).first)).hasFocus, isTrue);

    await press(tester, LogicalKeyboardKey.enter);
    expectHomeInRail();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a row goes on sideways', (tester) async {
    await pumpHome(tester, const Size(360, 640), released: [for (var i = 0; i < 10; i++) 'Released $i']);
    expect(find.text('Released 0'), findsOneWidget);
    expect(find.text('Released 9'), findsNothing);
    await tester.drag(find.text('Released 0'), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(find.text('Released 9'), findsOneWidget);
    expect(find.text('Pump'), findsOneWidget, reason: 'the other rows stay');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the home pulled down, its rows start again from their first album', (tester) async {
    final asked = await pumpHome(tester, const Size(360, 640), released: [for (var i = 0; i < 10; i++) 'Released $i']);
    final rows = asked.length;
    await tester.drag(find.text('Released 0'), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(find.text('Released 0'), findsNothing);
    expect(find.text('Released 9'), findsOneWidget);

    final list = find.descendant(of: find.byType(HomeView), matching: find.byType(Scrollable)).first;
    await tester.dragFrom(tester.getTopLeft(list) + const Offset(180, 20), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(asked.length, 2 * rows, reason: 'listed again');
    expect(find.text('Released 0'), findsOneWidget);
    expect(find.text('Released 9'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('arrows at the right of a row take it a screenful forward and back, lined up on an album', (
    tester,
  ) async {
    await pumpHome(
      tester,
      const Size(1000, 700),
      mostPlayed: [for (var i = 0; i < 20; i++) 'Most $i'],
      latest: [for (var i = 0; i < 20; i++) 'Latest $i'],
    );
    expect(
      find.descendant(of: rows, matching: find.byType(Scrollbar)),
      findsNothing,
      reason: 'the arrows take the place of the scrollbar a computer gives',
    );
    final back = find.byTooltip('Anteriores').first;
    final forward = find.byTooltip('Próximos').first;
    final heading = tester.getRect(find.text('Mais tocados'));
    expect(tester.getRect(back).left, greaterThan(heading.right));
    expect(tester.getRect(forward).left, greaterThan(tester.getRect(back).right - 1));
    expect(tester.getRect(forward).right, greaterThan(1000 - 64), reason: 'in the right corner');
    expect(tester.getCenter(forward).dy, moreOrLessEquals(heading.center.dy, epsilon: 4));

    final scroll = tester.widget<ListView>(find.ancestor(of: find.text('Most 0'), matching: rows)).controller!;

    bool enabled(Finder arrow) =>
        tester.widget<IconButton>(find.ancestor(of: arrow, matching: find.byType(IconButton)).first).onPressed != null;

    expect(enabled(back), isFalse, reason: 'at the start');
    expect(enabled(forward), isTrue);

    await tester.tap(forward);
    await tester.pumpAndSettle();
    expect(find.text('Most 0'), findsNothing);
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset % (160 + 16), 0, reason: 'an album at the left edge');
    expect(find.text('Latest 0'), findsOneWidget, reason: 'the other row stays');
    expect(enabled(back), isTrue);

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(find.text('Most 0'), findsOneWidget);
    expect(enabled(back), isFalse);

    for (var i = 0; i < 10 && enabled(forward); i++) {
      await tester.tap(forward);
      await tester.pumpAndSettle();
    }

    expect(enabled(forward), isFalse, reason: 'at the end');
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(find.text('Most 19'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on a touch screen, as wide as a tablet\'s, a row has no arrows: a finger drags it', (tester) async {
    await pumpHome(tester, const Size(1000, 700), mostPlayed: [for (var i = 0; i < 20; i++) 'Most $i']);
    expect(find.text('Most 0'), findsOneWidget);
    expect(find.byTooltip('Próximos'), findsNothing);
    expect(find.byTooltip('Anteriores'), findsNothing);
    await tester.drag(find.text('Most 0'), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(find.text('Most 0'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('on a TV, which has no touch screen, a row has its arrows', (tester) async {
    await pumpHome(
      tester,
      const Size(960, 540),
      mostPlayed: [for (var i = 0; i < 20; i++) 'Most $i'],
      television: true,
    );
    expect(find.byTooltip('Próximos'), findsOneWidget);
    expect(find.byTooltip('Anteriores'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a row\'s title opens the albums tab, in the row\'s order', (tester) async {
    final asked = await pumpHome(tester, const Size(1000, 700));

    bool picked(String label) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

    for (final (row, type) in [
      ('Lançamentos', 'byYear'),
      ('Mais tocados', 'frequent'),
      ('Adicionados recentemente', 'newest'),
    ]) {
      await tester.tap(find.byTooltip('Início'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(selectedInRail('Álbuns'), findsOneWidget, reason: row);
      expect(picked(row), isTrue, reason: row);
      expect(asked.last, allOf(containsPair('type', type), containsPair('size', '200')), reason: row);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a row\'s title opens the library on its albums tab, from another tab too, in the row\'s '
      'order', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    final bar = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: bar, matching: find.text('Biblioteca')));
    await tester.pumpAndSettle();
    await tapLibraryTab(tester, 'Artistas');
    await tester.tap(find.descendant(of: bar, matching: find.text('Início')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lançamentos'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bar).selectedIndex, 2);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller?.index, 0);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Lançamentos')).selected, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row whose albums all fit has no arrows', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    expect(find.text('Toys in the Attic'), findsOneWidget);
    expect(find.byTooltip('Próximos'), findsNothing);
    expect(find.byTooltip('Anteriores'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a row has 30 albums at most, even from a server that sends more', (tester) async {
    final asked = await pumpHome(
      tester,
      const Size(360, 640),
      released: [for (var i = 0; i < 40; i++) 'Released $i'],
      mostPlayed: [for (var i = 0; i < 40; i++) 'Most $i'],
      latest: [for (var i = 0; i < 40; i++) 'Latest $i'],
    );
    expect([for (final query in asked) query['size']], ['30', '30', '30']);

    for (final prefix in ['Released', 'Most', 'Latest']) {
      // By its albums: the list builds the rows that show, which change as it scrolls.
      final row = find.ancestor(of: find.text('$prefix 0'), matching: rows);
      await tester.ensureVisible(row); // the last ones are under the bottom bar, at first
      await tester.pumpAndSettle();
      await tester.drag(row, const Offset(-10000, 0));
      await tester.pumpAndSettle();
      expect(find.text('$prefix 29'), findsOneWidget);
      expect(find.text('$prefix 30'), findsNothing);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('before anything has played, the home says what will show there', (tester) async {
    await pumpHome(tester, const Size(1000, 700), mostPlayed: []);
    expect(find.text('Mais tocados'), findsOneWidget);
    expect(find.text('Os álbuns que você mais ouvir aparecem aqui.'), findsOneWidget);
    expect(find.text('Night in the Ruts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row the server fails to list says so, and the other still shows', (tester) async {
    await pumpHome(tester, const Size(1000, 700), mostPlayed: null);
    expect(find.textContaining('Não consegui listar os álbuns'), findsOneWidget);
    expect(find.text('Night in the Ruts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pulling the home down lists every row again', (tester) async {
    final asked = await pumpHome(tester, const Size(360, 640));

    List<String?> types() => [for (final query in asked) query['type']];

    expect(types(), unorderedEquals(['byYear', 'frequent', 'newest']));
    await tester.fling(find.text('Lançamentos'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(types(), unorderedEquals(['byYear', 'frequent', 'newest', 'byYear', 'frequent', 'newest']));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, right goes along a row, scrolling it, and down goes to the next row, past its arrows', (
    tester,
  ) async {
    await pumpHome(
      tester,
      const Size(960, 540),
      mostPlayed: [for (var i = 0; i < 12; i++) 'Most $i'],
      latest: [for (var i = 0; i < 12; i++) 'Latest $i'],
      television: true,
    );

    for (var i = 0; i < 100 && focusedAlbum() != 'Most 0'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(focusedAlbum(), 'Most 0');

    for (var i = 0; i < 7; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }

    expect(focusedAlbum(), 'Most 7');
    expect(tester.getRect(find.text('Most 7')).right, lessThanOrEqualTo(960), reason: 'scrolled into view');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedAlbum(), startsWith('Latest'));
    await tester.pumpWidget(const SizedBox());
  });
}
