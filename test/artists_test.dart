import 'dart:convert';

import 'package:flutter/gestures.dart';
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
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/artist_page.dart';
import 'package:segue/ui/cover.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/now_playing_bar.dart';

import 'fakes.dart';
import 'side_rail.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A server with three artists: Aerosmith, with two albums, none of them played, and a single and an EP, Cheap Trick,
/// with one album, six of whose songs have played, and Ramones, with none. A search for "toys" finds an album; any other, the artist Aerosmith.
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
          {
            'name': 'R',
            'artist': [
              {'id': 'ar3', 'name': 'Ramones', 'albumCount': 0},
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

  if (path.endsWith('getArtist.view') && id == 'ar3') {
    return subsonic({
      'artist': {'id': 'ar3', 'name': 'Ramones', 'albumCount': 0},
    });
  }

  if (path.endsWith('getArtist.view')) {
    return subsonic({
      'artist': {
        'id': 'ar1',
        'name': 'Aerosmith',
        'coverArt': 'ar-ar1',
        'albumCount': 2,
        'album': [
          {'id': 'a1', 'name': 'Aerosmith', 'artist': 'Aerosmith', 'year': 1973},
          {
            'id': 'a4',
            'name': 'Dream On',
            'artist': 'Aerosmith',
            'year': 1973,
            'releaseTypes': ['single'],
          },
          {
            'id': 'a2',
            'name': 'Toys in the Attic',
            'artist': 'Aerosmith',
            'year': 1975,
            'releaseTypes': ['album'],
          },
          {
            'id': 'a5',
            'name': 'Pink',
            'artist': 'Aerosmith',
            'year': 1997,
            'releaseTypes': ['EP'],
          },
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
          {'id': 's2', 'title': 'Hello There', 'album': 'In Color', 'duration': 101, 'playCount': 5},
          {'id': 's3', 'title': 'Big Eyes', 'album': 'In Color', 'duration': 187},
          {'id': 's4', 'title': 'I Want You to Want Me', 'album': 'In Color', 'duration': 191, 'playCount': 6},
          {'id': 's5', 'title': 'Southern Girls', 'album': 'In Color', 'duration': 223, 'playCount': 4},
          {'id': 's6', 'title': 'Clock Strikes Ten', 'album': 'In Color', 'duration': 180, 'playCount': 3},
          {'id': 's7', 'title': 'Downed', 'album': 'In Color', 'duration': 248, 'playCount': 2},
          {'id': 's8', 'title': 'So Good to See You', 'album': 'In Color', 'duration': 214, 'playCount': 1},
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

/// The artist's picture by their name, over their page.
Finder artistPicture() => find.descendant(of: find.byType(ArtistPage), matching: find.byType(ClipOval)).first;

/// The artist's picture as asked of the server at [size] pixels.
Finder artistPictureAt(int size) => find.descendant(
  of: artistPicture(),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is NetworkImage &&
        Uri.parse((widget.image as NetworkImage).url).queryParameters['size'] == '$size',
  ),
);

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
    expect(tester.getSize(artistPicture()), const Size.square(220), reason: 'as big as an album\'s cover on its page');
    expect(artistPictureAt(800), findsOneWidget, reason: 'asked of the server as that one is');
    expect(artistPictureAt(300), findsOneWidget, reason: 'under it, as it comes');
    final newer = tester.getTopLeft(find.text('Toys in the Attic'));
    final older = tester.getTopLeft(find.text('1973'));
    expect(newer.dx < older.dx || newer.dy < older.dy, isTrue, reason: 'the 1975 album comes first');
    expect(find.text('Mais tocadas'), findsNothing, reason: 'none of their songs has played');
    final albums = find.descendant(of: find.byType(ArtistPage), matching: find.text('Álbuns'));
    expect(albums, findsOneWidget, reason: 'their albums have a title all the same');
    expect(tester.getTopLeft(albums).dy, lessThan(tester.getTopLeft(find.text('Toys in the Attic')).dy));

    await tester.tap(find.text('Toys in the Attic'));
    await tester.pumpAndSettle();
    expect(find.text('Walk This Way'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('an artist\'s five songs the user plays most, numbered, come over their albums, and play from the one '
      'picked', (tester) async {
    // Tall enough for the songs and the album under them.
    final engine = await pumpHome(tester, const Size(1000, 900));
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
    expect(find.text('So Good to See You'), findsNothing, reason: 'the sixth');
    final tile = find.widgetWithText(ListTile, 'Hello There');
    final number = find.descendant(of: tile, matching: find.text('2'));
    expect(number, findsOneWidget);
    expect(
      tester.getTopRight(number).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.descendant(of: tile, matching: find.byType(Thumbnail))).dx),
      reason: 'before its cover',
    );
    expect(find.text('1977'), findsOneWidget, reason: 'the album, in the grid');

    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(
      [for (final track in engine.tracks) track.queryParameters['id']],
      ['s4', 's2', 's5', 's6', 's7'],
      reason: 'the songs listed',
    );
    expect(engine.index, 1, reason: 'from the one picked');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an artist\'s singles and EPs, newest first, come after their albums, under a title of their own', (
    tester,
  ) async {
    // Tall enough for both sections.
    await pumpHome(tester, const Size(1000, 1200));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aerosmith'));
    await tester.pumpAndSettle();
    final albums = tester.getRect(find.descendant(of: find.byType(ArtistPage), matching: find.text('Álbuns')));
    final singles = tester.getRect(find.text('Singles e EPs'));
    final (toys, pink, dreamOn) = (
      tester.getRect(find.text('Toys in the Attic')),
      tester.getRect(find.text('Pink')),
      tester.getRect(find.text('Dream On')),
    );
    expect(albums.bottom, lessThan(toys.top));
    expect(toys.bottom, lessThan(singles.top), reason: 'the albums first');
    expect(singles.bottom, lessThan(pink.top));
    expect((pink.top, singles.left), (dreamOn.top, albums.left));
    expect(pink.left, lessThan(dreamOn.left), reason: 'the 1997 EP before the 1973 single');
    expect(find.text('1997 · EP'), findsOneWidget, reason: 'its year and its type');
    expect(find.text('1973 · Single'), findsOneWidget);
    expect(find.text('1975'), findsOneWidget, reason: 'an album\'s year alone');
    expect(find.text('2 álbuns · 2 singles e EPs'), findsOneWidget, reason: 'by their picture, how many of each');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an artist with no albums has no title for them', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ramones'));
    await tester.pumpAndSettle();
    expect(artistName('Ramones'), findsOneWidget);
    expect(find.descendant(of: find.byType(ArtistPage), matching: find.text('Álbuns')), findsNothing);
    expect(find.text('Singles e EPs'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an artist with albums alone has no title for singles and EPs', (tester) async {
    // Tall enough for their songs and their album.
    await pumpHome(tester, const Size(1000, 900));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    expect(find.text('1977'), findsOneWidget, reason: 'the album, in the grid');
    expect(find.text('Singles e EPs'), findsNothing);
    expect(find.text('1 álbum'), findsOneWidget, reason: 'and no singles or EPs to count');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the sections are in a bar at the bottom, which stays under an artist\'s page', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 640));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byTooltip('Artistas'), findsOneWidget, reason: 'in the bar alone, with no side rail');
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Artistas')));
    await tester.pumpAndSettle();
    expect(title('Artistas'), findsOneWidget);
    expect(find.text('Cheap Trick'), findsOneWidget);

    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    final page = find.byType(ArtistPage);
    await ServicesScope.of(tester.element(page)).player.playQueue(const [Song(id: 's1', title: 'Dream Police')]);
    await tester.pumpAndSettle();
    // Under the home's bars, which stay; the albums go on behind them, and end clear of them.
    final grid = find.descendant(of: page, matching: find.byType(AlbumGrid));
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    expect(find.descendant(of: page, matching: find.byType(NowPlayingBar)), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    // Beside their picture, with no bar above them; smaller than on a wide screen, to leave their name room.
    final (arrow, rect) = (tester.getRect(find.byType(BackButton)), tester.getRect(artistPicture()));
    expect(rect.top, 16);
    expect(rect.size, const Size.square(140));
    expect(arrow.bottom, greaterThan(rect.top));
    expect(arrow.right, lessThanOrEqualTo(rect.left));
    expect(tester.getRect(grid).bottom, 640);
    expect(MediaQuery.paddingOf(tester.element(grid)).bottom, 640 - tester.getRect(find.byType(NowPlayingBar)).top);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timer
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

  testWidgets(
    'an artist has room inside, around their picture, where the tint shows; the picture is 16 from the next',
    (tester) async {
      await pumpHome(tester, const Size(1000, 700));
      await tester.tap(find.byTooltip('Artistas'));
      await tester.pumpAndSettle();
      Rect picture(String name) => tester.getRect(find.descendant(of: tile(name), matching: find.byType(Cover)));

      final (artist, next) = ('Aerosmith', 'Cheap Trick');
      expect(picture(artist).left - tester.getRect(tile(artist)).left, 8);
      expect(picture(artist).top - tester.getRect(tile(artist)).top, 8);
      expect(tester.getRect(tile(artist)).right - picture(artist).right, 8);
      expect(picture(next).left - picture(artist).right, moreOrLessEquals(16));
      expect(picture(artist).left - tester.getRect(find.byType(GridView)).left, moreOrLessEquals(16));
      await tester.pumpWidget(const SizedBox());
    },
  );

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
