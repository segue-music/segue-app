// The README's pictures of the app (docs/screenshots/), on a phone, a tablet, a computer and a TV, from a made-up
// library whose covers are drawn here, rendered as the tests render the app:
//
//   tool/flutter.sh test tool/screenshots.dart
//
// Out of test/, so that the suite doesn't make them again on every run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/mixes.dart';
import 'package:segue/player/player.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/app/television_screen.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/widgets/cover.dart';
import 'package:segue/ui/widgets/equalizer.dart';

import '../test/fakes.dart';

/// Where the pictures go, from the app's folder, where `flutter test` runs.
const _folder = 'docs/screenshots';

/// The README's language.
const _language = Locale('en');

final _server = Uri.parse('https://music.example');
const _credentials = SubsonicCredentials(username: 'sam', token: 't', salt: 's');

void main() {
  // Each picture is of the app at rest: an equalizer that moves would never let it settle. As in the tests
  // (test/flutter_test_config.dart), which this is, out of test/.
  // ignore: invalid_use_of_visible_for_testing_member
  Equalizer.moves = false;
  // The same mixes each time, rather than a picture of the computer's home anew: with this seed, those of the picture
  // first made (Indie, Electronic, the 1980s, ...).
  // ignore: invalid_use_of_visible_for_testing_member
  SuggestedMixes.seed = 50307;

  setUpAll(() async {
    await _loadFonts();
    _pictures.addAll(await _paintPictures());
    HttpOverrides.global = _PictureOverrides();
  });

  testWidgets('a phone: the full-screen player', (tester) async {
    await _pumpApp(tester, _Device.phone, album: 'coastline');
    await tester.tap(find.descendant(of: find.byTooltip(_strings.openPlayer), matching: find.byType(Cover)));
    await _settle(tester);
    await _save(tester, _Device.phone);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a tablet: the full-screen player with the lyrics', (tester) async {
    await _pumpApp(tester, _Device.tablet, album: 'estrada');
    await tester.tap(find.descendant(of: find.byTooltip(_strings.openPlayer), matching: find.byType(Cover)));
    await _settle(tester);
    await tester.tap(find.byTooltip(_strings.showLyrics).first);
    await _settle(tester);
    await _save(tester, _Device.tablet);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a computer: the home', (tester) async {
    await _pumpApp(tester, _Device.desktop, album: 'arcade');
    await _save(tester, _Device.desktop);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a TV: the full-screen player, as karaoke', (tester) async {
    await _pumpApp(tester, _Device.tv, album: 'kite');
    await tester.tap(find.byTooltip(_strings.nowPlaying));
    await _settle(tester);
    await _save(tester, _Device.tv);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

final _strings = lookupAppLocalizations(_language);
final _screen = GlobalKey();

/// The devices the pictures are of: each picture is named after its device, which it shows in its frame ([_frame]).
enum _Device {
  phone(Size(393, 852), 3, statusBar: 32, gestureBar: 20),
  tablet(Size(1194, 834), 2, brightness: Brightness.light, statusBar: 24, gestureBar: 20),
  desktop(Size(1440, 900), 2),
  tv(Size(960, 540), 2);

  const _Device(
    this.size,
    this.pixelRatio, {
    this.brightness = Brightness.dark,
    this.statusBar = 0,
    this.gestureBar = 0,
  });

  /// The screen's size, in logical pixels.
  final Size size;

  /// How many of the picture's pixels make a logical one.
  final double pixelRatio;

  /// The app's theme on it.
  final Brightness brightness;

  /// How tall Android's status bar at the top of the screen is, and its gesture bar at the bottom: the app keeps out
  /// of them, and the frame draws them.
  final double statusBar;
  final double gestureBar;
}

/// The app signed in to the made-up library, its hub connected, on [device]'s screen, playing here the first song of
/// [album] (its id), a minute in, its pictures loaded.
Future<void> _pumpApp(WidgetTester tester, _Device device, {required String album}) async {
  final api = SubsonicApi(_server, _credentials, client: MockClient((request) async => _answer(request)));
  final player = PlayerController(FakeEngine(), api);
  final (_, songs) = await api.album(album);
  await player.playQueue(songs, position: const Duration(seconds: 64), play: false);
  final services = Services(
    Session(server: _server, credentials: _credentials, deviceId: 'this', deviceName: 'This device'),
    api,
    player,
    ConnectController(player: player, client: _hub()),
  );
  await services.favorites.load();
  final television = device == _Device.tv;
  final systemBars = FakeViewPadding(
    top: device.statusBar * device.pixelRatio,
    bottom: device.gestureBar * device.pixelRatio,
  );
  tester.view
    ..physicalSize = device.size * device.pixelRatio
    ..devicePixelRatio = device.pixelRatio
    ..padding = systemBars
    ..viewPadding = systemBars;
  addTearDown(tester.view.reset);

  if (television) {
    // As on a TV, where the focus always shows (lib/device.dart).
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  }

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screen,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: _language,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: segueTheme(device.brightness),
        builder: (context, child) => ServicesScope(
          services: services,
          child: TelevisionScreen(enabled: television, child: child!),
        ),
        home: HomePage(onSignOut: () {}),
      ),
    ),
  );
  await _settle(tester);
  await player.play();
  await _settle(tester);
}

/// A hub that sees the user's other devices, which play nothing; never connected, but said to be, so that the top bar
/// shows Connect working.
SegueClient _hub() {
  final client = SegueClient(
    url: Uri.parse('ws://unused'),
    auth: Auth.subsonic(username: _credentials.username, token: _credentials.token, salt: _credentials.salt),
    device: const DeviceInfo(
      id: 'this',
      name: 'This device',
      client: 'segue',
      api: Api.subsonic,
      roles: [Role.player, Role.controller],
      capabilities: CommandAction.values,
    ),
  )..status = HubStatus.connected;

  for (final (id, name) in [('tv', 'Living room TV'), ('speaker', 'Kitchen speaker'), ('laptop', 'Laptop')]) {
    client.devices[id] = Device(
      info: DeviceInfo(
        id: id,
        name: name,
        client: 'segue',
        api: Api.subsonic,
        roles: const [Role.player, Role.controller],
        capabilities: CommandAction.values,
      ),
      online: true,
    );
  }

  return client;
}

/// Lets the pictures load: their bytes come at once, but the engine decodes them for real, outside the test's fake
/// time, which only goes on as the test pumps.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 8; round++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

/// Saves the screen as [device]'s picture, in its frame: whole, as PNG, which the README links to, and at half its
/// width, as WebP, which the README shows, a tenth as heavy, as sharp as the page shows it on a screen of 2 pixels per
/// point.
Future<void> _save(WidgetTester tester, _Device device) async {
  final screen = _screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await screen.toImage(pixelRatio: device.pixelRatio);
    final framed = await _frame(image, device);
    final png = await framed.toByteData(format: ui.ImageByteFormat.png);
    final width = framed.width;
    image.dispose();
    framed.dispose();
    final file = File('$_folder/${device.name}.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    // cwebp is in the dev image (tool/dev.Dockerfile).
    final webp = await Process.run('cwebp', [
      '-quiet',
      ...['-q', '88', '-alpha_q', '100'],
      ...['-resize', '${width ~/ 2}', '0'],
      file.path,
      ...['-o', '$_folder/${device.name}.webp'],
    ]);

    if (webp.exitCode != 0) {
      throw Exception('cwebp failed: ${webp.stderr}');
    }
  });
}

/// Roboto, from Flutter's own copy (bin/cache/artifacts/material_fonts), under the families the theme asks for on
/// each platform the pictures are of: a test otherwise draws every letter as a box.
Future<void> _loadFonts() async {
  // flutter_tester is in bin/cache/artifacts/engine/<platform>/.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = [
    for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black'])
      File('${artifacts.path}/material_fonts/Roboto-$weight.ttf').readAsBytesSync(),
  ];

  for (final family in ['Roboto', 'Ubuntu']) {
    final loader = FontLoader(family);

    for (final font in fonts) {
      loader.addFont(Future.value(ByteData.sublistView(font)));
    }

    await loader.load();
  }
}

/// The covers, the artists' pictures and the playlists', as PNG, by their cover ids.
final _pictures = <String, Uint8List>{};

/// Images ask the pictures of [_pictures], by their ids: a test reaches no network.
class _PictureOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _PictureClient();
}

class _PictureClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _PictureRequest(_pictures[url.queryParameters['id']]);
}

class _PictureRequest extends Fake implements HttpClientRequest {
  _PictureRequest(this._picture);

  final Uint8List? _picture;

  @override
  Future<HttpClientResponse> close() async => _PictureResponse(_picture);
}

class _PictureResponse extends Fake implements HttpClientResponse {
  _PictureResponse(this._picture);

  final Uint8List? _picture;

  @override
  int get statusCode => _picture == null ? HttpStatus.notFound : HttpStatus.ok;

  @override
  int get contentLength => _picture?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(_picture!).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

/// The made-up library, as a Subsonic server (Navidrome) answers it.
http.Response _answer(http.Request request) {
  final endpoint = request.url.pathSegments.last.replaceAll('.view', '');
  final query = request.url.queryParameters;
  final id = query['id'];
  final found = switch (endpoint) {
    'ping' || 'scrobble' || 'star' || 'unstar' => const <String, Object?>{},
    'getOpenSubsonicExtensions' => {'openSubsonicExtensions': const <Object?>[]},
    'getAlbumList2' => {
      'albumList2': {'album': _albumList(query).map(_albumJson).toList()},
    },
    'getAlbum' => switch (_albums.where((album) => album.id == id).firstOrNull) {
      final album? => {
        'album': {
          ..._albumJson(album),
          'song': [for (var track = 0; track < album.songs.length; track++) _songJson(album, track)],
        },
      },
      null => null,
    },
    'getSong' => switch (_songs[id]) {
      (final album, final track)? => {'song': _songJson(album, track)},
      null => null,
    },
    'getGenres' => {
      'genres': {
        'genre': [
          for (final genre in {for (final album in _albums) album.genre})
            {
              'value': genre,
              'albumCount': _albums.where((album) => album.genre == genre).length,
              'songCount': [for (final album in _albums.where((album) => album.genre == genre)) ...album.songs].length,
            },
        ],
      },
    },
    'getRandomSongs' => {
      'randomSongs': {'song': _randomSongs(query)},
    },
    'getArtists' => {
      'artists': {
        'index': [
          {
            'name': '#',
            'artist': [
              for (final artist in [..._artists]..sort((a, b) => a.name.compareTo(b.name))) _artistJson(artist),
            ],
          },
        ],
      },
    },
    'getArtist' => switch (_artists.where((artist) => artist.id == id).firstOrNull) {
      final artist? => {
        'artist': {
          ..._artistJson(artist),
          'album': [
            for (final album in _albums)
              if (album.artist == artist.id) _albumJson(album),
          ],
        },
      },
      null => null,
    },
    'getArtistInfo2' => {
      'artistInfo2': {
        'similarArtist': [
          for (final artist in _artists)
            if (artist.id != id) _artistJson(artist),
        ].take(5).toList(),
      },
    },
    'getTopSongs' => {
      'topSongs': {
        'song': [
          for (final album in _albums)
            if (_artistOf(album).name == query['artist'])
              for (var track = 0; track < album.songs.length; track++) _songJson(album, track),
        ].take(5).toList(),
      },
    },
    'getSimilarSongs2' => {
      'similarSongs2': {
        'song': _randomSongs(const {'size': '20'}),
      },
    },
    'getPlaylists' => {
      'playlists': {'playlist': _playlists.map(_playlistJson).toList()},
    },
    'getPlaylist' => switch (_playlists.where((playlist) => playlist.id == id).firstOrNull) {
      final playlist? => {
        'playlist': {
          ..._playlistJson(playlist),
          'entry': [for (final song in playlist.songs) _songJsonOf(song)],
        },
      },
      null => null,
    },
    'getStarred2' => {
      'starred2': {
        'song': [for (final song in _starredSongs) _songJsonOf(song)],
        'album': [
          for (final album in _albums)
            if (_starredAlbums.contains(album.id)) _albumJson(album),
        ],
        'artist': [
          for (final artist in _artists)
            if (_starredArtists.contains(artist.id)) _artistJson(artist),
        ],
      },
    },
    'getLyricsBySongId' => {
      'type': 'navidrome',
      'lyricsList': {
        'structuredLyrics': [
          if (_lyrics[id] case final lines?)
            {
              'synced': true,
              'line': [
                for (final (start, text) in lines) {'start': start * 1000, 'value': text},
              ],
            },
        ],
      },
    },
    'search3' => {
      'searchResult3': {
        'artist': [
          for (final artist in _artists)
            if (artist.name.toLowerCase().contains(query['query']!.toLowerCase())) _artistJson(artist),
        ],
        'album': [
          for (final album in _albums)
            if (album.name.toLowerCase().contains(query['query']!.toLowerCase())) _albumJson(album),
        ],
        'song': const <Object?>[],
      },
    },
    _ => null,
  };

  return found == null
      ? http.Response('', 404)
      : http.Response(
          jsonEncode({
            'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...found},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
}

List<_Album> _albumList(Map<String, String> query) {
  final albums = switch (query['type']) {
    'byYear' => [..._albums]..sort((a, b) => b.year.compareTo(a.year)),
    'frequent' => [..._albums]..sort((a, b) => b.plays.compareTo(a.plays)),
    'newest' || 'recent' => _albums,
    'alphabeticalByName' => [..._albums]..sort((a, b) => a.name.compareTo(b.name)),
    'byGenre' => [
      for (final album in _albums)
        if (album.genre == query['genre']) album,
    ],
    'starred' => [
      for (final album in _albums)
        if (_starredAlbums.contains(album.id)) album,
    ],
    _ => const <_Album>[],
  };

  return albums.skip(int.parse(query['offset'] ?? '0')).take(int.parse(query['size'] ?? '20')).toList();
}

/// Songs of the genre and the years [query] asks for, in an order of their own, the same each time.
List<Map<String, Object?>> _randomSongs(Map<String, String> query) {
  final from = int.tryParse(query['fromYear'] ?? '');
  final to = int.tryParse(query['toYear'] ?? '');
  final songs = [
    for (final album in _albums)
      if ((query['genre'] == null || album.genre == query['genre']) &&
          (from == null || album.year >= from) &&
          (to == null || album.year <= to))
        for (var track = 0; track < album.songs.length; track++) _songJson(album, track),
  ]..shuffle(Random(7));

  return songs.take(int.parse(query['size'] ?? '10')).toList();
}

_Artist _artistOf(_Album album) => _artists.firstWhere((artist) => artist.id == album.artist);

Map<String, Object?> _artistJson(_Artist artist) => {
  'id': artist.id,
  'name': artist.name,
  'coverArt': 'ar-${artist.id}',
  'albumCount': _albums.where((album) => album.artist == artist.id).length,
};

Map<String, Object?> _albumJson(_Album album) => {
  'id': album.id,
  'name': album.name,
  'artist': _artistOf(album).name,
  'artistId': album.artist,
  'coverArt': 'al-${album.id}',
  'year': album.year,
  'genre': album.genre,
  'songCount': album.songs.length,
  'duration': album.songs.fold<int>(0, (total, song) => total + song.$2),
  'playCount': album.plays,
};

Map<String, Object?> _songJson(_Album album, int track) => {
  'id': '${album.id}-${track + 1}',
  'title': album.songs[track].$1,
  'artist': _artistOf(album).name,
  'artistId': album.artist,
  'artists': [
    {'id': album.artist, 'name': _artistOf(album).name},
  ],
  'album': album.name,
  'albumId': album.id,
  'coverArt': 'al-${album.id}',
  'duration': album.songs[track].$2,
  'track': track + 1,
  'year': album.year,
  'genre': album.genre,
  'playCount': max(0, album.plays - track * 4),
};

/// The song whose id is [id].
Map<String, Object?> _songJsonOf(String id) {
  final (album, track) = _songs[id]!;

  return _songJson(album, track);
}

Map<String, Object?> _playlistJson(_Playlist playlist) => {
  'id': playlist.id,
  'name': playlist.name,
  'owner': _credentials.username,
  'coverArt': 'pl-${playlist.id}',
  'songCount': playlist.songs.length,
  'duration': [for (final song in playlist.songs) _songJsonOf(song)['duration']! as int]
      .fold<int>(0, (total, seconds) => total + seconds),
};

class _Artist {
  const _Artist(this.id, this.name, this.colors);

  final String id;
  final String name;

  /// Their picture's colors: the background first.
  final List<Color> colors;
}

class _Album {
  const _Album(this.id, this.name, this.artist, this.year, this.genre, this.art, this.songs, {required this.plays});

  final String id;
  final String name;

  /// The artist's id.
  final String artist;
  final int year;
  final String genre;
  final _Art art;

  /// Each song's title and length in seconds.
  final List<(String, int)> songs;
  final int plays;
}

class _Playlist {
  const _Playlist(this.id, this.name, this.songs);

  final String id;
  final String name;

  /// The songs' ids.
  final List<String> songs;
}

/// How a cover is drawn: a [_Style] in [colors], the background first, and the album's name and artist on it in
/// [ink], where there is one.
class _Art {
  const _Art(this.style, this.colors, {this.ink});

  final _Style style;
  final List<Color> colors;
  final Color? ink;
}

enum _Style { sunset, rings, waves, blobs, type, arcs, halftone, bauhaus }

const _artists = [
  _Artist('marina', 'Marina Vale', [Color(0xff2b1055), Color(0xffff6f91), Color(0xffffc75f), Color(0xff845ec2)]),
  _Artist('lanterns', 'The Paper Lanterns', [Color(0xff0f3d3e), Color(0xfff2a541), Color(0xffe4572e)]),
  _Artist('lua', 'Lua Clara', [Color(0xff3d1a2a), Color(0xffc8553d), Color(0xfff4a261), Color(0xff588b8b)]),
  _Artist('northbound', 'Northbound Static', [Color(0xff0b132b), Color(0xff5bc0be), Color(0xff3a506b)]),
  _Artist('ana', 'Ana Prado Trio', [Color(0xff1b3a6b), Color(0xffe07a5f), Color(0xfff4f1de)]),
  _Artist('ray', 'Ray Holloway & The Embers', [Color(0xff3b1f0e), Color(0xffe76f51), Color(0xffe9c46a)]),
  _Artist('dust', 'Dust Choir', [Color(0xff2b2d42), Color(0xffef8354), Color(0xffbfc0c0)]),
  _Artist('glasshouse', 'Glasshouse', [Color(0xff03071e), Color(0xffff006e), Color(0xff3a86ff)]),
  _Artist('ventiladores', 'Os Ventiladores', [Color(0xff1d1d1b), Color(0xffe63946), Color(0xffffb703)]),
  _Artist('kaito', 'Kaito Sun', [Color(0xff0d0221), Color(0xfff6019d), Color(0xfffbb13c)]),
  _Artist('ze', 'Zé Coqueiro', [Color(0xff2f3e2f), Color(0xfff2cc8f), Color(0xffe07a5f)]),
];

/// The albums, the latest added first.
const _albums = [
  _Album(
    'coastline',
    'Coastline Radio',
    'marina',
    2024,
    'Pop',
    _Art(_Style.sunset, [
      Color(0xff1a1040),
      Color(0xffff5e7e),
      Color(0xffffd36e),
      Color(0xffff6f91),
      Color(0xff2b1055),
      Color(0xffff8fab),
    ], ink: Color(0xfffff1e6)),
    [
      ('Neon Tide', 222),
      ('Coastline Radio', 245),
      ('Paper Boats', 198),
      ('Undertow', 261),
      ('Salt in the Air', 235),
      ('Lighthouse Keeper', 280),
      ('Static Hearts', 207),
      ('Low Tide, High Hopes', 230),
      ('Night Ferry', 302),
      ('Shoreline', 252),
    ],
    plays: 42,
  ),
  _Album(
    'gardens',
    'Low Frequency Gardens',
    'northbound',
    2022,
    'Electronic',
    _Art(_Style.halftone, [Color(0xff0b132b), Color(0xff5bc0be), Color(0xff3a506b)]),
    [
      ('Low Frequency Gardens', 318),
      ('Moss', 287),
      ('Signal Bloom', 342),
      ('Greenhouse Effect', 301),
      ('Photosynthesis', 276),
      ('Night Garden', 355),
    ],
    plays: 33,
  ),
  _Album(
    'estrada',
    'Estrada de Terra',
    'lua',
    2021,
    'MPB',
    _Art(_Style.waves, [
      Color(0xfff4e3c1),
      Color(0xffc8553d),
      Color(0xff8c2f39),
      Color(0xff588b8b),
      Color(0xff2d4739),
    ], ink: Color(0xff2d4739)),
    [
      ('Estrada de Terra', 248),
      ('Cheiro de Chuva', 213),
      ('Varanda', 226),
      ('Janela do Trem', 259),
      ('Fim de Tarde', 237),
      ('Rio Manso', 271),
    ],
    plays: 26,
  ),
  _Album(
    'softfocus',
    'Soft Focus',
    'marina',
    2020,
    'Pop',
    _Art(_Style.type, [Color(0xfff3d9c6), Color(0xffd1495b), Color(0xff2e2a3a)]),
    [
      ('Polaroid Summer', 214),
      ('Soft Focus', 236),
      ('Slow Motion Heart', 251),
      ('Daydream Club', 199),
      ('Window Seat', 227),
      ('Blur', 243),
    ],
    plays: 18,
  ),
  _Album(
    'kite',
    'Kite Season',
    'lanterns',
    2019,
    'Indie',
    _Art(_Style.rings, [Color(0xff0f3d3e), Color(0xfff2a541), Color(0xfff5e6c8), Color(0xffe4572e)]),
    [
      ('Kite Season', 238),
      ('Rooftop Weather', 204),
      ('Cardboard Castles', 256),
      ('The Long Way Round', 289),
      ('Small Hours', 221),
      ('Paper Lanterns', 274),
      ('Westbound', 247),
    ],
    plays: 30,
  ),
  _Album(
    'prism',
    'Prism Hours',
    'glasshouse',
    2018,
    'Electronic',
    _Art(_Style.blobs, [
      Color(0xff03071e),
      Color(0xffff006e),
      Color(0xff8338ec),
      Color(0xff3a86ff),
      Color(0xffffbe0b),
    ], ink: Color(0xffffffff)),
    [('Prism Hours', 284), ('Refraction', 263), ('Glass Floor', 247), ('Spectrum', 296), ('Halo', 238)],
    plays: 20,
  ),
  _Album(
    'saudade',
    'Saudade em Neon',
    'lua',
    2017,
    'MPB',
    _Art(_Style.blobs, [
      Color(0xff140f2d),
      Color(0xfff72585),
      Color(0xff7209b7),
      Color(0xff4cc9f0),
    ], ink: Color(0xffffffff)),
    [('Saudade em Neon', 231), ('Madrugada', 254), ('Avenida', 207), ('Luz de Vela', 240), ('Céu de Néon', 266)],
    plays: 15,
  ),
  _Album(
    'machines',
    'Quiet Machines',
    'northbound',
    2016,
    'Electronic',
    _Art(_Style.bauhaus, [
      Color(0xffe9e4d8),
      Color(0xff222222),
      Color(0xffd64933),
      Color(0xff2a6f97),
      Color(0xfff2c14e),
    ]),
    [('Quiet Machines', 296), ('Idle Loop', 254), ('Servo', 238), ('Clockwork Rain', 312), ('Standby', 275)],
    plays: 9,
  ),
  _Album(
    'northern',
    'Northern Lines',
    'lanterns',
    2015,
    'Indie',
    _Art(_Style.arcs, [Color(0xff1d3557), Color(0xffe63946), Color(0xfff1faee), Color(0xffa8dadc), Color(0xff457b9d)]),
    [
      ('Northern Lines', 233),
      ('Last Train Home', 262),
      ('Snowglobe', 198),
      ('Harbour Bells', 241),
      ('Long Exposure', 305),
    ],
    plays: 12,
  ),
  _Album(
    'concrete',
    'Concrete Summer',
    'dust',
    1996,
    'Rock',
    _Art(_Style.halftone, [Color(0xffffb703), Color(0xff023047)]),
    [
      ('Concrete Summer', 224),
      ('Overpass', 201),
      ('Heatwave Static', 247),
      ('Parking Lot Prayer', 263),
      ('Burnout', 236),
      ('Gasoline Moon', 289),
    ],
    plays: 17,
  ),
  _Album(
    'copper',
    'Copper Skies',
    'dust',
    1993,
    'Rock',
    _Art(_Style.waves, [
      Color(0xff2b2d42),
      Color(0xffef8354),
      Color(0xffbfc0c0),
      Color(0xff4f5d75),
    ], ink: Color(0xffef8354)),
    [('Copper Skies', 251), ('Rust Belt', 233), ('Dry County', 268), ('Thunderhead', 245)],
    plays: 11,
  ),
  _Album(
    'arcade',
    'Midnight Arcade',
    'kaito',
    1987,
    'Pop',
    _Art(_Style.sunset, [
      Color(0xff0d0221),
      Color(0xff261447),
      Color(0xfffbb13c),
      Color(0xffff3864),
      Color(0xff1b0b3b),
      Color(0xfff6019d),
    ]),
    [
      ('Midnight Arcade', 247),
      ('High Score', 219),
      ('Pixel Heart', 233),
      ('Cassette Love', 251),
      ('Insert Coin', 205),
      ('City Pop Dream', 268),
    ],
    plays: 19,
  ),
  _Album(
    'ventania',
    'Ventania',
    'ventiladores',
    1985,
    'Rock',
    _Art(_Style.bauhaus, [
      Color(0xfff1e9da),
      Color(0xff1d1d1b),
      Color(0xffe63946),
      Color(0xff457b9d),
      Color(0xffffb703),
    ]),
    [('Ventania', 213), ('Fita Cassete', 198), ('Ladeira', 224), ('Garoa', 207), ('Néon e Concreto', 236)],
    plays: 14,
  ),
  _Album(
    'varanda',
    'Sambas de Varanda',
    'ze',
    1978,
    'Samba',
    _Art(_Style.rings, [Color(0xff2f3e2f), Color(0xfff2cc8f), Color(0xffe07a5f), Color(0xff81b29a)]),
    [
      ('Sambas de Varanda', 196),
      ('Quintal', 208),
      ('Pandeiro de Prata', 187),
      ('Roda de Domingo', 233),
      ('Saudade de Itapuã', 224),
    ],
    plays: 16,
  ),
  _Album(
    'slowfire',
    'Slow Fire',
    'ray',
    1974,
    'Soul',
    _Art(_Style.arcs, [Color(0xfff6e7cb), Color(0xffe76f51), Color(0xfff4a261), Color(0xffe9c46a), Color(0xff2a9d8f)]),
    [
      ('Slow Fire', 254),
      ('Sweet Little Daylight', 231),
      ('Hold On, Brother', 266),
      ('Sunday Dress', 219),
      ('Ember Glow', 288),
      ('Keep the Light On', 243),
    ],
    plays: 21,
  ),
  _Album(
    'bluehour',
    'Blue Hour Sessions',
    'ana',
    1962,
    'Jazz',
    _Art(_Style.type, [Color(0xff1b3a6b), Color(0xfff4f1de), Color(0xffe07a5f)]),
    [('Blue Hour', 372), ('Rua Augusta', 318), ('Smoke and Mirrors', 401), ('Late Set', 345), ('Bossa for Ana', 287)],
    plays: 24,
  ),
];

/// Every song, by its id: its album and its place there.
final _songs = {
  for (final album in _albums)
    for (var track = 0; track < album.songs.length; track++) '${album.id}-${track + 1}': (album, track),
};

const _playlists = [
  _Playlist('road', 'Road Trip', [
    'coastline-2',
    'concrete-1',
    'kite-1',
    'arcade-1',
    'copper-1',
    'estrada-1',
    'ventania-1',
    'northern-2',
  ]),
  _Playlist('sunday', 'Sunday Morning', ['slowfire-2', 'bluehour-2', 'varanda-1', 'estrada-3', 'softfocus-5']),
  _Playlist('focus', 'Deep Focus', ['gardens-1', 'machines-1', 'prism-2', 'gardens-3', 'machines-4']),
  _Playlist('night', 'Late Night Drive', ['arcade-6', 'saudade-1', 'coastline-9', 'prism-1', 'bluehour-1']),
];

const _starredSongs = ['coastline-1', 'kite-1', 'slowfire-1', 'estrada-2'];
const _starredAlbums = {'coastline', 'kite', 'bluehour'};
const _starredArtists = {'marina', 'lua'};

/// The lyrics of the songs that have them, by their ids: each line's start, in seconds, and its words.
const _lyrics = {
  'coastline-1': [
    (14, 'City lights are spilling on the water'),
    (19, 'Every wave keeps singing back your name'),
    (25, 'I\'ve been driving with the windows open'),
    (30, 'Chasing static on the radio again'),
    (37, 'Oh, the neon tide is rising'),
    (42, 'Pulling me back to the shore'),
    (47, 'Every signal I\'ve been hiding'),
    (52, 'Comes in clearer than before'),
    (58, 'So turn it up, turn it up'),
    (63, 'Let the coastline carry us home'),
    (68, 'Turn it up, turn it up'),
    (73, 'We were never really alone'),
    (82, 'Paper boats and borrowed sweaters'),
    (87, 'Sand still in the passenger seat'),
    (92, 'We said nothing lasts forever'),
    (97, 'But the summer\'s in no hurry to leave'),
  ],
  'estrada-1': [
    (12, 'Poeira vermelha no vidro do carro'),
    (17, 'O rádio chiando uma canção de ninar'),
    (23, 'A tarde caindo devagar no barro'),
    (28, 'E eu sem pressa nenhuma de chegar'),
    (35, 'Estrada de terra, me leva pra casa'),
    (40, 'Onde o tempo anda descalço no chão'),
    (46, 'Estrada de terra, de curva e de brasa'),
    (51, 'Cabe o mundo inteiro na palma da mão'),
    (58, 'Ipê florido na beira do rio'),
    (63, 'Cheiro de café passado no fogão'),
    (69, 'A lua aparece e o céu fica frio'),
    (74, 'Mas tem fogueira acesa no meu coração'),
    (82, 'Estrada de terra, me leva pra casa'),
    (87, 'Onde o tempo anda descalço no chão'),
    (93, 'Estrada de terra, de curva e de brasa'),
    (98, 'Cabe o mundo inteiro na palma da mão'),
  ],
  'kite-1': [
    (9, 'We were running out of summer'),
    (14, 'Counting clouds above the town'),
    (19, 'Every string we tied together'),
    (24, 'Pulled us up and let us down'),
    (30, 'Rooftops painted gold and copper'),
    (35, 'Bicycles along the bay'),
    (40, 'If the wind should ever drop us'),
    (45, 'We\'ll just find another day'),
    (52, 'So hold on, it\'s kite season'),
    (57, 'And the wind is on our side'),
    (63, 'We don\'t need a better reason'),
    (68, 'Paper hearts against the sky'),
    (76, 'Strings are tangled in the branches'),
    (81, 'Somebody\'s calling us inside'),
    (86, 'We were never good at endings'),
    (91, 'So we let the evening fly'),
  ],
};

/// How many pixels across a picture is.
const _side = 800.0;

/// The pictures of [_pictures]: the albums' covers, each in its [_Art], the artists' and the playlists'.
Future<Map<String, Uint8List>> _paintPictures() async {
  final covers = <String, ui.Image>{};

  for (final (index, album) in _albums.indexed) {
    covers[album.id] = await _paint((canvas) {
      _drawArt(canvas, album.art, Random(index), title: album.name);

      if (album.art.ink case final ink?) {
        _drawLabel(canvas, album.name, _artistOf(album).name, ink);
      }
    });
  }

  final pictures = {for (final MapEntry(:key, :value) in covers.entries) 'al-$key': value};

  for (final (index, artist) in _artists.indexed) {
    pictures['ar-${artist.id}'] = await _paint((canvas) => _drawPortrait(canvas, artist.colors, Random(index)));
  }

  // As Navidrome's: the covers of its first albums, four in a square.
  for (final playlist in _playlists) {
    final albums = {for (final song in playlist.songs) _songs[song]!.$1.id}.take(4).toList();
    pictures['pl-${playlist.id}'] = await _paint((canvas) {
      for (final (index, album) in albums.indexed) {
        final image = covers[album]!;
        final place = Rect.fromLTWH(index % 2 * _side / 2, index ~/ 2 * _side / 2, _side / 2, _side / 2);
        canvas.drawImageRect(image, Offset.zero & const Size(_side, _side), place, Paint());
      }
    });
  }

  return {
    for (final MapEntry(:key, :value) in pictures.entries)
      key: (await value.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List(),
  };
}

Future<ui.Image> _paint(void Function(Canvas canvas) draw) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..clipRect(const Rect.fromLTWH(0, 0, _side, _side));
  draw(canvas);

  return recorder.endRecording().toImage(_side.toInt(), _side.toInt());
}

/// The cover [art], on a [_Style.type] one with [title] across it.
void _drawArt(Canvas canvas, _Art art, Random random, {String? title}) {
  final colors = art.colors;
  const all = Rect.fromLTWH(0, 0, _side, _side);
  canvas.drawRect(all, Paint()..color = colors[0]);

  switch (art.style) {
    case _Style.sunset:
      // A sun going down behind a grid, cut by bands that widen toward the horizon.
      const horizon = _side * 0.62;
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _side, horizon),
        Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, horizon), [colors[0], colors[1]]),
      );
      const center = Offset(_side / 2, _side * 0.42);
      const radius = _side * 0.26;
      canvas.drawCircle(
        center,
        radius * 1.15,
        Paint()
          ..color = colors[3].withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50),
      );
      var sun = Path()..addOval(Rect.fromCircle(center: center, radius: radius));

      for (var band = 0; band < 6; band++) {
        final top = center.dy + 24 + band * 30.0;
        sun = Path.combine(
          PathOperation.difference,
          sun,
          Path()..addRect(Rect.fromLTWH(0, top, _side, 4 + band * 3.0)),
        );
      }

      canvas
        ..save()
        ..clipRect(const Rect.fromLTWH(0, 0, _side, horizon))
        ..drawPath(
          sun,
          Paint()
            ..shader = ui.Gradient.linear(center.translate(0, -radius), center.translate(0, radius), [
              colors[2],
              colors[3],
            ]),
        )
        ..restore()
        ..drawRect(const Rect.fromLTRB(0, horizon, _side, _side), Paint()..color = colors[4]);
      final grid = Paint()
        ..color = colors[5].withValues(alpha: 0.8)
        ..strokeWidth = 3;

      for (var line = 0; line <= 8; line++) {
        final y = horizon + pow(line / 8, 2) * (_side - horizon);
        canvas.drawLine(Offset(0, y), Offset(_side, y), grid);
      }

      for (var line = -8; line <= 8; line++) {
        canvas.drawLine(const Offset(_side / 2, horizon), Offset(_side / 2 + line * 150, _side), grid);
      }

    case _Style.rings:
      final center = Offset(_side * (0.3 + random.nextDouble() * 0.4), _side * (0.3 + random.nextDouble() * 0.4));

      for (var ring = 16; ring >= 1; ring--) {
        canvas.drawCircle(center, ring * 44.0, Paint()..color = colors[ring % colors.length]);
      }

    case _Style.waves:
      canvas.drawCircle(const Offset(_side * 0.72, _side * 0.24), _side * 0.12, Paint()..color = colors[1]);

      for (var wave = 0; wave < 6; wave++) {
        final top = _side * (0.36 + wave * 0.11);
        final height = 18 + random.nextDouble() * 22;
        final phase = random.nextDouble() * pi * 2;
        final path = Path()..moveTo(0, _side);

        for (var x = 0.0; x <= _side; x += 8) {
          path.lineTo(x, top + sin(x / _side * pi * 2.6 + phase) * height);
        }

        path
          ..lineTo(_side, _side)
          ..close();
        canvas.drawPath(path, Paint()..color = colors[1 + wave % (colors.length - 1)]);
      }

    case _Style.blobs:
      for (var blob = 0; blob < 8; blob++) {
        final color = colors[1 + blob % (colors.length - 1)];
        final center = Offset(random.nextDouble() * _side, random.nextDouble() * _side);
        final radius = _side * (0.3 + random.nextDouble() * 0.35);
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..blendMode = BlendMode.screen
            ..shader = ui.Gradient.radial(center, radius, [color.withValues(alpha: 0.85), color.withValues(alpha: 0)]),
        );
      }

    case _Style.type:
      canvas.drawRect(const Rect.fromLTRB(0, _side * 0.66, _side, _side), Paint()..color = colors[2]);

    case _Style.arcs:
      // A rainbow, as on a sleeve of the 70s.
      const center = Offset(_side / 2, _side * 0.84);

      for (var arc = 1; arc < colors.length; arc++) {
        canvas.drawCircle(center, _side * 0.5 - (arc - 1) * 60, Paint()..color = colors[arc]);
      }

      canvas
        ..drawCircle(center, _side * 0.5 - (colors.length - 1) * 60, Paint()..color = colors[0])
        ..drawRect(Rect.fromLTRB(0, center.dy, _side, _side), Paint()..color = colors[colors.length - 1]);

    case _Style.halftone:
      const step = 28.0;
      final focus = Offset(_side * (0.25 + random.nextDouble() * 0.5), _side * (0.25 + random.nextDouble() * 0.5));
      final dot = Paint()..color = colors[1];

      for (var row = 0; row * step < _side + step; row++) {
        for (var column = 0; column * step < _side + step; column++) {
          final at = Offset(column * step + (row.isOdd ? step / 2 : 0), row * step);
          final distance = (at - focus).distance / _side;
          canvas.drawCircle(at, (1 - distance * 1.3).clamp(0.08, 1.0) * step * 0.5, dot);
        }
      }

    case _Style.bauhaus:
      const cell = _side / 3;

      for (var row = 0; row < 3; row++) {
        for (var column = 0; column < 3; column++) {
          final place = Rect.fromLTWH(column * cell, row * cell, cell, cell);
          final background = colors[random.nextInt(colors.length)];
          var shape = background;

          while (shape == background) {
            shape = colors[random.nextInt(colors.length)];
          }

          final paint = Paint()..color = shape;
          canvas
            ..save()
            ..clipRect(place)
            ..drawRect(place, Paint()..color = background);

          switch (random.nextInt(4)) {
            case 0:
              canvas.drawCircle(place.center, cell * 0.4, paint);
            case 1:
              canvas.drawCircle(place.topLeft, cell, paint);
            case 2:
              canvas.drawCircle(place.bottomCenter, cell / 2, paint);
            default:
              canvas.drawPath(
                Path()
                  ..moveTo(place.left, place.bottom)
                  ..lineTo(place.right, place.bottom)
                  ..lineTo(place.right, place.top)
                  ..close(),
                paint,
              );
          }

          canvas.restore();
        }
      }
  }

  if (art.style == _Style.type && title != null) {
    _drawText(
      canvas,
      title.toUpperCase().replaceAll(' ', '\n'),
      const Offset(56, 60),
      TextStyle(color: colors[1], fontSize: 132, fontWeight: FontWeight.w900, height: 0.92, letterSpacing: -4),
    );
  }
}

/// The album's name and artist, small, in the cover's corner.
void _drawLabel(Canvas canvas, String name, String artist, Color ink) {
  _drawText(
    canvas,
    name.toUpperCase(),
    const Offset(48, 48),
    TextStyle(color: ink, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 6),
  );
  _drawText(
    canvas,
    artist,
    const Offset(48, 96),
    TextStyle(color: ink.withValues(alpha: 0.8), fontSize: 28, fontWeight: FontWeight.w400, letterSpacing: 2),
  );
}

void _drawText(Canvas canvas, String text, Offset at, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(fontFamily: 'Roboto'),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: _side - at.dx * 2);
  painter
    ..paint(canvas, at)
    ..dispose();
}

/// An artist's picture: stage lights in their colors, out of focus.
void _drawPortrait(Canvas canvas, List<Color> colors, Random random) {
  _drawArt(canvas, _Art(_Style.blobs, colors), random);

  for (var light = 0; light < 18; light++) {
    final color = Color.lerp(colors[1 + light % (colors.length - 1)], const Color(0xffffffff), 0.5)!;
    canvas.drawCircle(
      Offset(random.nextDouble() * _side, random.nextDouble() * _side * 0.7),
      18 + random.nextDouble() * 50,
      Paint()
        ..color = color.withValues(alpha: 0.15 + random.nextDouble() * 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }
}

/// [screen] in [device]'s frame, on a transparent background, a shadow under it: a phone's and a tablet's with
/// Android's status and gesture bars over the screen's top and bottom, which the app kept out of; a computer as a
/// laptop. Drawn here, in logical pixels, as the device's own sizes would have it.
Future<ui.Image> _frame(ui.Image screen, _Device device) {
  // Room around the device, for its shadow.
  const margin = 32.0;
  final bezel = switch (device) {
    _Device.phone => const EdgeInsets.all(12),
    _Device.tablet => const EdgeInsets.all(18),
    _Device.desktop => const EdgeInsets.fromLTRB(16, 22, 16, 24),
    _Device.tv => const EdgeInsets.all(6),
  };
  final bodySize = bezel.inflateSize(device.size);
  // What goes beyond the body: a laptop's base, wider than its lid, under it, and a TV's stand. Whole logical pixels,
  // so that the screen falls on the picture's pixels, unscaled.
  final overhang = device == _Device.desktop ? (bodySize.width * 0.07).roundToDouble() : 0.0;
  final under = switch (device) {
    _Device.desktop => 16.0,
    _Device.tv => 46.0,
    _ => 0.0,
  };
  final body = Offset(margin + overhang, margin) & bodySize;
  final screenPlace = bezel.deflateRect(body);
  final size = Size(body.width + 2 * (margin + overhang), body.height + under + 2 * margin);
  final bodyShape = switch (device) {
    _Device.phone => RRect.fromRectAndRadius(body, const Radius.circular(56)),
    _Device.tablet => RRect.fromRectAndRadius(body, const Radius.circular(34)),
    _Device.desktop => RRect.fromRectAndCorners(
      body,
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    ),
    _Device.tv => RRect.fromRectAndRadius(body, const Radius.circular(8)),
  };
  final screenShape = RRect.fromRectAndRadius(
    screenPlace,
    Radius.circular(switch (device) {
      _Device.phone => 44,
      _Device.tablet => 16,
      _Device.desktop => 6,
      _Device.tv => 2,
    }),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(device.pixelRatio);
  final shadow = Paint()
    ..color = const Color(0x40000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
  final rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..shader = ui.Gradient.linear(
      body.topLeft,
      body.bottomRight,
      const [Color(0xff7a7a82), Color(0xff2e2e33), Color(0xff62626a)],
      const [0, 0.5, 1],
    );

  switch (device) {
    case _Device.phone:
      // The volume and power buttons, on the right.
      for (final (from, length) in [(0.2, 0.1), (0.34, 0.06)]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(body.right - 1, body.top + body.height * from, 3.5, body.height * length),
            const Radius.circular(1.5),
          ),
          Paint()..color = const Color(0xff4a4a50),
        );
      }

    case _Device.tablet:
      // The power and volume buttons, on the top.
      for (final (from, length) in [(0.08, 0.04), (0.75, 0.07)]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(body.left + body.width * from, body.top - 2.5, body.width * length, 3.5),
            const Radius.circular(1.5),
          ),
          Paint()..color = const Color(0xff4a4a50),
        );
      }

    case _Device.desktop:
      // The base, under the lid: a slab, lit from above, with a notch to open it by.
      final base = Rect.fromLTWH(body.left - overhang, body.bottom, body.width + 2 * overhang, under);
      canvas
        ..drawOval(Rect.fromCenter(center: base.bottomCenter, width: base.width * 0.9, height: 12), shadow)
        ..drawRRect(
          RRect.fromRectAndCorners(
            base,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
            bottomLeft: Radius.elliptical(60, under),
            bottomRight: Radius.elliptical(60, under),
          ),
          Paint()
            ..shader = ui.Gradient.linear(
              base.topCenter,
              base.bottomCenter,
              const [Color(0xfff2f3f6), Color(0xffc6c8ce), Color(0xff8e9097)],
              const [0, 0.5, 1],
            ),
        )
        ..drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromCenter(center: Offset(base.center.dx, base.top + 2.5), width: body.width * 0.15, height: 5),
            bottomLeft: const Radius.circular(5),
            bottomRight: const Radius.circular(5),
          ),
          Paint()..color = const Color(0xffa4a6ad),
        );

    case _Device.tv:
      // The stand: a neck, and a foot under it.
      final neck = Rect.fromCenter(center: Offset(body.center.dx, body.bottom + 17), width: 56, height: 34);
      final foot = Rect.fromCenter(center: Offset(body.center.dx, neck.bottom + 6), width: 280, height: 12);
      canvas
        ..drawOval(Rect.fromCenter(center: foot.bottomCenter, width: foot.width * 1.1, height: 10), shadow)
        ..drawRect(
          neck,
          Paint()
            ..shader = ui.Gradient.linear(
              neck.centerLeft,
              neck.centerRight,
              const [Color(0xff1e1e22), Color(0xff3e3e44), Color(0xff1e1e22)],
              const [0, 0.5, 1],
            ),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(foot, const Radius.circular(6)),
          Paint()
            ..shader = ui.Gradient.linear(foot.topCenter, foot.bottomCenter, const [
              Color(0xff4a4a50),
              Color(0xff1f1f23),
            ]),
        );
  }

  canvas
    ..drawRRect(bodyShape.shift(const Offset(0, 8)), shadow)
    ..drawRRect(bodyShape, Paint()..color = const Color(0xff101013))
    ..drawRRect(bodyShape.deflate(0.75), rim)
    ..save()
    ..clipRRect(screenShape)
    ..drawImageRect(
      screen,
      Offset.zero & Size(screen.width.toDouble(), screen.height.toDouble()),
      screenPlace,
      Paint()..filterQuality = FilterQuality.high,
    );

  if (device.statusBar > 0) {
    _drawSystemBars(canvas, screenPlace, device);
  }

  canvas.restore();
  final lens = Paint()..color = const Color(0xff050506);
  final ring = Paint()
    ..color = const Color(0xff26262c)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  switch (device) {
    case _Device.phone:
      // The camera, through the screen, in the middle of the status bar.
      final camera = Offset(screenPlace.center.dx, screenPlace.top + device.statusBar / 2);
      canvas
        ..drawCircle(camera, 6, lens)
        ..drawCircle(camera, 6, ring);

    case _Device.tablet || _Device.desktop:
      // The camera, in the bezel above the screen.
      final camera = Offset(body.center.dx, body.top + bezel.top / 2);
      canvas
        ..drawCircle(camera, 3, lens)
        ..drawCircle(camera, 3, ring);

    case _Device.tv:
      break;
  }

  return recorder.endRecording().toImage(
    (size.width * device.pixelRatio).round(),
    (size.height * device.pixelRatio).round(),
  );
}

/// Android's status bar over the top of [screen] (the time; the battery, the Wi-Fi and, on a phone, the mobile
/// network) and its gesture bar's handle over the bottom, in the color that stands out on the app's theme.
void _drawSystemBars(Canvas canvas, Rect screen, _Device device) {
  final ink = device.brightness == Brightness.dark ? const Color(0xffffffff) : const Color(0xff1c1b1f);
  final paint = Paint()..color = ink;
  final bar = Rect.fromLTWH(screen.left, screen.top, screen.width, device.statusBar);
  // Away from the screen's round corners.
  final side = device == _Device.phone ? 30.0 : 20.0;
  final time = TextPainter(
    text: TextSpan(
      text: '12:30',
      style: TextStyle(fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w500, color: ink),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  time
    ..paint(canvas, Offset(bar.left + side, bar.center.dy - time.height / 2))
    ..dispose();
  final battery = Rect.fromLTWH(bar.right - side - 22, bar.center.dy - 5.5, 20, 11);
  final wifi = Offset(battery.left - 16, bar.center.dy + 6);
  final network = Offset(wifi.dx - 26, bar.center.dy + 6);
  canvas
    ..drawRRect(
      RRect.fromRectAndRadius(battery, const Radius.circular(3)),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    )
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(battery.left + 2.2, battery.top + 2.2, (battery.width - 4.4) * 0.8, battery.height - 4.4),
        const Radius.circular(1.2),
      ),
      paint,
    )
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(battery.right + 0.8, battery.center.dy - 2.5, 2, 5),
        const Radius.circular(1),
      ),
      paint,
    )
    // A quarter of a circle, its point down.
    ..drawArc(Rect.fromCircle(center: wifi, radius: 12), -pi * 3 / 4, pi / 2, true, paint);

  if (device == _Device.phone) {
    canvas.drawPath(
      Path()
        ..moveTo(network.dx, network.dy)
        ..lineTo(network.dx + 12, network.dy)
        ..lineTo(network.dx + 12, network.dy - 12)
        ..close(),
      paint,
    );
  }

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(screen.center.dx, screen.bottom - device.gestureBar / 2),
        width: device == _Device.phone ? 108 : 160,
        height: 4,
      ),
      const Radius.circular(2),
    ),
    Paint()..color = ink.withValues(alpha: 0.85),
  );
}
