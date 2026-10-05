import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/cover.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/shortcuts.dart';

import 'fakes.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A library of two albums: Toys in the Attic, with two songs, and Pump, which the server fails to
/// give. A search finds Toys in the Attic.
http.Response server(http.Request request) {
  final path = request.url.path;
  const toys = {'id': 'a1', 'name': 'Toys in the Attic', 'artist': 'Aerosmith'};

  if (path.endsWith('getAlbumList2.view')) {
    return subsonic({
      'albumList2': {
        'album': [
          toys,
          {'id': 'a2', 'name': 'Pump', 'artist': 'Aerosmith'},
        ],
      },
    });
  }

  if (path.endsWith('getAlbum.view') && request.url.queryParameters['id'] == 'a1') {
    return subsonic({
      'album': {
        ...toys,
        'song': [
          {'id': 's1', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'albumId': 'a1'},
          {'id': 's2', 'title': 'Sweet Emotion', 'artist': 'Aerosmith', 'albumId': 'a1'},
        ],
      },
    });
  }

  if (path.endsWith('search3.view')) {
    return subsonic({
      'searchResult3': {
        'album': [toys],
      },
    });
  }

  return http.Response('', 500);
}

/// The app on the albums tab, on a TV with [television]. Returns its player.
Future<PlayerController> pumpAlbums(WidgetTester tester, {bool television = false}) async {
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request)),
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
      builder: (context, child) => ServicesScope(
        services: services,
        child: DirectionalNavigation(enabled: television, child: child!),
      ),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Álbuns'));
  await tester.pumpAndSettle();
  return player;
}

final playButton = find.byTooltip('Tocar o álbum');

Finder title(String text) => find.descendant(of: find.byType(AppBar), matching: find.text(text));

/// The tile of the album named [name].
Finder tile(String name) => find.ancestor(of: find.text(name), matching: find.byType(AlbumTile));

/// A mouse, over nothing yet.
Future<TestGesture> mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(999, 699));
  addTearDown(() async {
    try {
      await gesture.removePointer();
    } on Object {
      // removed by the test already
    }
  });
  await tester.pumpAndSettle();
  return gesture;
}

void main() {
  testWidgets(
    'on a computer, an album\'s play button shows in the middle of its cover only while the pointer is over the '
    'album',
    (tester) async {
      await pumpAlbums(tester);
      expect(playButton, findsNothing, reason: 'no pointer yet');

      final gesture = await mouse(tester);
      expect(playButton, findsNothing);

      await gesture.moveTo(tester.getCenter(find.text('Toys in the Attic')));
      await tester.pumpAndSettle();
      expect(playButton, findsOneWidget);
      final cover = tester.getCenter(find.descendant(of: tile('Toys in the Attic'), matching: find.byType(Cover)));
      expect(tester.getCenter(playButton), offsetMoreOrLessEquals(cover));

      await gesture.moveTo(tester.getCenter(find.text('Pump')));
      await tester.pumpAndSettle();
      expect(playButton, findsOneWidget, reason: 'the other album\'s');
      expect(find.descendant(of: tile('Pump'), matching: playButton), findsOneWidget);

      await gesture.moveTo(const Offset(999, 699));
      await tester.pumpAndSettle();
      expect(playButton, findsNothing);

      // Out of the window, where the system stops telling the app about the mouse.
      await gesture.removePointer();
      await tester.pumpAndSettle();
      expect(playButton, findsNothing, reason: 'the pointer left the window');
      await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'clicked, it plays the album from its first song, without opening it',
    variant: TargetPlatformVariant.desktop(),
    (tester) async {
      final player = await pumpAlbums(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(tester.getCenter(find.text('Toys in the Attic')));
      await tester.pumpAndSettle();
      await tester.tap(playButton);
      await tester.pumpAndSettle();
      expect([for (final song in player.queue) song.title], ['Walk This Way', 'Sweet Emotion']);
      expect(player.current?.title, 'Walk This Way');
      expect(player.playing, isTrue);
      expect(title('Álbuns'), findsOneWidget, reason: 'still on the albums');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'on a phone or a tablet, with no pointer to hover with, every album shows it',
    variant: TargetPlatformVariant.mobile(),
    (tester) async {
      final player = await pumpAlbums(tester);
      expect(playButton, findsNWidgets(2));
      await tester.tap(find.descendant(of: tile('Toys in the Attic'), matching: playButton));
      await tester.pumpAndSettle();
      expect(player.current?.title, 'Walk This Way');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a TV there is none: the remote goes from album to album, and an album plays from its page', (
    tester,
  ) async {
    await pumpAlbums(tester, television: true);
    expect(find.text('Toys in the Attic'), findsOneWidget);
    expect(playButton, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the albums a search finds have it too', (tester) async {
    final player = await pumpAlbums(tester);
    await tester.enterText(find.byType(TextField), 'toys');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pumpAndSettle();
    expect(playButton, findsOneWidget);
    final icon = tester.element(find.descendant(of: playButton, matching: find.byType(Icon)));
    expect(
      IconTheme.of(icon).color,
      Theme.of(icon).colorScheme.onPrimary,
      reason: 'the filled button\'s, not the list tile\'s icons\'',
    );

    await tester.tap(playButton);
    await tester.pumpAndSettle();
    expect(player.current?.title, 'Walk This Way');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an album the server fails to give says so, and nothing plays', (tester) async {
    final player = await pumpAlbums(tester);
    await tester.tap(find.descendant(of: tile('Pump'), matching: playButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não consegui tocar o álbum'), findsOneWidget);
    expect(player.queue, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
