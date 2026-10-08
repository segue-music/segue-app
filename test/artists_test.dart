import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/artist_page.dart';
import 'package:segue/ui/biography_page.dart';
import 'package:segue/ui/cover.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/now_playing_bar.dart';
import 'package:segue/ui/page_bar.dart';
import 'package:segue/ui/segmented_choice.dart';
import 'package:segue/ui/themed_icon.dart';

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
/// Unless [played], nothing has played: not even Cheap Trick's songs. Cheap Trick's popular songs are three of that
/// album's, Big Eyes first; the others' fail, as on a server that has none to give. Aerosmith has a biography, Last.fm's;
/// the others have none, which fails too.
http.Response server(http.Request request, {bool played = true}) {
  final path = request.url.path;
  final id = request.url.queryParameters['id'];

  if (path.endsWith('getTopSongs.view') && request.url.queryParameters['artist'] == 'Cheap Trick') {
    return subsonic({
      'topSongs': {
        'song': [
          {'id': 's3', 'title': 'Big Eyes', 'album': 'In Color', 'duration': 187},
          {'id': 's4', 'title': 'I Want You to Want Me', 'album': 'In Color', 'duration': 191},
          {'id': 's8', 'title': 'So Good to See You', 'album': 'In Color', 'duration': 214},
        ],
      },
    });
  }

  if (path.endsWith('getAlbumList2.view') && played && request.url.queryParameters['type'] == 'frequent') {
    return subsonic({
      'albumList2': {
        'album': [
          {'id': 'a3', 'name': 'In Color', 'artist': 'Cheap Trick', 'artistId': 'ar2', 'year': 1977, 'playCount': 7},
        ],
      },
    });
  }

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

  if (path.endsWith('getArtistInfo2.view') && id == 'ar1') {
    return subsonic({
      'artistInfo2': {
        'biography':
            'Aerosmith is an American rock band formed in Boston in 1970. <a target=\'_blank\' '
            'href="https://www.last.fm/music/Aerosmith" rel="nofollow">Read more on Last.fm</a>',
      },
    });
  }

  if (path.endsWith('getArtist.view') && id == 'ar2') {
    return subsonic({
      'artist': {
        'id': 'ar2',
        'name': 'Cheap Trick',
        'coverArt': 'ar-ar2',
        'albumCount': 1,
        'album': [
          {'id': 'a3', 'name': 'In Color', 'artist': 'Cheap Trick', 'year': 1977, 'playCount': ?(played ? 7 : null)},
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

/// Opens the home, over a [server] where songs have [played]; what the player plays goes to the engine it returns.
Future<FakeEngine> pumpHome(WidgetTester tester, Size size, {bool played = true}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request, played: played)),
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
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

/// The artist's picture, at the top of their page.
Finder artistPicture() => find.descendant(of: find.byType(ArtistPage), matching: find.byType(LargeCover)).first;

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

/// The icon [data] draws.
Finder icon(HugeIconData data) => find.byWidgetPredicate((widget) => widget is ThemedIcon && widget.icon == data);

/// The tile of the artist named [name], in the artists' grid.
Finder tile(String name) => find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;

/// The choice of the artists tab between their orders.
Finder orders() => find.byWidgetPredicate((widget) => widget is SegmentedChoice);

/// The option of the artists tab that picks the order [label] names.
Finder order(String label) => find.descendant(of: orders(), matching: find.text(label));

/// The option of an artist's page that shows the list of their songs [label] names, or the list's title.
Finder songList(String label) => find.descendant(of: find.byType(ArtistPage), matching: find.text(label));

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
    expect(find.text('Suas mais tocadas'), findsNothing, reason: 'none of their songs has played');
    expect(find.text('Populares'), findsNothing, reason: 'nor are there popular ones');
    final albums = find.descendant(of: find.byType(ArtistPage), matching: find.text('Álbuns'));
    expect(albums, findsOneWidget, reason: 'their albums have a title all the same');
    expect(tester.getTopLeft(albums).dy, lessThan(tester.getTopLeft(find.text('Toys in the Attic')).dy));

    await tester.tap(find.text('Toys in the Attic'));
    await tester.pumpAndSettle();
    expect(find.text('Walk This Way'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('the artists tab lists them by name, or the most played first, as picked in a choice above them', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(order('Nome')), isSemantics(isSelected: true));
    expect(tester.getSemantics(order('Mais tocados')), isSemantics(isSelected: false));
    expect(find.text('Aerosmith'), findsOneWidget);
    expect(find.text('Ramones'), findsOneWidget);
    final picture = tester.getRect(find.descendant(of: tile('Aerosmith'), matching: find.byType(Cover)));
    final choice = tester.getRect(orders());
    expect(picture.left, moreOrLessEquals(choice.left), reason: 'lined up with the choice');
    expect(picture.top, greaterThan(choice.bottom), reason: 'under it');
    expect(
      choice.width,
      lessThan(tester.getSize(find.byType(GridView)).width / 2),
      reason: 'as wide as its options, not the tab',
    );

    await tester.tap(order('Mais tocados'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(order('Mais tocados')), isSemantics(isSelected: true));
    expect(tester.getSemantics(order('Nome')), isSemantics(isSelected: false));
    expect(find.text('Cheap Trick'), findsOneWidget, reason: 'their songs have played');
    expect(find.text('1 álbum'), findsOneWidget, reason: 'as the tab lists them by name');
    expect(find.text('Aerosmith'), findsNothing, reason: 'none of theirs has');
    expect(find.text('Ramones'), findsNothing);

    await tester.tap(order('Nome'));
    await tester.pumpAndSettle();
    expect(find.text('Aerosmith'), findsOneWidget);
    expect(find.text('Ramones'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, once the artist\'s picture has gone up, their name stays in a bar at the top of their '
      'page, under the top bar, whose arrows go back', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    final page = find.byType(ArtistPage);
    Finder inBar(Finder finder) => find.descendant(of: find.byType(PageBarSliver), matching: finder);
    final position = tester
        .state<ScrollableState>(find.descendant(of: page, matching: find.byType(Scrollable)).first)
        .position;
    expect(inBar(find.text('Cheap Trick')), findsNothing, reason: 'by the picture');

    position.jumpTo(300);
    await tester.pumpAndSettle();
    expect(position.pixels, 300, reason: 'far enough down for the picture to have gone');
    final (area, name) = (tester.getRect(page), tester.getRect(inBar(find.text('Cheap Trick'))));
    expect(name.left, area.left + 16, reason: 'from the page\'s margin');
    expect(name.center.dy, moreOrLessEquals(area.top + kToolbarHeight / 2, epsilon: 1), reason: 'at its top');
    expect(find.descendant(of: page, matching: find.byType(BackButton)), findsNothing);

    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(inBar(find.text('Cheap Trick')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a wide screen, the artist\'s picture is behind the top of their page too, blurred, across it, under '
    'the page\'s color: half of it at the top, all of it at the bottom of the round picture; nothing with no picture',
    (tester) async {
      await pumpHome(tester, const Size(1000, 700));
      await tester.tap(find.byTooltip('Artistas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheap Trick'));
      await tester.pumpAndSettle();
      final page = find.byType(ArtistPage);
      final backdrop = find.descendant(of: page, matching: find.byType(ImageFiltered));
      expect(tester.widget<Cover>(find.descendant(of: backdrop, matching: find.byType(Cover))).id, 'ar-ar2');
      final (area, behind) = (tester.getRect(page), tester.getRect(backdrop));
      final round = tester.getRect(find.descendant(of: page, matching: find.byType(ClipOval)));
      expect(behind, Rect.fromLTRB(area.left, area.top, area.right, round.bottom));
      final shade = tester.widget<DecoratedBox>(find.ancestor(of: backdrop, matching: find.byType(DecoratedBox)).first);
      final gradient = (shade.decoration as BoxDecoration).gradient! as LinearGradient;
      final surface = Theme.of(tester.element(page)).colorScheme.surface;
      expect(shade.position, DecorationPosition.foreground);
      expect((gradient.colors.first, gradient.colors.last), (surface.withValues(alpha: 0.5), surface));

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ramones'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: page, matching: find.byType(ImageFiltered)), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('before anything has played, the most played artists say where they will be', (tester) async {
    await pumpHome(tester, const Size(1000, 700), played: false);
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(order('Mais tocados'));
    await tester.pumpAndSettle();
    expect(find.text('Os artistas que você mais ouvir aparecem aqui.'), findsOneWidget);
    expect(find.text('Cheap Trick'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an artist\'s five songs the user plays most, numbered, come over their albums, picked over them, and '
      'play from the one picked', (tester) async {
    // Tall enough for the songs and the album under them.
    final engine = await pumpHome(tester, const Size(1000, 900));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    expect(artistName('Cheap Trick'), findsOneWidget);
    final heading = songList('Suas mais tocadas');
    final albums = find.descendant(of: find.byType(ArtistPage), matching: find.text('Álbuns'));
    expect(heading, findsOneWidget);
    expect(tester.getSemantics(heading), isSemantics(isSelected: true), reason: 'the user\'s first');
    expect(tester.getSemantics(songList('Populares')), isSemantics(isSelected: false));
    expect(find.text('Big Eyes'), findsNothing, reason: 'it hasn\'t played');
    final top = find.text('I Want You to Want Me');
    final second = find.text('Hello There');
    expect(tester.getTopLeft(heading).dy, lessThan(tester.getTopLeft(top).dy));
    expect(tester.getTopLeft(top).dy, lessThan(tester.getTopLeft(second).dy), reason: 'the most played first');
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(albums).dy), reason: 'the albums under them');
    final last = find.descendant(of: find.widgetWithText(ListTile, 'Downed'), matching: find.text('In Color'));
    expect(
      tester.getRect(albums).top - tester.getRect(last).bottom,
      moreOrLessEquals(36, epsilon: 1),
      reason: 'as far from the last song\'s lines as a section of albums is from the one over it',
    );
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

  testWidgets('picking the popular ones shows the artist\'s songs everyone plays most, as the server gives them, which '
      'play from the one picked', (tester) async {
    final engine = await pumpHome(tester, const Size(1000, 900));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    await tester.tap(songList('Populares'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(songList('Populares')), isSemantics(isSelected: true));
    expect(tester.getSemantics(songList('Suas mais tocadas')), isSemantics(isSelected: false));
    final first = find.widgetWithText(ListTile, 'Big Eyes');
    final last = find.widgetWithText(ListTile, 'So Good to See You');
    expect(find.descendant(of: first, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: last, matching: find.text('3')), findsOneWidget);
    expect(find.text('Hello There'), findsNothing, reason: 'the user\'s, not among the popular ones');

    await tester.tap(last);
    await tester.pumpAndSettle();
    expect([for (final track in engine.tracks) track.queryParameters['id']], ['s3', 's4', 's8']);
    expect(engine.index, 2);

    await tester.tap(songList('Suas mais tocadas'));
    await tester.pumpAndSettle();
    expect(find.text('Hello There'), findsOneWidget, reason: 'the user\'s again');
    expect(find.text('Big Eyes'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an artist none of whose songs has played has their popular ones, under a title', (tester) async {
    await pumpHome(tester, const Size(1000, 900), played: false);
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    final heading = songList('Populares');
    expect(heading, findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is SegmentedChoice), findsNothing, reason: 'nothing else to pick');
    expect(find.text('Suas mais tocadas'), findsNothing);
    expect(tester.getTopLeft(heading).dy, lessThan(tester.getTopLeft(find.text('Big Eyes')).dy));
    expect(find.text('So Good to See You'), findsOneWidget);
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
    expect(
      singles.top - tester.getRect(find.text('1975')).bottom,
      36,
      reason: 'from the albums\' last lines, with no room left empty under them, as far as the albums from the songs',
    );
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

  testWidgets('on a phone, the sections are in a bar at the bottom, the artists\' orders in icons, and the bar stays '
      'under an artist\'s page', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byTooltip('Artistas'), findsOneWidget, reason: 'in the bar alone, with no side rail');
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Artistas')));
    await tester.pumpAndSettle();
    expect(title('Artistas'), findsOneWidget);
    expect(find.text('Cheap Trick'), findsOneWidget);
    // The orders in icons, their names in tooltips, as on an artist's page: A to Z, and headphones for what the user
    // listens to.
    expect(find.descendant(of: orders(), matching: find.byType(Text)), findsNothing);
    expect(find.descendant(of: find.byTooltip('Nome'), matching: icon(HugeIcons.strokeRoundedSortingAZ02)), findsOne);
    expect(
      find.descendant(of: find.byTooltip('Mais tocados'), matching: icon(HugeIcons.strokeRoundedHeadphones)),
      findsOne,
    );
    expect(tester.getSemantics(find.byTooltip('Nome')), isSemantics(isSelected: true));

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
    expect(tester.getRect(grid).bottom, 640);
    expect(MediaQuery.paddingOf(tester.element(grid)).bottom, 640 - tester.getRect(find.byType(NowPlayingBar)).top);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timer
  });

  testWidgets('on a phone, an artist\'s picture goes across the top of their page, under the system\'s bar and the '
      'page\'s, which has their name, centered, and stays as the page scrolls; the choice of their songs is over its '
      'bottom, in icons, with how many albums they have at the end of its line', (tester) async {
    // A system's bar at the top of the screen.
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24);
    await pumpHome(tester, const Size(360, 640));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Artistas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    final picture = tester.getRect(artistPicture());
    expect(
      picture,
      const Rect.fromLTWH(0, 0, 360, 24 + 320),
      reason: 'as wide as the page, from the top of the screen, and half the screen tall at most under the bar',
    );
    expect(find.descendant(of: find.byType(ArtistPage), matching: find.byType(ClipOval)), findsNothing);
    expect(artistPictureAt(1200), findsOneWidget, reason: 'asked of the server as many pixels across as a phone has');
    expect(artistPictureAt(300), findsOneWidget, reason: 'under it, as it comes');
    final title = find.descendant(of: find.byType(AppBar), matching: find.text('Cheap Trick'));
    final (arrow, name) = (tester.getRect(find.byType(BackButton)), tester.getRect(title));
    expect(find.descendant(of: find.byType(ArtistPage), matching: find.text('Cheap Trick')), findsOneWidget);
    expect(arrow.center.dy, 24 + kToolbarHeight / 2, reason: 'over the picture, under the system\'s bar');
    expect(name.left, greaterThanOrEqualTo(arrow.right));
    expect(name.center.dx, moreOrLessEquals(180, epsilon: 1), reason: 'centered on the page');
    expect(name.center.dy, moreOrLessEquals(arrow.center.dy, epsilon: 1), reason: 'on the arrow\'s line');
    final choice = tester.getRect(find.byWidgetPredicate((widget) => widget is SegmentedChoice));
    expect(choice.bottom, lessThanOrEqualTo(picture.bottom));
    expect(choice.top, greaterThan(picture.center.dy), reason: 'over the bottom of the picture');
    final count = tester.getRect(find.text('1 álbum'));
    expect(count.center.dy, moreOrLessEquals(choice.center.dy, epsilon: 1), reason: 'on the choice\'s line');
    expect(count.right, moreOrLessEquals(360 - 16, epsilon: 1), reason: 'at its end, the page\'s margin from the edge');
    expect(
      tester.getRect(find.text('I Want You to Want Me')).top,
      greaterThanOrEqualTo(picture.bottom),
      reason: 'the songs under the picture',
    );
    // Icons, their names in tooltips: headphones for what the user listens to, fire for what's hot.
    expect(
      find.descendant(of: find.byWidgetPredicate((widget) => widget is SegmentedChoice), matching: find.byType(Text)),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byTooltip('Suas mais tocadas'), matching: icon(HugeIcons.strokeRoundedHeadphones)),
      findsOne,
    );
    expect(find.descendant(of: find.byTooltip('Populares'), matching: icon(HugeIcons.strokeRoundedFire)), findsOne);
    expect(tester.getSemantics(find.byTooltip('Suas mais tocadas')), isSemantics(isSelected: true));
    // The picture is as it is at the top, under the system's bar and the name, and fades to the page's color, all of it
    // at the bottom.
    final surface = Theme.of(tester.element(find.byType(ArtistPage))).colorScheme.surface;
    final fade = find.descendant(
      of: find.byType(ArtistPage),
      matching: find.byWidgetPredicate(
        (widget) => switch (widget) {
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(:final colors))) =>
            colors.first == surface.withValues(alpha: 0) && colors.last == surface,
          _ => false,
        },
      ),
    );
    expect(tester.getRect(fade), picture);
    // The bar, clear over the picture, takes more of the page's color as the page scrolls under it, all of it once half
    // the picture has gone up, so that what passes under the name doesn't hide it.
    final appBar = find.descendant(of: find.byType(ArtistPage), matching: find.byType(AppBar));
    Color bar() => tester.widget<Material>(find.descendant(of: appBar, matching: find.byType(Material)).first).color!;
    expect(bar().a, 0);

    await tester.drag(find.byType(AlbumGrid), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(bar().a, inExclusiveRange(0, 1), reason: 'some of it');

    await tester.drag(find.byType(AlbumGrid), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(artistPicture()).bottom, lessThanOrEqualTo(24 + kToolbarHeight), reason: 'gone up past it');
    expect(bar().a, 1, reason: 'all of it');
    expect((tester.getRect(find.byType(BackButton)), tester.getRect(title)), (arrow, name), reason: 'the bar stays');

    await tester.drag(find.byType(AlbumGrid), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(tester.getRect(artistPicture()).top, 0);
    expect(bar().a, 0, reason: 'clear again');

    await tester.tap(find.byTooltip('Populares'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byTooltip('Populares')), isSemantics(isSelected: true));
    expect(find.text('Big Eyes'), findsOneWidget, reason: 'the popular ones');
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

  for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
    testWidgets('on $screen, a button after how many albums an artist has opens their biography over the window, under '
        'their picture; an artist without one has no button', (tester) async {
      final narrow = size.width < 600;
      await pumpHome(tester, size);
      final artists = narrow ? find.text('Artistas') : find.byTooltip('Artistas');
      await tester.tap(artists);
      await tester.pumpAndSettle();
      await tester.tap(tile('Aerosmith'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(ArtistPage), matching: find.byTooltip('Ver a biografia')));
      await tester.pumpAndSettle();

      final page = find.byType(BiographyPage);
      expect(page, findsOneWidget);
      expect(find.descendant(of: page, matching: find.text('Aerosmith')), findsOneWidget);
      expect(
        find.descendant(of: page, matching: find.text('Aerosmith is an American rock band formed in Boston in 1970.')),
        findsOneWidget,
      );
      expect(find.descendant(of: page, matching: find.text('Biografia provida por Last.fm')), findsOneWidget);
      final picture = find.descendant(of: page, matching: find.byType(LargeCover));
      expect(tester.widget<LargeCover>(picture).id, 'ar-ar1');
      // As wide as the screen, but no taller than most of it.
      expect(tester.getSize(picture), Size.square(narrow ? 360 : 420));

      if (narrow) {
        await tester.tap(find.descendant(of: page, matching: find.byTooltip('Fechar')));
      } else {
        // A tap on the picture or the text keeps it; one beside them, or Esc, closes it.
        await tester.tap(picture);
        await tester.tap(find.text('Aerosmith is an American rock band formed in Boston in 1970.'));
        await tester.pumpAndSettle();
        expect(page, findsOneWidget);
        await tester.tapAt(tester.getTopLeft(picture) - const Offset(40, -40));
        await tester.pumpAndSettle();
        expect(page, findsNothing);
        await tester.tap(find.descendant(of: find.byType(ArtistPage), matching: find.byTooltip('Ver a biografia')));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }

      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(artistName('Aerosmith'), findsOneWidget, reason: 'back on their page');

      // A section closes the page.
      await tester.tap(artists);
      await tester.pumpAndSettle();
      await tester.tap(tile('Cheap Trick'));
      await tester.pumpAndSettle();
      expect(artistName('Cheap Trick'), findsOneWidget);
      expect(find.byTooltip('Ver a biografia'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
