import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/equalizer_choice.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/settings.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/settings/equalizer_page.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/app/login_page.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/widgets/cover.dart';

import 'fakes.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

const album = {'id': 'a1', 'name': 'Toys in the Attic', 'artist': 'Aerosmith', 'artistId': 'ar1', 'coverArt': 'a1'};

/// A library of one album, with one song, which has played and is its artist's popular one, and its lyrics.
http.Response server(http.Request request) {
  final path = request.url.path;
  const song = {'id': 's1', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'albumId': 'a1', 'artistId': 'ar1'};

  if (path.endsWith('getArtist.view')) {
    return subsonic({
      'artist': {
        'id': 'ar1',
        'name': 'Aerosmith',
        'album': [
          {...album, 'playCount': 1},
        ],
      },
    });
  }

  if (path.endsWith('getTopSongs.view')) {
    return subsonic({
      'topSongs': {
        'song': [song],
      },
    });
  }

  if (path.endsWith('getLyricsBySongId.view')) {
    return subsonic({
      'lyricsList': {
        'structuredLyrics': [
          {
            'synced': true,
            'line': [
              {'start': 0, 'value': 'Backstroke lover'},
            ],
          },
        ],
      },
    });
  }

  if (path.endsWith('getAlbumList2.view')) {
    return subsonic({
      'albumList2': {
        'album': [album],
      },
    });
  }

  if (path.endsWith('getAlbum.view')) {
    return subsonic({
      'album': {
        ...album,
        'song': [
          {...song, 'playCount': 1},
        ],
      },
    });
  }

  return http.Response('', 404);
}

/// The app on a computer's wide window, with its theme, Walk This Way in the player, and a mouse over
/// nothing yet.
Future<TestGesture> pumpApp(WidgetTester tester) async {
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request)),
  );
  final player = PlayerController(FakeEngine(), api);
  await player.playQueue(const [
    Song(id: 's1', title: 'Walk This Way', artist: 'Aerosmith', albumId: 'a1'),
  ], play: false);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  final settings = Settings(equalizer: EqualizerChoice(const EqualizerSettings(on: true)));
  addTearDown(settings.dispose);
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      theme: segueTheme(Brightness.light),
      builder: (context, child) => SettingsScope(
        settings: settings,
        child: ServicesScope(services: services, child: child!),
      ),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pumpAndSettle();

  return addMouse(tester);
}

/// A mouse, in the window's bottom right corner.
Future<TestGesture> addMouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(999, 699));
  addTearDown(gesture.removePointer);
  await tester.pumpAndSettle();

  return gesture;
}

/// The mouse's cursor over the middle of what [finder] finds.
Future<MouseCursor?> cursorOver(WidgetTester tester, TestGesture gesture, Finder finder) async {
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();

  return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1); // the test's mouse
}

void main() {
  testWidgets('on a computer, the pointer is a hand over what can be clicked, and an arrow over the rest', (
    tester,
  ) async {
    final gesture = await pumpApp(tester);

    Future<void> expectHand(String what, Finder finder) async =>
        expect(await cursorOver(tester, gesture, finder), SystemMouseCursors.click, reason: what);

    Future<void> expectArrow(String what, Finder finder) async =>
        expect(await cursorOver(tester, gesture, finder), SystemMouseCursors.basic, reason: what);

    // The home, with the player bar.
    await expectHand('the app\'s icon', find.byTooltip('Início'));
    await expectHand('a section in the side rail', find.byTooltip('Álbuns'));
    await expectHand('a button in the top bar', find.byTooltip('Configurações'));
    await expectHand('an album', find.text('Toys in the Attic').first);
    await expectHand('its play button', find.byTooltip('Tocar o álbum').first);
    await expectHand('its artist', find.text('Aerosmith').first);
    await expectHand('the song in the player bar', find.byTooltip('Abrir o player'));
    await expectHand('a button in the player bar', find.byTooltip('Próxima'));
    await expectArrow('the hub\'s status, which only tells', find.byTooltip('Sem hub: só toca neste aparelho'));
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    await expectHand('a choice in the settings', find.text('Idioma'));
    await tester.tap(find.text('Idioma'));
    await tester.pumpAndSettle();
    await expectHand('a language in its sheet', find.text('English'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Equalizador'), 100, scrollable: find.byType(Scrollable).last);
    await expectHand('the equalizer in the settings', find.text('Equalizador'));
    await tester.tap(find.text('Equalizador'));
    await tester.pumpAndSettle();
    await expectHand('the equalizer\'s switch', find.byType(Switch));
    await expectHand('a curve', find.widgetWithText(ChoiceChip, 'Rock'));
    await expectHand('a band', find.byType(EqualizerBand).first);
    await tester.tap(find.byTooltip('Início'));
    await tester.pumpAndSettle();
    await expectArrow('the side rail\'s empty part', find.byType(VerticalDivider));
    expect(
      await cursorOver(tester, gesture, find.byType(TextField)),
      SystemMouseCursors.text,
      reason: 'the search bar',
    );
    await expectHand('a row\'s title', find.text('Lançamentos'));

    // The albums tab.
    await tester.tap(find.byTooltip('Álbuns'));
    await tester.pumpAndSettle();
    await expectHand('an order', find.widgetWithText(ChoiceChip, 'Mais tocados'));
    await tester.tap(find.byTooltip('Início'));
    await tester.pumpAndSettle();

    // An album's page.
    await tester.tap(find.text('Toys in the Attic').first);
    await tester.pumpAndSettle();
    await expectHand('the top bar\'s back arrow', find.byTooltip('Voltar'));
    await expectHand('the cover', find.byTooltip('Ver a capa'));
    await expectHand('the play button', find.byTooltip('Tocar o álbum'));
    await expectHand('a song', find.text('Walk This Way').first);
    await expectHand(
      'its artist',
      find.descendant(of: find.widgetWithText(ListTile, 'Walk This Way'), matching: find.text('Aerosmith')),
    );

    // Its artist's page.
    await tester.tap(
      find.descendant(of: find.widgetWithText(ListTile, 'Walk This Way'), matching: find.text('Aerosmith')),
    );
    await tester.pumpAndSettle();
    await expectHand('a list of their songs to pick', find.text('Populares'));
    await expectHand('the one picked', find.text('Suas mais tocadas'));

    // The full-screen player's lyrics.
    await tester.tap(find.descendant(of: find.byTooltip('Abrir o player'), matching: find.byType(Cover)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mostrar a letra'));
    await tester.pumpAndSettle();
    await expectHand('a line of the lyrics', find.text('Backstroke lover'));
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();

    // The devices, and a line that only tells.
    await tester.tap(find.byTooltip('Aparelhos'));
    await tester.pumpAndSettle();
    await expectHand('this device', find.textContaining('Este aparelho'));
    await expectArrow('a line that only tells', find.text('Nenhum hub encontrado'));
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on the sign-in, the language menu, and the languages in it', (tester) async {
    final settings = Settings();
    addTearDown(settings.dispose);
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        theme: segueTheme(Brightness.light),
        builder: (context, child) => SettingsScope(settings: settings, child: child!),
        home: LoginPage(onSignedIn: (_) {}),
      ),
    );
    final gesture = await addMouse(tester);
    expect(await cursorOver(tester, gesture, find.byTooltip('Idioma')), SystemMouseCursors.click, reason: 'the menu');

    await tester.tap(find.byTooltip('Idioma'));
    await tester.pumpAndSettle();
    expect(await cursorOver(tester, gesture, find.text('English')), SystemMouseCursors.click, reason: 'a language');
  });
}
