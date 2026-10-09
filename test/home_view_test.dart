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
import 'package:segue/ui/album_page.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/home_view.dart';
import 'package:segue/ui/settings_page.dart';
import 'package:segue/ui/shortcuts.dart';
import 'package:segue/ui/theme.dart';
import 'package:segue/ui/theme_fade.dart';
import 'package:segue/ui/themed_icon.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';
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
/// is the version the settings show. Returns the queries of the album lists asked for.
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
        asked.add(query);
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
  Widget app() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('pt')],
    theme: themeChoice == null ? null : segueTheme(Brightness.light),
    darkTheme: themeChoice == null ? null : segueTheme(Brightness.dark),
    themeMode: themeChoice?.value ?? ThemeMode.system,
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

  await tester.pumpWidget(
    themeChoice == null ? app() : ListenableBuilder(listenable: themeChoice, builder: (context, _) => app()),
  );
  await tester.pumpAndSettle();
  return asked;
}

/// The top bar's button that opens the settings.
final settingsButton = find.byTooltip('Configurações');

/// In the settings, the item that says [text].
Finder settingsItem(String text) => find.widgetWithText(ListTile, text);

/// Whether the settings' item that says [text] has the check of the one picked.
bool checked(String text) =>
    find.descendant(of: settingsItem(text), matching: themedIcon(HugeIcons.strokeRoundedTick02)).evaluate().isNotEmpty;

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
    await tester.tap(settingsItem('Tema escuro'));
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
    await tester.tap(settingsItem('Tema escuro'));
    await tester.pump();
    expect(find.byKey(ThemeFade.oldThemeKey), findsNothing);
    expect(Theme.of(tester.element(find.byType(HomePage))).brightness, Brightness.dark);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the theme, the language, the version and signing out are in the settings, a page whose button '
    'comes after the hub\'s status',
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
        'Tema',
        'Tema do sistema',
        'Tema claro',
        'Tema escuro',
        'Idioma',
        'Idioma do sistema',
        'English',
        'Español',
        'Português',
        'Versão',
        '0.1.0 (214)',
        'Licenças de código aberto',
        'Sair',
      ];
      final tops = [for (final text in texts) tester.getTopLeft(find.text(text)).dy];
      expect([...tops]..sort(), tops, reason: 'in this order, top to bottom');
      final lines = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Divider));
      expect(lines, findsNWidgets(3), reason: 'a line after each group');
      expect(
        tester.getCenter(lines.at(0)).dy,
        inExclusiveRange(tops[texts.indexOf('Tema escuro')], tops[texts.indexOf('Idioma')]),
        reason: 'between the themes and the languages',
      );
      expect(
        tester.getCenter(lines.at(1)).dy,
        inExclusiveRange(tops[texts.indexOf('Português')], tops[texts.indexOf('Versão')]),
        reason: 'between the languages and the version, over the licenses',
      );
      expect(
        tester.getCenter(lines.at(2)).dy,
        inExclusiveRange(tops[texts.indexOf('Licenças de código aberto')], tops[texts.indexOf('Sair')]),
        reason: 'as before signing out',
      );
      expect(
        find.descendant(of: settingsItem('Versão'), matching: themedIcon(HugeIcons.strokeRoundedInformationCircle)),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(settingsItem('Versão')).onTap, isNull, reason: 'only shown');
      expect(
        find.descendant(
          of: settingsItem('Licenças de código aberto'),
          matching: themedIcon(HugeIcons.strokeRoundedLicense),
        ),
        findsOneWidget,
      );
      final options = texts
          .where((text) => !{'Tema', 'Idioma', 'Versão', '0.1.0 (214)', 'Licenças de código aberto'}.contains(text))
          .toList();
      expect(
        [for (final text in options) checked(text)],
        [true, false, false, true, false, false, false, false],
        reason: 'the system\'s theme and language, until a pick',
      );
      expect(
        tester.widget<ListTile>(settingsItem('Tema do sistema')).selected,
        isTrue,
        reason: 'in the theme\'s color',
      );
      expect(tester.widget<ListTile>(settingsItem('Tema claro')).selected, isFalse);
      expect(
        find.descendant(of: settingsItem('Sair'), matching: themedIcon(HugeIcons.strokeRoundedLogout01)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: settingsItem('Sair'), matching: find.text('a em music.test')),
        findsOneWidget,
        reason: 'the account it signs out of',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
      expect(title('Início'), findsOneWidget);

      await openSettings(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Álbuns')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing, reason: 'a section picked closes it');
      expect(title('Álbuns'), findsOneWidget);
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
    expect(checked('Tema do sistema'), isTrue, reason: 'which the button had no way back to');
    expect(checked('Qualidade automática'), isTrue);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);

    await openSettings(tester);
    final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable));
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
    await tester.tap(settingsItem('Tema escuro'));
    await tester.pump();
    expect(shown(), Brightness.dark);
    expect(find.byKey(ThemeFade.oldThemeKey), findsOneWidget, reason: 'the app as it was, in the light theme');
    await tester.pumpAndSettle();
    expect(find.byKey(ThemeFade.oldThemeKey), findsNothing, reason: 'faded away');
    expect((await ThemeChoice.load()).value, ThemeMode.dark, reason: 'kept for the next launch');
    expect(find.byType(SettingsPage), findsOneWidget, reason: 'still open');
    expect([checked('Tema do sistema'), checked('Tema escuro')], [false, true], reason: 'the check moved');

    await tester.tap(settingsItem('Tema do sistema'));
    await tester.pumpAndSettle();
    expect(shown(), Brightness.light, reason: 'the system\'s again');
    expect((await ThemeChoice.load()).value, ThemeMode.system);
    expect([checked('Tema do sistema'), checked('Tema escuro')], [true, false]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the quality is in the settings, after the languages, before signing out', (tester) async {
    final (themeChoice, languageChoice, qualityChoice) = (ThemeChoice(), LanguageChoice(), QualityChoice());
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
    // More than a phone's screen: down to the qualities.
    final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(settingsItem('Qualidade automática'), 100, scrollable: list);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Português'), lessThan(top('Qualidade do áudio')), reason: 'after the languages');
    expect(top('Qualidade do áudio'), lessThan(top('Qualidade automática')), reason: 'under its name');
    expect(checked('Qualidade automática'), isTrue);
    expect(
      find.descendant(
        of: settingsItem('Qualidade automática'),
        matching: find.text('Original no Wi-Fi, 160 kbps nos dados móveis'),
      ),
      findsOneWidget,
      reason: 'what it does, under it',
    );

    // To its end, which stays clear of the bars at the bottom.
    await tester.fling(list, const Offset(0, -1000), 3000);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(settingsItem('Sair')).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
    );
    final texts = [
      'Qualidade original',
      'Qualidade alta · 320 kbps',
      'Qualidade normal · 160 kbps',
      'Qualidade baixa · 96 kbps',
      'Sair',
    ];
    final tops = [for (final text in texts) top(text)];
    expect([...tops]..sort(), tops, reason: 'in this order, top to bottom, signing out last');

    await tester.tap(settingsItem('Qualidade normal · 160 kbps'));
    await tester.pumpAndSettle();
    expect(qualityChoice.value, StreamQuality.normal);
    expect((await QualityChoice.load()).value, StreamQuality.normal);
    expect([checked('Qualidade automática'), checked('Qualidade normal · 160 kbps')], [false, true]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the volume\'s normalization is in the settings, after the qualities, each way with what it '
      'does; a pick holds, and is kept', (tester) async {
    final (qualityChoice, replayGainChoice) = (QualityChoice(), ReplayGainChoice());
    addTearDown(qualityChoice.dispose);
    addTearDown(replayGainChoice.dispose);
    await pumpHome(tester, const Size(360, 640), qualityChoice: qualityChoice, replayGainChoice: replayGainChoice);

    await openSettings(tester);
    final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(settingsItem('Desligada'), 100, scrollable: list);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    final texts = [
      'Qualidade baixa · 96 kbps',
      'Normalização do volume',
      'Automática',
      'Por música',
      'Por álbum',
      'Desligada',
    ];
    final tops = [for (final text in texts) top(text)];
    expect([...tops]..sort(), tops, reason: 'in this order, top to bottom, after the qualities');
    expect(checked('Desligada'), isTrue, reason: 'until a pick');

    for (final (name, detail) in [
      ('Automática', 'Por álbum quando um álbum toca em ordem, por música nas outras vezes'),
      ('Por música', 'Todas as músicas no mesmo volume'),
      ('Por álbum', 'Todos os álbuns no mesmo volume, e as músicas de cada um como são entre si'),
      ('Desligada', 'Cada música no volume do seu arquivo'),
    ]) {
      expect(
        find.descendant(of: settingsItem(name), matching: find.text(detail)),
        findsOneWidget,
        reason: name,
      );
    }

    await tester.tap(settingsItem('Por álbum'));
    await tester.pumpAndSettle();
    expect(replayGainChoice.value, ReplayGainMode.album);
    expect((await ReplayGainChoice.load()).value, ReplayGainMode.album);
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
        greaterThan(tester.getTopLeft(find.text('Cada música no volume do seu arquivo')).dy),
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

  testWidgets('on a phone, the app\'s icon is in the top left corner too, and the bar at the bottom keeps the home', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 640));
    final logo = find.descendant(of: find.byType(AppBar), matching: find.byTooltip('Início'));
    final bar = find.byType(NavigationBar);
    expect(tester.getRect(logo).left, lessThan(16));
    expect(find.descendant(of: bar, matching: find.text('Início')), findsOneWidget);

    await tester.tap(find.descendant(of: bar, matching: find.text('Álbuns')));
    await tester.pumpAndSettle();
    expect(title('Álbuns'), findsOneWidget);

    await tester.tap(logo);
    await tester.pumpAndSettle();
    expect(title('Início'), findsOneWidget);
    expect(tester.widget<NavigationBar>(bar).selectedIndex, 0);
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

  testWidgets('arrows at the right of a row take it a screenful forward and back, lined up on an album', (
    tester,
  ) async {
    await pumpHome(
      tester,
      const Size(1000, 700),
      mostPlayed: [for (var i = 0; i < 20; i++) 'Most $i'],
      latest: [for (var i = 0; i < 20; i++) 'Latest $i'],
    );
    expect(find.byType(Scrollbar), findsNothing);
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
  });

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

  testWidgets('a row whose albums all fit has no arrows', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    expect(find.text('Toys in the Attic'), findsOneWidget);
    expect(find.byTooltip('Próximos'), findsNothing);
    expect(find.byTooltip('Anteriores'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

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
