import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/artist_page.dart';
import 'package:segue/ui/cover.dart';
import 'package:segue/ui/home_page.dart';

import 'fakes.dart';
import 'side_rail.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A server with two artists: Aerosmith, with two albums, none of them played, and Cheap Trick, with
/// one, two of whose songs have played. A search for "toys" finds an album; any other, the artist
/// Aerosmith.
http.Response server(http.Request request) {
  final path = request.url.path;
  final id = request.url.queryParameters['id'];

  if (path.endsWith('getAlbumList2.view')) {
    return subsonic({'albumList2': <String, Object?>{}});
  }

  if (path.endsWith('getArtists.view')) {
    return subsonic({
      'artists': {
        'index': [
          {
            'name': 'A',
            'artist': [
              {'id': 'ar1', 'name': 'Aerosmith', 'albumCount': 2},
            ],
          },
          {
            'name': 'C',
            'artist': [
              {'id': 'ar2', 'name': 'Cheap Trick', 'albumCount': 1},
            ],
          },
        ],
      },
    });
  }

  if (path.endsWith('getArtist.view') && id == 'ar2') {
    return subsonic({
      'artist': {
        'id': 'ar2',
        'name': 'Cheap Trick',
        'albumCount': 1,
        'album': [
          {'id': 'a3', 'name': 'In Color', 'artist': 'Cheap Trick', 'year': 1977, 'playCount': 7},
        ],
      },
    });
  }

  if (path.endsWith('getArtist.view')) {
    return subsonic({
      'artist': {
        'id': 'ar1',
        'name': 'Aerosmith',
        'albumCount': 2,
        'album': [
          {'id': 'a1', 'name': 'Aerosmith', 'artist': 'Aerosmith', 'year': 1973},
          {'id': 'a2', 'name': 'Toys in the Attic', 'artist': 'Aerosmith', 'year': 1975},
        ],
      },
    });
  }

  if (path.endsWith('getAlbum.view') && id == 'a3') {
    return subsonic({
      'album': {
        'id': 'a3',
        'name': 'In Color',
        'artist': 'Cheap Trick',
        'artistId': 'ar2',
        'year': 1977,
        'song': [
          {'id': 's2', 'title': 'Hello There', 'album': 'In Color', 'duration': 101, 'playCount': 2},
          {'id': 's3', 'title': 'Big Eyes', 'album': 'In Color', 'duration': 187},
          {'id': 's4', 'title': 'I Want You to Want Me', 'album': 'In Color', 'duration': 191, 'playCount': 5},
        ],
      },
    });
  }

  if (path.endsWith('getAlbum.view')) {
    return subsonic({
      'album': {
        'id': 'a2',
        'name': 'Toys in the Attic',
        'artist': 'Aerosmith',
        'artistId': 'ar1',
        'year': 1975,
        'song': [
          {'id': 's1', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'duration': 220},
        ],
      },
    });
  }

  if (path.endsWith('search3.view') && request.url.queryParameters['query'] == 'toys') {
    return subsonic({
      'searchResult3': {
        'album': [
          {'id': 'a2', 'name': 'Toys in the Attic', 'artist': 'Aerosmith', 'artistId': 'ar1', 'year': 1975},
        ],
      },
    });
  }

  if (path.endsWith('search3.view')) {
    return subsonic({
      'searchResult3': {
        'artist': [
          {'id': 'ar1', 'name': 'Aerosmith', 'albumCount': 2},
        ],
      },
    });
  }

  return http.Response('', 404);
}

/// Opens the home; what the player plays goes to the engine it returns.
Future<FakeEngine> pumpHome(WidgetTester tester, Size size) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request)),
  );
  final engine = FakeEngine();
  final player = PlayerController(engine, api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pumpAndSettle();
  return engine;
}

Finder title(String text) => find.descendant(of: find.byType(AppBar), matching: find.text(text));

/// The artist's name, by their picture, over their page: its first text that says it, since an album can be named
/// after them too.
Finder artistName(String name) => find.descendant(of: find.byType(ArtistPage), matching: find.text(name)).first;

/// The tile of the artist named [name], in the artists' grid.
Finder tile(String name) => find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;

/// What darkens the picture of the artist named [name]: black, a little.
Finder shade(String name) => find.descendant(
  of: tile(name),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is ColoredBox &&
        (widget.color.r, widget.color.g, widget.color.b) == (0.0, 0.0, 0.0) &&
        widget.color.a > 0 &&
        widget.color.a < 0.5,
  ),
);

void main() {
  testWidgets('on a wide screen, a side rail goes to the artists, and an artist shows their albums, newest first', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    expect(find.byType(NavigationBar), findsNothing);
    expectHomeInRail();

    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Artistas'), findsOneWidget);
    expect(find.text('Aerosmith'), findsOneWidget);
    expect(find.text('Cheap Trick'), findsOneWidget);
    expect(find.text('2 álbuns'), findsOneWidget);
    expect(find.text('1 álbum'), findsOneWidget);

    await tester.tap(find.text('Aerosmith'));
    await tester.pumpAndSettle();
    expect(artistName('Aerosmith'), findsOneWidget);
    final newer = tester.getTopLeft(find.text('Toys in the Attic'));
    final older = tester.getTopLeft(find.text('1973'));
    expect(newer.dx < older.dx || newer.dy < older.dy, isTrue, reason: 'the 1975 album comes first');
    expect(find.text('Mais tocadas'), findsNothing, reason: 'none of their songs has played');

    await tester.tap(find.text('Toys in the Attic'));
    await tester.pumpAndSettle();
    expect(find.text('Walk This Way'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('an artist\'s songs the user plays most come over their albums, and play from the one picked', (
    tester,
  ) async {
    final engine = await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    expect(artistName('Cheap Trick'), findsOneWidget);
    final heading = find.descendant(of: find.byType(ArtistPage), matching: find.text('Mais tocadas'));
    final albums = find.descendant(of: find.byType(ArtistPage), matching: find.text('Álbuns'));
    expect(heading, findsOneWidget);
    expect(find.text('Big Eyes'), findsNothing, reason: 'it hasn\'t played');
    final top = find.text('I Want You to Want Me');
    final second = find.text('Hello There');
    expect(tester.getTopLeft(heading).dy, lessThan(tester.getTopLeft(top).dy));
    expect(tester.getTopLeft(top).dy, lessThan(tester.getTopLeft(second).dy), reason: 'the most played first');
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(albums).dy), reason: 'the albums under them');
    expect(find.text('1977'), findsOneWidget, reason: 'the album, in the grid');

    await tester.tap(second);
    await tester.pumpAndSettle();
    expect([for (final track in engine.tracks) track.queryParameters['id']], ['s4', 's2'], reason: 'the songs listed');
    expect(engine.index, 1, reason: 'from the one picked');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the sections are in a bar at the bottom', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byTooltip('Artistas'), findsOneWidget, reason: 'in the bar alone, with no side rail');
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Artistas')));
    await tester.pumpAndSettle();
    expect(title('Artistas'), findsOneWidget);
    expect(find.text('Cheap Trick'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an artist\'s picture darkens a little while the pointer is over the artist, as an album\'s cover does', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(999, 699));
    addTearDown(gesture.removePointer);
    expect(shade('Aerosmith'), findsNothing);

    await gesture.moveTo(tester.getCenter(find.text('Aerosmith')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: shade('Aerosmith'), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1), reason: 'it fades in, as the cover\'s shade does');
    await tester.pumpAndSettle();
    final picture = find.descendant(of: tile('Aerosmith'), matching: find.byType(Cover));
    expect(tester.getRect(shade('Aerosmith')), tester.getRect(picture), reason: 'all of the picture');
    expect(
      find.ancestor(of: shade('Aerosmith'), matching: find.byType(ClipOval)),
      findsOneWidget,
      reason: 'round',
    );
    expect(shade('Cheap Trick'), findsNothing);

    await gesture.moveTo(const Offset(999, 699));
    await tester.pumpAndSettle();
    expect(shade('Aerosmith'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search finds artists too, and one opens their page', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.enterText(find.byType(TextField), 'aero');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pumpAndSettle();
    expect(find.text('Artistas'), findsWidgets);
    await tester.tap(find.text('Aerosmith'));
    await tester.pumpAndSettle();
    expect(artistName('Aerosmith'), findsOneWidget);
    expect(find.text('Toys in the Attic'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('search finds albums too: one opens its page, and its artist theirs', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.enterText(find.byType(TextField), 'toys');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pumpAndSettle();
    expect(find.text('Álbuns'), findsWidgets);
    expect(find.textContaining('1975'), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir o artista'));
    await tester.pumpAndSettle();
    expect(artistName('Aerosmith'), findsOneWidget);
    expect(find.text('1973'), findsOneWidget, reason: 'their albums');
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Toys in the Attic'));
    await tester.pumpAndSettle();
    expect(find.text('Walk This Way'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('an album\'s page links its artist, whom the keyboard and the remote reach too', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.enterText(find.byType(TextField), 'toys');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toys in the Attic'));
    await tester.pumpAndSettle();
    expect(find.text('Walk This Way'), findsOneWidget);
    expect(find.textContaining('1975'), findsOneWidget, reason: 'the year, after the artist');

    final link = find.byTooltip('Abrir o artista');
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(artistName('Aerosmith'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    // Tab, as the remote's arrows, gets to it, and Enter, as its middle button, opens it.
    for (var i = 0; i < 5 && FocusManager.instance.primaryFocus?.rect != tester.getRect(link); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(link));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(artistName('Aerosmith'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
