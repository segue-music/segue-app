import 'dart:async';
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
import 'package:segue/pictures/fanart_tv.dart';
import 'package:segue/player/player.dart';
import 'package:segue/releases/musicbrainz.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/artist_page.dart';
import 'package:segue/ui/artists_view.dart';
import 'package:segue/ui/biography_page.dart';
import 'package:segue/ui/cover.dart';
import 'package:segue/ui/genre_page.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/now_playing_bar.dart';
import 'package:segue/ui/page_bar.dart';
import 'package:segue/ui/picture_gallery.dart';
import 'package:segue/ui/segmented_choice.dart';
import 'package:segue/ui/text_link.dart';
import 'package:segue/ui/themed_icon.dart';
import 'package:segue/ui/tile_row.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';
import 'side_rail.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A server with four artists: Aerosmith, with two albums, none of them played, and a single and an EP, Cheap Trick,
/// with one album, six of whose songs have played, Joe Perry, a member of Aerosmith by their MusicBrainz id, whose
/// albums it doesn't give, and Ramones, with none. Aerosmith's albums are in four genres: Hard Rock (three of them),
/// Blues Rock (two), Rock and Pop (one each, Rock first); Cheap Trick's in Power Pop. A search for "toys" finds an
/// album, one for "perry" the artist Joe Perry, any other the artist Aerosmith.
/// Unless [played], nothing has played: not even Cheap Trick's songs. Cheap Trick's popular songs are three of that
/// album's, Big Eyes first; the others' fail, as on a server that has none to give. Aerosmith has a biography, Last.fm's,
/// a MusicBrainz id, and Cheap Trick and Ramones as the artists like them; the others have neither, which fails too.
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
            'name': 'J',
            'artist': [
              {'id': 'ar4', 'name': 'Joe Perry', 'albumCount': 3, 'musicBrainzId': 'mb-perry'},
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
        'similarArtist': [
          {'id': 'ar2', 'name': 'Cheap Trick', 'coverArt': 'ar-ar2', 'albumCount': 1},
          {'id': 'ar3', 'name': 'Ramones', 'albumCount': 0},
        ],
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
          {
            'id': 'a3',
            'name': 'In Color',
            'artist': 'Cheap Trick',
            'year': 1977,
            'playCount': ?(played ? 7 : null),
            'genre': 'Power Pop',
          },
        ],
      },
    });
  }

  if (path.endsWith('getArtist.view') && id == 'ar4') {
    return subsonic({
      'artist': {'id': 'ar4', 'name': 'Joe Perry', 'albumCount': 0, 'musicBrainzId': 'mb-perry'},
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
        'musicBrainzId': 'mb1',
        'album': [
          {'id': 'a1', 'name': 'Aerosmith', 'artist': 'Aerosmith', 'year': 1973, 'genre': 'Hard Rock'},
          {
            'id': 'a4',
            'name': 'Dream On',
            'artist': 'Aerosmith',
            'year': 1973,
            'releaseTypes': ['single'],
            'genre': 'Hard Rock',
          },
          {
            'id': 'a2',
            'name': 'Toys in the Attic',
            'artist': 'Aerosmith',
            'year': 1975,
            'releaseTypes': ['album'],
            'genres': [
              {'name': 'Hard Rock'},
              {'name': 'Blues Rock'},
              {'name': 'Rock'},
            ],
          },
          {
            'id': 'a5',
            'name': 'Pink',
            'artist': 'Aerosmith',
            'year': 1997,
            'releaseTypes': ['EP'],
            'genres': [
              {'name': 'Blues Rock'},
              {'name': 'Pop'},
            ],
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

  if (path.endsWith('search3.view') && request.url.queryParameters['query'] == 'perry') {
    return subsonic({
      'searchResult3': {
        'artist': [
          {'id': 'ar4', 'name': 'Joe Perry', 'albumCount': 3, 'musicBrainzId': 'mb-perry'},
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

/// Opens the home, over a [server] where songs have [played], with [musicBrainz] (none: no band's years) and [fanartTv]
/// (none: no more pictures of an artist); what the player plays goes to the engine it returns.
Future<FakeEngine> pumpHome(
  WidgetTester tester,
  Size size, {
  bool played = true,
  MusicBrainz? musicBrainz,
  FanartTv? fanartTv,
}) async {
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
    musicBrainz: musicBrainz,
    fanartTv: fanartTv,
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

/// The URL of the [n]th picture of Aerosmith that fanart.tv has, or of [artist].
Uri fanartUrl(int n, {String artist = 'aerosmith'}) => Uri.parse('https://assets.fanart.tv/fanart/$artist-$n.jpg');

/// fanart.tv, with five pictures of Aerosmith (by their MusicBrainz id, mb1), the first the most liked, two of Joe Perry
/// (mb-perry), the second the most liked, and none of anyone else; [asked] gets every request.
FanartTv fanartTv({List<http.Request>? asked}) => FanartTv(
  apiKey: 'key',
  client: MockClient((request) async {
    asked?.add(request);
    return http.Response(
      jsonEncode({
        if (request.url.path.endsWith('/mb1'))
          'artistthumb': [
            for (var n = 1; n <= 5; n++) {'id': '$n', 'url': '${fanartUrl(n)}', 'likes': '${5 - n}'},
          ]
        else if (request.url.path.endsWith('/mb-perry'))
          'artistthumb': [
            for (var n = 1; n <= 2; n++) {'id': 'p$n', 'url': '${fanartUrl(n, artist: 'joe-perry')}', 'likes': '$n'},
          ],
      }),
      200,
    );
  }),
);

/// The [n]th picture of Aerosmith that fanart.tv has, in their biography's gallery.
Finder morePicture(int n) => fanartPicture(fanartUrl(n));

/// The picture at [url], one of fanart.tv's, as the app shows it: taken no more pixels across than it shows.
Finder fanartPicture(Uri url) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      switch (widget.image) {
        ResizeImage(imageProvider: NetworkImage(url: final shown)) => shown == '$url',
        _ => false,
      },
);

/// What opens URLs out of the app, as url_launcher asks the platform: it notes them, and the modes they open in, and
/// opens those that [opens] says.
class FakeUrlLauncher extends UrlLauncherPlatform {
  final launched = <String>[];
  final modes = <PreferredLaunchMode>[];
  bool Function(String url) opens = (_) => true;

  void clear() {
    launched.clear();
    modes.clear();
  }

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    modes.add(options.mode);
    return opens(url);
  }
}

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
    expect(tester.getSemantics(order('Nome')), isSemantics(label: 'Nome', isButton: true), reason: 'the order picked');
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
    expect(tester.getSemantics(order('Mais tocados')), isSemantics(label: 'Mais tocados'));
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
    expect(
      tester.getSemantics(heading),
      isSemantics(label: 'Suas mais tocadas', isButton: true),
      reason: 'the user\'s first',
    );
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
    expect(tester.getSemantics(songList('Populares')), isSemantics(label: 'Populares'));
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

  testWidgets('an artist with albums and singles or EPs has a choice between them over the albums, which shows their '
      'singles and EPs, newest first, in their place', (tester) async {
    await pumpHome(tester, const Size(1000, 900));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aerosmith'));
    await tester.pumpAndSettle();
    final choice = find.descendant(of: find.byType(ArtistPage), matching: orders());
    expect(choice, findsOneWidget);
    expect(find.descendant(of: choice, matching: find.text('Álbuns')), findsOneWidget);
    expect(find.descendant(of: choice, matching: find.text('Singles e EPs')), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Álbuns')),
      isSemantics(label: 'Álbuns', isButton: true),
      reason: 'the albums first',
    );
    final toys = tester.getRect(find.text('Toys in the Attic'));
    expect(tester.getRect(choice).bottom, lessThan(toys.top));
    expect(tester.getRect(choice).left, toys.left, reason: 'lined up with the covers and their names');
    expect(tester.getRect(choice).width, lessThan(400), reason: 'as wide as its options, not the page');
    expect(find.text('1975'), findsOneWidget, reason: 'an album\'s year alone');
    expect(find.text('Pink'), findsNothing, reason: 'the EP not with the albums');
    expect(find.text('Dream On'), findsNothing);
    expect(find.text('2 álbuns · 2 singles e EPs'), findsOneWidget, reason: 'by their picture, how many of each');

    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('Singles e EPs')), isSemantics(label: 'Singles e EPs'));
    expect(find.text('Toys in the Attic'), findsNothing);
    final (pink, dreamOn) = (tester.getRect(find.text('Pink')), tester.getRect(find.text('Dream On')));
    expect(tester.getRect(choice).bottom, lessThan(pink.top));
    expect((pink.top, pink.left), (dreamOn.top, toys.left), reason: 'where the albums were');
    expect(pink.left, lessThan(dreamOn.left), reason: 'the 1997 EP before the 1973 single');
    expect(find.text('1997 · EP'), findsOneWidget, reason: 'its year and its type');
    expect(find.text('1973 · Single'), findsOneWidget);

    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(find.text('Toys in the Attic'), findsOneWidget, reason: 'the albums again');
    expect(find.text('Pink'), findsNothing);
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

  testWidgets('an artist with albums alone has them under a title, with nothing to pick', (tester) async {
    // Tall enough for their songs and their album.
    await pumpHome(tester, const Size(1000, 900));
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheap Trick'));
    await tester.pumpAndSettle();
    expect(find.text('1977'), findsOneWidget, reason: 'the album, in the grid');
    final albums = find.descendant(of: find.byType(ArtistPage), matching: find.text('Álbuns'));
    expect(albums, findsOneWidget);
    expect(
      find.ancestor(of: albums, matching: orders()),
      findsNothing,
      reason: 'a title, not a choice',
    );
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
    expect(tester.getSemantics(find.byTooltip('Nome')), isSemantics(label: 'Nome', isButton: true));

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
      'page\'s, which stays as the page scrolls; their name, the choice of their songs, in icons, and how many albums '
      'they have, at the end of its line, are over its bottom, where it fades into the page', (tester) async {
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
    final appBar = find.descendant(of: find.byType(ArtistPage), matching: find.byType(AppBar));
    final title = find.descendant(of: appBar, matching: find.text('Cheap Trick'));
    final (arrow, name) = (tester.getRect(find.byType(BackButton)), tester.getRect(title));
    expect(arrow.center.dy, 24 + kToolbarHeight / 2, reason: 'over the picture, under the system\'s bar');
    expect(name.left, greaterThanOrEqualTo(arrow.right));
    expect(name.center.dx, moreOrLessEquals(180, epsilon: 1), reason: 'centered on the page');
    expect(name.center.dy, moreOrLessEquals(arrow.center.dy, epsilon: 1), reason: 'on the arrow\'s line');
    double titleOpacity() =>
        tester.widget<Opacity>(find.ancestor(of: title, matching: find.byType(Opacity)).first).opacity;
    expect(titleOpacity(), 0, reason: 'the page shows it');
    // The page's own, over the bottom of the picture, in bold, bigger than the bar has it.
    final heading = find.descendant(
      of: find.byType(ArtistPage),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'Cheap Trick' && widget.style?.fontWeight == FontWeight.bold,
      ),
    );
    expect(tester.getRect(heading).left, 16);
    expect(tester.getRect(heading).top, greaterThan(picture.center.dy));
    expect(tester.getSize(heading).height, greaterThan(tester.getSize(title).height));
    final choice = tester.getRect(find.byWidgetPredicate((widget) => widget is SegmentedChoice));
    expect(choice.bottom, lessThanOrEqualTo(picture.bottom));
    expect(choice.top, greaterThan(tester.getRect(heading).bottom), reason: 'under the name');
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
    expect(
      tester.getSemantics(find.byTooltip('Suas mais tocadas')),
      isSemantics(label: 'Suas mais tocadas', isButton: true),
    );
    // The picture is as it is at the top, under the system's bar, and fades to the page's color from a little above
    // the name, more than half of it behind the name, so that it reads over any picture, and all of it at the bottom.
    final surface = Theme.of(tester.element(find.byType(ArtistPage))).colorScheme.surface;
    Finder fade({required double from, required double to}) => find.descendant(
      of: find.byType(ArtistPage),
      matching: find.byWidgetPredicate(
        (widget) => switch (widget) {
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(:final colors))) =>
            colors.first == surface.withValues(alpha: from) && colors.last == surface.withValues(alpha: to),
          _ => false,
        },
      ),
    );
    final above = tester.getRect(fade(from: 0, to: 0.6));
    final under = tester.getRect(fade(from: 0.6, to: 1));
    expect(above.bottom, under.top);
    expect(above.top, greaterThan(24 + kToolbarHeight), reason: 'the picture as it is under the bars');
    expect(under.top, lessThanOrEqualTo(tester.getRect(heading).top), reason: 'behind the name');
    expect(under.bottom, picture.bottom);
    // The bar, clear over the picture, takes more of the page's color as the page scrolls under it, all of it once the
    // name reaches it, and takes the name as that goes up under it.
    Color bar() => tester.widget<Material>(find.descendant(of: appBar, matching: find.byType(Material)).first).color!;
    expect(bar().a, 0);

    await tester.drag(find.byType(AlbumGrid), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(bar().a, inExclusiveRange(0, 1), reason: 'some of it');
    expect(titleOpacity(), 0, reason: 'the name still under the bar');

    await tester.drag(find.byType(AlbumGrid), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(artistPicture()).bottom, lessThanOrEqualTo(24 + kToolbarHeight), reason: 'gone up past it');
    expect(bar().a, 1, reason: 'all of it');
    expect(titleOpacity(), 1, reason: 'the name gone up under it');
    expect((tester.getRect(find.byType(BackButton)), tester.getRect(title)), (arrow, name), reason: 'the bar stays');

    await tester.drag(find.byType(AlbumGrid), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(tester.getRect(artistPicture()).top, 0);
    expect(bar().a, 0, reason: 'clear again');
    expect(titleOpacity(), 0);

    await tester.tap(find.byTooltip('Populares'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byTooltip('Populares')), isSemantics(label: 'Populares'));
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
      // As wide as the text under it, in the middle, but no taller than most of the screen.
      final side = narrow ? 328.0 : 420.0;
      expect(
        tester.getRect(picture),
        rectMoreOrLessEquals(Rect.fromCenter(center: Offset(size.width / 2, side / 2), width: side, height: side)),
      );

      if (narrow) {
        await tester.tap(find.descendant(of: page, matching: find.byTooltip('Fechar')));
      } else {
        // A tap on the picture or the text keeps it; one beside them, or Esc, closes it.
        await tester.tap(picture);
        await tester.tap(find.text('Aerosmith is an American rock band formed in Boston in 1970.'));
        await tester.pumpAndSettle();
        expect(page, findsOneWidget);
        await tester.tapAt(tester.getTopLeft(picture) - const Offset(80, -40));
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

  for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
    testWidgets('on $screen, an artist\'s biography has their pictures at the top, in a gallery: the server\'s in the '
        'middle, then three of fanart.tv\'s at most, the next showing a little beside it; a swipe, a tap on the one '
        'beside and the arrows go from one to the next', (tester) async {
      final narrow = size.width < 600;
      final asked = <http.Request>[];
      await pumpHome(tester, size, fanartTv: fanartTv(asked: asked));
      await tester.tap(narrow ? find.text('Artistas') : find.byTooltip('Artistas'));
      await tester.pumpAndSettle();
      await tester.tap(tile('Aerosmith'));
      await tester.pumpAndSettle();
      expect(
        asked.map((request) => request.url.path),
        isNot(contains('/v3/music/mb1')),
        reason: 'only the biography shows those of an artist the server has a picture of',
      );
      await tester.tap(find.descendant(of: find.byType(ArtistPage), matching: find.byTooltip('Ver a biografia')));
      await tester.pumpAndSettle();
      expect(asked.last.url.path, '/v3/music/mb1', reason: 'by their MusicBrainz id');

      final page = find.byType(BiographyPage);
      final picture = find.descendant(of: page, matching: find.byType(LargeCover));
      final middle = size.width / 2;
      expect(tester.getCenter(picture).dx, middle);
      expect(tester.getRect(morePicture(1)).left, tester.getRect(picture).right + 8, reason: 'beside it');
      expect(tester.getRect(morePicture(1)).left, lessThanOrEqualTo(size.width - 8), reason: 'showing');
      expect(morePicture(2), findsNothing, reason: 'nor one past it');

      // A swipe past half of it brings the next one to the middle.
      await tester.drag(find.byType(PictureGallery), Offset(-tester.getSize(picture).width * 0.75, 0));
      await tester.pumpAndSettle();
      expect(tester.getCenter(morePicture(1)).dx, middle);
      expect(tester.getRect(picture).right, tester.getRect(morePicture(1)).left - 8, reason: 'the one before');

      // A tap on the one before brings it back.
      await tester.tapAt(tester.getRect(picture).centerRight - const Offset(4, 0));
      await tester.pumpAndSettle();
      expect(page, findsOneWidget);
      expect(tester.getCenter(picture).dx, middle);

      // The arrows right and left, as far as there are pictures: three more.
      for (final n in [1, 2, 3, 3]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(tester.getCenter(morePicture(n)).dx, middle);
      }

      expect(morePicture(4), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(tester.getCenter(morePicture(2)).dx, middle);

      // With a mouse, arrows at the gallery's edges, as the pointer is over it: over the ones beside on a wide screen,
      // over the middle one's edges on a phone, where so little of them shows.
      double opacity(String tooltip) => tester
          .widget<AnimatedOpacity>(find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(opacity('Próxima foto'), 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byType(PictureGallery)));
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();
      expect(opacity('Foto anterior'), 1);
      expect(opacity('Próxima foto'), 1);
      final next = tester.getCenter(find.byTooltip('Próxima foto')).dx;
      expect(tester.getRect(find.byType(PictureGallery)).right - next, lessThan(32));

      if (!narrow) {
        expect(next, greaterThan(tester.getRect(morePicture(2)).right));
      }

      await tester.tap(find.byTooltip('Próxima foto'));
      await tester.pumpAndSettle();
      expect(tester.getCenter(morePicture(3)).dx, middle);
      expect(opacity('Próxima foto'), 0, reason: 'the last one');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a gallery takes fanart.tv\'s pictures as they come; the first is in the middle where the server has no '
      'picture of the artist, and a placeholder where neither has any', (tester) async {
    final more = Completer<List<Uri>>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: BiographyPage(
          const Biography(['Aerosmith is an American rock band.']),
          name: 'Aerosmith',
          morePictures: more.future,
        ),
      ),
    );
    await tester.pump();
    final placeholder = find.descendant(of: find.byType(PictureGallery), matching: find.byType(LargeCover));
    expect(tester.widget<LargeCover>(placeholder).id, isNull);
    final text = tester.getTopLeft(find.text('Aerosmith is an American rock band.'));

    more.complete([fanartUrl(1), fanartUrl(2)]);
    await tester.pumpAndSettle();
    expect(placeholder, findsNothing);
    expect(tester.getCenter(morePicture(1)).dx, 400);
    expect(tester.getRect(morePicture(2)).left, tester.getRect(morePicture(1)).right + 8);
    expect(tester.getTopLeft(find.text('Aerosmith is an American rock band.')), text, reason: 'where it was');
  });

  for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
    testWidgets('on $screen, an artist the server has no picture of has the one fanart.tv\'s users like most, by their '
        'MusicBrainz id: in search, in the artists\' grid and on their page, asked for once; one without the id, a '
        'person', (tester) async {
      final narrow = size.width < 600;
      final asked = <http.Request>[];
      await pumpHome(tester, size, fanartTv: fanartTv(asked: asked));

      if (narrow) {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Buscar')));
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byType(TextField), 'perry');
      await tester.pump(HomePage.searchTypingPause);
      await tester.pumpAndSettle();
      final liked = fanartPicture(fanartUrl(2, artist: 'joe-perry'));
      expect(find.descendant(of: find.widgetWithText(ListTile, 'Joe Perry'), matching: liked), findsOneWidget);
      expect(asked.map((request) => request.url.path), ['/v3/music/mb-perry']);

      await tester.tap(
        narrow
            ? find.descendant(of: find.byType(NavigationBar), matching: find.text('Artistas'))
            : find.byTooltip('Artistas'),
      );
      await tester.pumpAndSettle();
      expect(find.descendant(of: tile('Joe Perry'), matching: liked), findsOneWidget);
      expect(find.descendant(of: tile('Ramones'), matching: find.byType(Image)), findsNothing);
      expect(find.descendant(of: tile('Ramones'), matching: icon(HugeIcons.strokeRoundedUser)), findsOneWidget);

      await tester.tap(tile('Joe Perry'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: artistPicture(), matching: liked), findsWidgets);

      if (!narrow) {
        final backdrop = find.descendant(of: find.byType(ArtistPage), matching: find.byType(ImageFiltered));
        expect(
          find.descendant(of: backdrop, matching: liked),
          findsOneWidget,
          reason: 'behind, blurred',
        );
      }

      expect(asked, hasLength(1), reason: 'remembered, and none for the others');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
    testWidgets(
      'on $screen, the artists like one come at the end of their page, in a row of their pictures, which open '
      'their pages; an artist with none has no row',
      (tester) async {
        await pumpHome(tester, size);
        await tester.tap(size.width < 600 ? find.text('Artistas') : find.byTooltip('Artistas'));
        await tester.pumpAndSettle();
        await tester.tap(tile('Aerosmith'));
        await tester.pumpAndSettle();
        // The page's own, the first: the row's scrolls sideways.
        final page = find.descendant(of: find.byType(ArtistPage), matching: find.byType(Scrollable)).first;
        await tester.drag(page, const Offset(0, -3000));
        await tester.pumpAndSettle();

        final row = find.descendant(of: find.byType(ArtistPage), matching: find.byType(TileRow));
        expect(find.descendant(of: row, matching: find.text('Artistas parecidos')), findsOneWidget);
        expect(
          tester.getTopLeft(row).dy,
          greaterThan(tester.getBottomLeft(find.text('1973')).dy),
          reason: 'after their albums, the 1973 one last',
        );
        final artists = find.descendant(of: row, matching: find.byType(ArtistTile));
        expect(
          [for (final tile in tester.widgetList<ArtistTile>(artists)) tile.artist.name],
          ['Cheap Trick', 'Ramones'],
        );
        final picture = find.descendant(of: artists.first, matching: find.byType(ClipOval));
        expect(tester.getSize(picture), const Size.square(160), reason: 'as big as a cover in a row of albums');

        await tester.tap(picture);
        await tester.pumpAndSettle();
        expect(artistName('Cheap Trick'), findsOneWidget);
        await tester.drag(page, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(find.text('In Color'), findsWidgets, reason: 'at the end of their page');
        expect(find.text('Artistas parecidos'), findsNothing, reason: 'the server gives none like them');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'on a wide screen, an artist\'s genres, the three most of their albums are in, the one most are in first, '
    'come under how many albums they have, each a link to its page; an artist with none has none',
    (tester) async {
      await pumpHome(tester, const Size(1000, 700));
      await tester.tap(find.byTooltip('Artistas'));
      await tester.pumpAndSettle();
      await tester.tap(tile('Aerosmith'));
      await tester.pumpAndSettle();
      final page = find.byType(ArtistPage);
      Finder inPage(String text) => find.descendant(of: page, matching: find.text(text));
      expect(find.descendant(of: page, matching: find.byTooltip('Abrir o gênero')), findsNWidgets(3));
      expect(inPage('Pop'), findsNothing, reason: 'in as many albums as Rock, which came first');
      final genres = [
        for (final name in ['Hard Rock', 'Blues Rock', 'Rock']) tester.getRect(inPage(name)),
      ];
      expect(genres[0].left, tester.getTopLeft(artistName('Aerosmith')).dx, reason: 'lined up with the name');
      expect(genres[0].top, greaterThan(tester.getBottomLeft(inPage('2 álbuns · 2 singles e EPs')).dy));
      expect(genres[1].left, greaterThan(genres[0].right));
      expect(genres[2].left, greaterThan(genres[1].right));
      final link = tester.widget<TextLink>(find.ancestor(of: inPage('Hard Rock'), matching: find.byType(TextLink)));
      expect(link.style?.shadows, isNull, reason: 'no halo off the picture');

      await tester.tap(inPage('Blues Rock'));
      await tester.pumpAndSettle();
      expect(find.byType(GenrePage), findsOneWidget);
      expect(tester.widget<GenrePage>(find.byType(GenrePage)).genre.name, 'Blues Rock');

      await tester.tap(find.byTooltip('Artistas'));
      await tester.pumpAndSettle();
      await tester.tap(tile('Ramones'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Abrir o gênero'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a phone, an artist\'s genres are over the bottom of their picture, between their name and the choice '
      'of their songs, with no halo', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    await tester.tap(find.text('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(tile('Cheap Trick'));
    await tester.pumpAndSettle();
    final page = find.byType(ArtistPage);
    final genre = find.descendant(of: page, matching: find.text('Power Pop'));
    final choice = find.descendant(of: page, matching: orders());
    // The page's, not the bar's.
    final name = find.descendant(of: find.byType(AlbumGrid), matching: find.text('Cheap Trick'));
    expect(tester.getTopLeft(genre).dx, 16);
    expect(tester.getTopLeft(genre).dy, greaterThanOrEqualTo(tester.getBottomLeft(name).dy));
    expect(tester.getBottomLeft(genre).dy, lessThanOrEqualTo(tester.getTopLeft(choice).dy));
    expect(tester.getBottomLeft(genre).dy, lessThan(tester.getBottomLeft(artistPicture()).dy));
    final link = tester.widget<TextLink>(find.ancestor(of: genre, matching: find.byType(TextLink)));
    expect(link.style?.shadows, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
    testWidgets('on $screen, an artist\'s genres show the ink of the focus (a TV\'s) over their picture: on a material '
        'of their own, not on the page\'s, under the picture', (tester) async {
      await pumpHome(tester, size);
      await tester.tap(size.width < 600 ? find.text('Artistas') : find.byTooltip('Artistas'));
      await tester.pumpAndSettle();
      await tester.tap(tile('Cheap Trick'));
      await tester.pumpAndSettle();
      final page = find.byType(ArtistPage);
      // Blurred across the page on a wide screen, across it from the top on a phone.
      final picture = size.width < 600
          ? artistPicture()
          : find.descendant(of: page, matching: find.byType(ImageFiltered));
      expect(picture, findsOneWidget);
      final genre = find.descendant(of: page, matching: find.text('Power Pop'));
      final material = find.ancestor(of: genre, matching: find.byType(Material)).first;
      expect(find.descendant(of: material, matching: picture), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a band\'s biography has its years beside its name, and where it comes from under it, asked of '
      'MusicBrainz as it opens', (tester) async {
    final asked = <Uri>[];
    final brainz = MusicBrainz(
      spacing: Duration.zero,
      client: MockClient((request) async {
        asked.add(request.url);
        return http.Response(
          jsonEncode({
            'id': 'mb1',
            'type': 'Group',
            'life-span': {'begin': '1970', 'end': null, 'ended': false},
            'country': 'US',
            // A state, which says its country by its code: no more to ask.
            'begin-area': {
              'id': 'ma',
              'name': 'Massachusetts',
              'iso-3166-2-codes': ['US-MA'],
            },
          }),
          200,
        );
      }),
    );
    await pumpHome(tester, const Size(1000, 700), musicBrainz: brainz);
    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    await tester.tap(tile('Aerosmith'));
    await tester.pumpAndSettle();
    expect(asked, isEmpty, reason: 'only the biography shows them');
    await tester.tap(find.descendant(of: find.byType(ArtistPage), matching: find.byTooltip('Ver a biografia')));
    await tester.pumpAndSettle();
    expect(asked.single.path, '/ws/2/artist/mb1', reason: 'once for the years and where it comes from');
    final page = find.byType(BiographyPage);
    expect(find.descendant(of: page, matching: find.text('Aerosmith (desde 1970)')), findsOneWidget);
    expect(find.descendant(of: page, matching: find.text('Massachusetts, Estados Unidos')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('where an artist comes from, under their name, by a pin: the place and its country, or either alone; '
      'nothing for a country the app has no name for', (tester) async {
    for (final (Origin? origin, String? text) in [
      ((place: 'Boston', country: 'US'), 'Boston, Estados Unidos'),
      ((place: null, country: 'GB'), 'Reino Unido'),
      ((place: 'Seattle', country: null), 'Seattle'),
      ((place: null, country: 'SU'), 'União Soviética'),
      ((place: 'Somewhere', country: 'XW'), 'Somewhere'),
      ((place: null, country: 'XW'), null),
      (null, null),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('pt')],
          home: BiographyPage(
            const Biography(['Aerosmith is an American rock band.']),
            name: 'Aerosmith',
            origin: Stream.fromIterable([?origin]),
          ),
        ),
      );
      await tester.pump();
      final pin = icon(HugeIcons.strokeRoundedLocation01);

      if (text == null) {
        expect(pin, findsNothing, reason: '$origin');
        continue;
      }

      final line = find.text(text);
      expect(line, findsOneWidget, reason: '$origin');
      expect(tester.getCenter(pin).dy, moreOrLessEquals(tester.getCenter(line).dy, epsilon: 1));
      expect(tester.getTopLeft(line).dy, greaterThan(tester.getBottomLeft(find.text('Aerosmith')).dy));
      expect(
        tester.getBottomLeft(line).dy,
        lessThan(tester.getTopLeft(find.text('Aerosmith is an American rock band.')).dy),
      );
    }

    // The country again, where it turns out to be another.
    final origins = StreamController<Origin>();
    addTearDown(origins.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: BiographyPage(
          const Biography(['David Byrne is a Scottish-American musician.']),
          name: 'David Byrne',
          origin: origins.stream,
        ),
      ),
    );
    origins.add((place: 'Dumbarton', country: 'US'));
    await tester.pumpAndSettle();
    expect(find.text('Dumbarton, Estados Unidos'), findsOneWidget);
    origins.add((place: 'Dumbarton', country: 'GB'));
    await tester.pumpAndSettle();
    expect(find.text('Dumbarton, Reino Unido'), findsOneWidget);
    expect(find.text('Dumbarton, Estados Unidos'), findsNothing);
  });

  testWidgets('where an artist comes from is a link to it on a map: on Android in the maps app the user picks, on iOS '
      'and macOS in Apple Maps, elsewhere OpenStreetMap\'s, in the browser; on a TV, plain text', (tester) async {
    final launcher = FakeUrlLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);

    Future<void> pump(TargetPlatform platform, {bool television = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('pt')],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(navigationMode: television ? NavigationMode.directional : NavigationMode.traditional),
            child: child!,
          ),
          home: BiographyPage(
            const Biography(['Aerosmith is an American rock band.']),
            name: 'Aerosmith',
            origin: Stream.value((place: 'Boston', country: 'US')),
          ),
        ),
      );
      // Once the theme has gone from one platform's to the next.
      await tester.pumpAndSettle();
    }

    for (final (platform, url) in [
      (TargetPlatform.android, 'geo:0,0?q=Boston%2C+Estados+Unidos'),
      (TargetPlatform.iOS, 'https://maps.apple.com/?q=Boston%2C+Estados+Unidos'),
      (TargetPlatform.macOS, 'https://maps.apple.com/?q=Boston%2C+Estados+Unidos'),
      (TargetPlatform.linux, 'https://www.openstreetmap.org/search?query=Boston%2C+Estados+Unidos'),
      (TargetPlatform.windows, 'https://www.openstreetmap.org/search?query=Boston%2C+Estados+Unidos'),
    ]) {
      await pump(platform);
      expect(find.byTooltip('Ver no mapa'), findsOneWidget);
      await tester.tap(find.text('Boston, Estados Unidos'));
      await tester.pump();
      expect(launcher.launched, [url], reason: '$platform');
      expect(launcher.modes.single, PreferredLaunchMode.externalApplication, reason: 'out of the app');
      launcher.clear();
    }

    // On an Android without a maps app, OpenStreetMap's.
    launcher.opens = (url) => !url.startsWith('geo:');
    await pump(TargetPlatform.android);
    await tester.tap(find.text('Boston, Estados Unidos'));
    await tester.pump();
    expect(launcher.launched, [
      'geo:0,0?q=Boston%2C+Estados+Unidos',
      'https://www.openstreetmap.org/search?query=Boston%2C+Estados+Unidos',
    ]);
    launcher.clear();

    await pump(TargetPlatform.android, television: true);
    expect(find.text('Boston, Estados Unidos'), findsOneWidget);
    expect(find.byTooltip('Ver no mapa'), findsNothing);
    await tester.tap(find.text('Boston, Estados Unidos'));
    await tester.pump();
    expect(launcher.launched, isEmpty);
  });

  for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
    testWidgets('on $screen, a band\'s members, under its biography, are links to the pages of those in the library '
        'too, which open as the biography closes', (tester) async {
      final brainz = MusicBrainz(
        spacing: Duration.zero,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'id': 'mb1',
              'type': 'Group',
              'life-span': {'begin': '1970', 'end': null, 'ended': false},
              'relations': [
                for (final (id, name, begin, end) in [
                  ('mb-perry', 'Joe Perry', '1970-10', '1979-07'),
                  ('mb-tyler', 'Steven Tyler', '1970-10', null),
                  ('mb-tabano', 'Ray Tabano', '1970-10', '1971-04'),
                  ('mb-perry', 'Joe Perry', '1984-04', null),
                ])
                  {
                    'type': 'member of band',
                    'direction': 'backward',
                    'begin': begin,
                    'end': end,
                    'ended': end != null,
                    'artist': {'id': id, 'name': name, 'sort-name': name},
                  },
              ],
            }),
            200,
          ),
        ),
      );
      await pumpHome(tester, size, musicBrainz: brainz);
      await tester.tap(size.width < 600 ? find.text('Artistas') : find.byTooltip('Artistas'));
      await tester.pumpAndSettle();
      await tester.tap(tile('Aerosmith'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(ArtistPage), matching: find.byTooltip('Ver a biografia')));
      await tester.pumpAndSettle();

      final page = find.byType(BiographyPage);
      Finder inPage(String text) => find.descendant(of: page, matching: find.text(text));
      await tester.scrollUntilVisible(
        inPage('Ray Tabano'),
        100,
        // The page's own, the first: the gallery's scrolls sideways.
        scrollable: find.descendant(of: page, matching: find.byType(Scrollable)).first,
      );
      expect(inPage('Integrantes'), findsOneWidget);
      expect(inPage('Ex-integrantes'), findsOneWidget);
      expect(inPage('1970\u00a0–\u00a01979, desde\u00a01984'), findsOneWidget);
      expect(
        find.descendant(of: page, matching: find.byTooltip('Abrir o artista')),
        findsOneWidget,
        reason: 'Joe Perry alone is in the library',
      );

      await tester.tap(inPage('Joe Perry'));
      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(artistName('Joe Perry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a band\'s members, one a line, their years beside them, lined up: those it has now, then those it had; '
      'where it has broken up, all of them under one title', (tester) async {
    BandMember member(String name, List<BandYears> years, {bool current = false}) =>
        (id: name, name: name, current: current, years: years);

    Future<void> pump(Band band) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('pt')],
          home: BiographyPage(
            const Biography(['Aerosmith is an American rock band.']),
            name: 'Aerosmith',
            band: Future.value(band),
          ),
        ),
      );
      await tester.pump();
    }

    await pump((
      years: (begin: 1970, end: null, ended: false),
      members: [
        member('Steven Tyler', [(begin: 1970, end: null, ended: false)], current: true),
        member('Joe Perry', [
          (begin: 1970, end: 1979, ended: true),
          (begin: 1984, end: null, ended: false),
        ], current: true),
        member('Ray Tabano', [(begin: 1970, end: 1971, ended: true)]),
        member('Tommy Moore', [(begin: 1960, end: 1960, ended: true)]),
      ],
    ));
    final perry = find.text('1970\u00a0–\u00a01979, desde\u00a01984');
    final tyler = find.text('desde\u00a01970');
    expect(find.text('1970\u00a0–\u00a01971'), findsOneWidget);
    expect(find.text('1960'), findsOneWidget, reason: 'in one year alone');
    final lines = ['Integrantes', 'Steven Tyler', 'Joe Perry', 'Ex-integrantes', 'Ray Tabano', 'Tommy Moore'];

    // Those it has now, then those it had, each in the order they came.
    for (final (i, text) in lines.indexed.skip(1)) {
      expect(tester.getTopLeft(find.text(text)).dy, greaterThan(tester.getTopLeft(find.text(lines[i - 1])).dy));
    }

    // Their first line, where they wrap (as here, in the tests' wide letters).
    expect(tester.getTopLeft(perry).dy, tester.getTopLeft(find.text('Joe Perry')).dy, reason: 'beside the name');
    expect(tester.getTopLeft(perry).dx, tester.getTopLeft(tyler).dx, reason: 'lined up');
    expect(tester.getTopLeft(tyler).dx, greaterThan(tester.getTopRight(find.text('Steven Tyler')).dx));
    expect(find.byTooltip('Abrir o artista'), findsNothing, reason: 'none in the library');

    await pump((
      years: (begin: 1960, end: 1970, ended: true),
      members: [
        member('Paul McCartney', [(begin: 1960, end: 1970, ended: true)]),
        member('Pete Best', [(begin: 1960, end: 1962, ended: true)]),
      ],
    ));
    expect(find.text('Integrantes'), findsOneWidget);
    expect(find.text('Ex-integrantes'), findsNothing);
    expect(find.text('Pete Best'), findsOneWidget);
  });

  testWidgets('a band\'s years: since it formed, from one to the other, until it broke up, or to a year not known; '
      'an artist without them, their name alone', (tester) async {
    for (final (BandYears? years, text) in [
      // On one line: no space in the years that the line could break at.
      ((begin: 1985, end: null, ended: false), 'Os Mutantes (desde 1985)'),
      ((begin: 1966, end: 1978, ended: true), 'Os Mutantes (1966 – 1978)'),
      ((begin: null, end: 1978, ended: true), 'Os Mutantes (até 1978)'),
      ((begin: 1966, end: null, ended: true), 'Os Mutantes (1966 – ?)'),
      (null, 'Os Mutantes'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('pt')],
          home: BiographyPage(
            const Biography(['Os Mutantes are a Brazilian rock band.']),
            name: 'Os Mutantes',
            band: Future.value(years == null ? null : (years: years, members: const <BandMember>[])),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(text), findsOneWidget, reason: '$years');
    }
  });
}
