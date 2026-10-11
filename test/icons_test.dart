import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/language_choice.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/widgets/cover.dart';
import 'package:segue/ui/widgets/themed_icon.dart';

import 'fakes.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

const song = {
  'id': 's1',
  'title': 'Sweet Emotion',
  'artist': 'Aerosmith',
  'album': 'Toys in the Attic',
  'duration': 274,
};

/// A library of one album, with one song.
http.Response server(http.Request request) {
  final path = request.url.path;

  if (path.endsWith('getAlbumList2.view')) {
    return subsonic({
      'albumList2': {
        'album': [
          {'id': 'a1', 'name': 'Toys in the Attic', 'artist': 'Aerosmith'},
        ],
      },
    });
  }

  if (path.endsWith('getAlbum.view')) {
    return subsonic({
      'album': {
        'id': 'a1',
        'name': 'Toys in the Attic',
        'artist': 'Aerosmith',
        'song': [song],
      },
    });
  }

  return http.Response('', 404);
}

/// The app on a screen of [size], with its theme, and Sweet Emotion in the player.
Future<void> pumpApp(WidgetTester tester, Size size) async {
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request)),
  );
  final player = PlayerController(FakeEngine(), api);
  await player.playQueue(const [
    Song(
      id: 's1',
      title: 'Sweet Emotion',
      artist: 'Aerosmith',
      album: 'Toys in the Attic',
      duration: Duration(seconds: 274),
    ),
  ], play: false);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  final languageChoice = LanguageChoice();
  addTearDown(languageChoice.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      theme: segueTheme(Brightness.light),
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: HomePage(onSignOut: () {}, languageChoice: languageChoice),
    ),
  );
  await tester.pumpAndSettle();
}

/// Hugeicons' icons, sized by the theme (ThemedIcon).
final hugeIcons = find.byType(ThemedIcon);

/// Any icon from a font, as Material's.
final otherIcons = find.byType(Icon);

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the app\'s icons are Hugeicons\', none of Material\'s: the home, the settings, an album, the player, '
      'its queue and the devices', (tester) async {
    await pumpApp(tester, const Size(1000, 700));
    expect(hugeIcons, findsWidgets);
    expect(otherIcons, findsNothing, reason: 'the home, with the player bar');

    await tap(tester, find.byTooltip('Configurações'));
    expect(otherIcons, findsNothing, reason: 'the settings');
    await tap(tester, find.text('Idioma'));
    expect(find.text('English'), findsOneWidget);
    expect(otherIcons, findsNothing, reason: 'a choice\'s sheet, with the check of the one picked');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Voltar'));

    await tap(tester, find.text('Toys in the Attic').first);
    expect(otherIcons, findsNothing, reason: 'an album');

    await tap(tester, find.descendant(of: find.byTooltip('Abrir o player'), matching: find.byType(Cover)));
    expect(otherIcons, findsNothing, reason: 'the player');

    await tap(tester, find.byTooltip('Fila'));
    expect(otherIcons, findsNothing, reason: 'the queue');

    await tap(tester, find.byTooltip('Voltar'));
    await tap(tester, find.byTooltip('Aparelhos'));
    expect(find.textContaining('Este aparelho'), findsOneWidget);
    expect(otherIcons, findsNothing, reason: 'the devices');
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('on a phone, the bar at the bottom too, the settings, and a page\'s back arrow', (tester) async {
    await pumpApp(tester, const Size(360, 640));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(otherIcons, findsNothing);

    await tap(tester, find.byTooltip('Configurações'));
    expect(find.text('Idioma'), findsOneWidget);
    expect(otherIcons, findsNothing, reason: 'the settings, with the back arrow');
    await tap(tester, find.byType(BackButton));

    await tap(tester, find.text('Toys in the Attic').first);
    expect(find.byType(BackButton), findsOneWidget);
    expect(otherIcons, findsNothing, reason: 'an album, with the back arrow');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an icon is the size the theme gives it, as an icon button\'s, and its own when it has one', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: IconTheme(
          data: IconThemeData(size: 40),
          child: Row(
            children: [
              ThemedIcon(HugeIcons.strokeRoundedPlay, key: Key('theme')),
              ThemedIcon(HugeIcons.strokeRoundedClock01, size: 18, key: Key('own')),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('theme'))), const Size.square(40));
    expect(tester.getSize(find.byKey(const Key('own'))), const Size.square(18));
  });
}
