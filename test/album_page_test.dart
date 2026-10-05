import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album_page.dart';
import 'package:segue/ui/cover_page.dart';

import 'fakes.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The page of Toys in the Attic, with the cover [coverArt], on a 1000×700 screen.
Future<void> pumpAlbum(WidgetTester tester, {String? coverArt = 'al-a1'}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient(
      (request) async => subsonic({
        'album': {
          'id': 'a1',
          'name': 'Toys in the Attic',
          'artist': 'Aerosmith',
          'coverArt': ?coverArt,
          'song': [
            {'id': 's1', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'duration': 220},
          ],
        },
      }),
    ),
  );
  final player = PlayerController(FakeEngine(), api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: const AlbumPage(Album(id: 'a1', name: 'Toys in the Attic')),
    ),
  );
  await tester.pumpAndSettle();
}

/// The cover as asked of the server at [size] pixels.
Finder coverAt(int size) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      Uri.parse((widget.image as NetworkImage).url).queryParameters['size'] == '$size',
);

Future<void> openCover(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ver a capa'));
  await tester.pumpAndSettle();
  expect(find.byType(CoverPage), findsOneWidget);
}

void main() {
  testWidgets('the cover opens full screen: as big as the screen\'s shorter side, asked of the server so', (
    tester,
  ) async {
    await pumpAlbum(tester);
    await openCover(tester);
    expect(tester.getSize(coverAt(700)), const Size(700, 700));
    expect(tester.getCenter(coverAt(700)), const Offset(500, 350));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap anywhere closes it, as do Esc and "Fechar"', (tester) async {
    await pumpAlbum(tester);
    await openCover(tester);
    await tester.tapAt(const Offset(500, 350));
    await tester.pumpAndSettle();
    expect(find.byType(CoverPage), findsNothing);
    expect(find.text('Walk This Way'), findsOneWidget);

    await openCover(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CoverPage), findsNothing);

    await openCover(tester);
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(CoverPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the keyboard and the remote get to the cover too', (tester) async {
    await pumpAlbum(tester);
    final cover = find.byTooltip('Ver a capa');

    for (var i = 0; i < 5 && FocusManager.instance.primaryFocus?.rect != tester.getRect(cover); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(cover));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CoverPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an album without a cover has none to open', (tester) async {
    await pumpAlbum(tester, coverArt: null);
    expect(find.byTooltip('Ver a capa'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
