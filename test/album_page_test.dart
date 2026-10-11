import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/releases/musicbrainz.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album/album_page.dart';
import 'package:segue/ui/album/albums_view.dart';
import 'package:segue/ui/album/cover_page.dart';
import 'package:segue/ui/album/credits_page.dart';
import 'package:segue/ui/app/page_bar.dart';
import 'package:segue/ui/artist/artist_page.dart';
import 'package:segue/ui/player/now_playing_bar.dart';
import 'package:segue/ui/song/song_list_header.dart';
import 'package:segue/ui/widgets/cover.dart';
import 'package:segue/ui/widgets/text_link.dart';
import 'package:segue/ui/widgets/tile_row.dart';

import 'fakes.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The library's artists: Aerosmith, whose picture is `ar-ar1`, and Steven Tyler, whose MusicBrainz id is `mb1`.
const libraryArtists = [
  {'id': 'ar1', 'name': 'Aerosmith', 'albumCount': 1, 'coverArt': 'ar-ar1'},
  {'id': 'ar3', 'name': 'Steven Tyler', 'albumCount': 0, 'musicBrainzId': 'mb1'},
];

/// The page of Toys in the Attic, with the cover [coverArt], two songs by Aerosmith, `s1` and `s2`, with their
/// [contributors], by their ids, and then [more] songs and [others], the release date [releaseDate], the record labels
/// [recordLabels], the release types [releaseTypes] and the MusicBrainz id [musicBrainzId], on a screen of [size], with
/// what [musicBrainz] adds. Aerosmith's albums are this one and [moreByArtist]. Returns the player's engine.
Future<FakeEngine> pumpAlbum(
  WidgetTester tester, {
  String? coverArt = 'al-a1',
  int more = 0,
  List<Map<String, Object?>> others = const [],
  Map<String, List<Map<String, Object?>>> contributors = const {},
  Map<String, int>? releaseDate,
  List<String> recordLabels = const [],
  List<String>? releaseTypes,
  String? musicBrainzId,
  MusicBrainz? musicBrainz,
  List<Map<String, Object?>> moreByArtist = const [],
  Size size = const Size(1000, 700),
}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      if (request.url.path.endsWith('getArtist.view')) {
        final id = request.url.queryParameters['id'];
        final artist = libraryArtists.firstWhere((artist) => artist['id'] == id, orElse: () => libraryArtists.first);
        return subsonic({
          'artist': {
            ...artist,
            if (artist['id'] == 'ar1')
              'album': [
                {'id': 'a1', 'name': 'Toys in the Attic', 'artist': 'Aerosmith', 'artistId': 'ar1', 'year': 1975},
                ...moreByArtist,
              ],
          },
        });
      }

      if (request.url.path.endsWith('getArtists.view')) {
        return subsonic({
          'artists': {
            'index': [
              {'name': 'A', 'artist': libraryArtists},
            ],
          },
        });
      }

      return subsonic({
        'album': {
          'id': 'a1',
          'name': 'Toys in the Attic',
          'artist': 'Aerosmith',
          'artistId': 'ar1',
          'year': 1975,
          'coverArt': ?coverArt,
          'releaseDate': ?releaseDate,
          'releaseTypes': ?releaseTypes,
          'musicBrainzId': ?musicBrainzId,
          'recordLabels': [
            for (final label in recordLabels) {'name': label},
          ],
          'song': [
            {
              'id': 's1',
              'title': 'Walk This Way',
              'artist': 'Aerosmith',
              'artistId': 'ar1',
              'duration': 220,
              'contributors': ?contributors['s1'],
            },
            {
              'id': 's2',
              'title': 'Sweet Emotion',
              'artist': 'Aerosmith',
              'artistId': 'ar1',
              'duration': 274,
              'contributors': ?contributors['s2'],
            },
            for (var i = 1; i <= more; i++) {'id': 'm$i', 'title': 'Song $i', 'artist': 'Aerosmith', 'duration': 200},
            ...others,
          ],
        },
      });
    }),
  );
  final engine = FakeEngine();
  final player = PlayerController(engine, api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
    musicBrainz: musicBrainz,
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: const AlbumPage(Album(id: 'a1', name: 'Toys in the Attic')),
    ),
  );
  await tester.pumpAndSettle();

  return engine;
}

/// One of a song's contributors, as Navidrome gives them: [name], the library's artist whose id is [id], of [role],
/// playing [subRole].
Map<String, Object?> contributor(String role, String id, String name, {String? subRole}) => {
  'role': role,
  'subRole': ?subRole,
  'artist': {'id': id, 'name': name},
};

/// Toys in the Attic's credits, as the server has them: Steven Tyler, one of the library's artists, sang both songs,
/// played the harmonica in the second and wrote both; Joe Perry played the guitar in both and wrote the first; Jack
/// Douglas produced both, and Jay Messina mixed the second.
final serverCredits = {
  's1': [
    contributor('performer', 'ar3', 'Steven Tyler', subRole: 'lead vocals'),
    contributor('performer', 'ar4', 'Joe Perry', subRole: 'guitar'),
    contributor('composer', 'ar3', 'Steven Tyler'),
    contributor('composer', 'ar4', 'Joe Perry'),
    contributor('producer', 'ar5', 'Jack Douglas'),
  ],
  's2': [
    contributor('performer', 'ar3', 'Steven Tyler', subRole: 'lead vocals'),
    contributor('performer', 'ar3', 'Steven Tyler', subRole: 'harmonica'),
    contributor('performer', 'ar4', 'Joe Perry', subRole: 'Guitar'),
    contributor('composer', 'ar3', 'Steven Tyler'),
    contributor('producer', 'ar5', 'Jack Douglas'),
    contributor('mixer', 'ar6', 'Jay Messina'),
  ],
};

/// A relation of MusicBrainz's of a recording, a work or a release to an artist, [name], whose MusicBrainz id is [id],
/// of [type], with [attributes].
Map<String, Object?> relation(String type, String id, String name, {List<String> attributes = const []}) => {
  'type': type,
  'target-type': 'artist',
  'direction': 'backward',
  'attributes': attributes,
  'artist': {'id': id, 'name': name},
};

/// A relation of a recording or a release to the place it was recorded at, [name], from [begin] to [end]; or mixed or
/// mastered at, by [type].
Map<String, Object?> recordedAt(String name, {String? begin, String? end, String type = 'recorded at'}) => {
  'type': type,
  'target-type': 'place',
  'begin': begin,
  'end': end,
  'place': {'id': name, 'name': name},
};

/// MusicBrainz, whose release `r1` is Toys in the Attic, with two tracks: on the first, Steven Tyler sang and Joe
/// Perry played the guitar, and both wrote it, at the Record Plant in January 1975, in the United Kingdom; on the
/// second, Steven Tyler sang, at the Record Plant in February, at Electric Lady Studios on the 1st of March, at Media
/// Sound in January, at Sound City from September 1974 to March 1975, and at a studio of no dates, and was mixed at
/// Electric Lady Studios in March. George Marino mastered the release, at Sterling Sound, of no dates; Pacific Eye & Ear
/// designed it and Bob Gruen took its photographs. Its credits come once [credits] has completed, where it's given.
MusicBrainz musicBrainzCredits({Future<void>? credits}) => MusicBrainz(
  spacing: Duration.zero,
  client: MockClient((request) async {
    if (request.url.queryParameters['inc']?.contains('recordings') ?? false) {
      await credits;
    }

    return http.Response(
      jsonEncode({
        'id': 'r1',
        'media': [
          {
            'tracks': [
              {
                'id': 't1',
                'recording': {
                  'id': 'rec1',
                  'relations': [
                    relation('vocal', 'mb1', 'Steven Tyler', attributes: ['lead vocals']),
                    relation('instrument', 'mb2', 'Joe Perry', attributes: ['guitar']),
                    recordedAt('The Record Plant', begin: '1975-01-20', end: '1975-01-25'),
                    {
                      'type': 'recorded in',
                      'target-type': 'area',
                      'area': {
                        'id': 'gb',
                        'name': 'United Kingdom',
                        'iso-3166-1-codes': ['GB'],
                      },
                    },
                    {
                      'type': 'performance',
                      'target-type': 'work',
                      'work': {
                        'id': 'w1',
                        'relations': [
                          relation('composer', 'mb1', 'Steven Tyler'),
                          relation('lyricist', 'mb2', 'Joe Perry'),
                        ],
                      },
                    },
                  ],
                },
              },
              {
                'id': 't2',
                'recording': {
                  'id': 'rec2',
                  'relations': [
                    relation('vocal', 'mb1', 'Steven Tyler', attributes: ['lead vocals']),
                    recordedAt('The Record Plant', begin: '1975-02-03', end: '1975-02-10'),
                    recordedAt('Electric Lady Studios', begin: '1975-03-01', end: '1975-03-01'),
                    recordedAt('Media Sound', begin: '1975-01-02', end: '1975-01-09'),
                    recordedAt('Sound City', begin: '1974-09', end: '1975-03'),
                    recordedAt('Studio X'),
                    recordedAt('Electric Lady Studios', begin: '1975-03-10', end: '1975-03-12', type: 'mixed at'),
                  ],
                },
              },
            ],
          },
        ],
        'relations': [
          relation('mastering', 'mb3', 'George Marino'),
          relation('design/illustration', 'mb4', 'Pacific Eye & Ear'),
          relation('photography', 'mb5', 'Bob Gruen'),
          recordedAt('Sterling Sound', type: 'mastered at'),
        ],
      }),
      200,
    );
  }),
);

/// The song titled [title] in the album's list.
Finder song(String title) => find.widgetWithText(ListTile, title);

/// The cover as asked of the server at [size] pixels.
Finder coverAt(int size) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      Uri.parse((widget.image as NetworkImage).url).queryParameters['size'] == '$size',
);

/// The image of the cover whose id is [id].
Finder coverOf(String id) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      Uri.parse((widget.image as NetworkImage).url).queryParameters['id'] == id,
);

/// The play button, with the room around it that a tap on a touch screen takes too.
final playButton = find.ancestor(of: find.byTooltip('Tocar o álbum'), matching: find.byType(IconButton));

/// Opens the album's page again over the one [pumpAlbum] opened, so it has a page to go back to, and the back arrow.
Future<void> pushAlbum(WidgetTester tester) async {
  unawaited(
    Navigator.of(tester.element(find.byType(AlbumPage))).push(
      MaterialPageRoute<void>(
        builder: (context) => const AlbumPage(Album(id: 'a1', name: 'Toys in the Attic')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openCover(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ver a capa'));
  await tester.pumpAndSettle();
  expect(find.byType(CoverPage), findsOneWidget);
}

void main() {
  testWidgets('on a phone, the songs go on behind the player bar, and the last one scrolls clear of it', (
    tester,
  ) async {
    await pumpAlbum(tester, more: 20, size: const Size(360, 640));
    await tester.tap(song('Walk This Way'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(CustomScrollView)).bottom, 640);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -100000));
    await tester.pumpAndSettle();
    expect(tester.getRect(song('Song 20')).bottom, lessThanOrEqualTo(tester.getRect(find.byType(NowPlayingBar)).top));
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timer
  });

  testWidgets(
    'a song\'s menu plays it next, or adds it to the queue, and says so; the album\'s button, all its songs',
    (tester) async {
      final engine = await pumpAlbum(tester);
      List<String?> queue() => [for (final i in engine.order) engine.tracks[i].queryParameters['id']];

      Future<void> pick(Finder menu, String item) async {
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(item).last);
        await tester.pumpAndSettle();
      }

      await tester.tap(song('Walk This Way'));
      await tester.pumpAndSettle();
      await pick(find.descendant(of: song('Sweet Emotion'), matching: find.byTooltip('Mais opções')), 'Tocar a seguir');
      expect(queue(), ['s1', 's2', 's2']);
      expect(find.text('Vai tocar a seguir'), findsOneWidget);

      await pick(find.byTooltip('Adicionar'), 'Adicionar à fila');
      expect(queue(), ['s1', 's2', 's2', 's1', 's2']);
      expect(engine.index, 0, reason: 'the song that played plays on');
      await tester.pump(const Duration(seconds: 5)); // the message before goes
      await tester.pumpAndSettle();
      expect(find.text('2 faixas adicionadas à fila'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

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

  testWidgets('the play button is just its icon, its name in the tooltip, and plays the album from its first song', (
    tester,
  ) async {
    final engine = await pumpAlbum(tester);
    final play = find.byTooltip('Tocar o álbum');
    expect(find.descendant(of: play, matching: find.byType(Text)), findsNothing);
    expect(find.text('Tocar'), findsNothing);
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(engine.tracks, hasLength(2));
    expect(engine.index, 0);
    expect(engine.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('under each song, its artist, a link to their page that doesn\'t play the song', (tester) async {
    final engine = await pumpAlbum(tester);
    final artist = find.descendant(of: song('Walk This Way'), matching: find.text('Aerosmith'));
    expect(artist, findsOneWidget, reason: 'also when they are the album\'s artist');
    await tester.tap(artist);
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.descendant(of: find.byType(ArtistPage), matching: find.text('Aerosmith')).first, findsOneWidget);
    expect(engine.tracks, isEmpty, reason: 'the song didn\'t play');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the button that adds the album to the queue or a playlist comes before the play button, whose edge is '
    '16 from the screen\'s, also on a touch screen, whose buttons have room around them',
    variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.linux}),
    (tester) async {
      await pumpAlbum(tester, size: const Size(360, 640));
      final add = tester.getRect(find.byTooltip('Adicionar'));
      final play = tester.getRect(find.byTooltip('Tocar o álbum'));
      expect(play.right, 360 - 16);
      expect(play.left, greaterThan(add.right), reason: 'after it, apart');
      await tester.pumpWidget(const SizedBox());
    },
  );

  /// The album, with a song by Run-DMC and Aerosmith after its own, on a screen of [size].
  Future<FakeEngine> pumpDuet(WidgetTester tester, {Size size = const Size(1000, 700)}) => pumpAlbum(
    tester,
    others: [
      {
        'id': 's3',
        'title': 'Walk This Way (Run-DMC)',
        'artist': 'Run-DMC; Aerosmith',
        'artistId': 'ar2',
        'artists': [
          {'id': 'ar2', 'name': 'Run-DMC'},
          {'id': 'ar1', 'name': 'Aerosmith'},
        ],
        'duration': 311,
      },
    ],
    size: size,
  );

  testWidgets('a song by several artists links each of them', (tester) async {
    await pumpDuet(tester);
    final duet = song('Walk This Way (Run-DMC)');
    expect(find.descendant(of: duet, matching: find.byTooltip('Abrir o artista')), findsNWidgets(2));
    expect(find.descendant(of: duet, matching: find.text(' · ')), findsOneWidget);
    final runDmc = find.descendant(of: duet, matching: find.text('Run-DMC'));
    await tester.ensureVisible(runDmc);
    await tester.pumpAndSettle();
    await tester.tap(runDmc);
    await tester.pumpAndSettle();
    expect(tester.widget<ArtistPage>(find.byType(ArtistPage)).artist.id, 'ar2');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, a song\'s artists are plain text, which a tap on plays the song: only the player links them',
    (tester) async {
      final engine = await pumpDuet(tester, size: const Size(360, 640));
      final duet = song('Walk This Way (Run-DMC)');
      expect(find.descendant(of: duet, matching: find.byTooltip('Abrir o artista')), findsNothing);
      final artists = find.descendant(of: duet, matching: find.text('Run-DMC · Aerosmith'));
      await tester.ensureVisible(artists);
      await tester.pumpAndSettle();
      await tester.tap(artists);
      await tester.pumpAndSettle();
      expect(find.byType(ArtistPage), findsNothing);
      expect(engine.tracks, hasLength(3));
      expect(engine.index, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'under the album\'s name, its artist, with their picture, then its year, its songs and how long they last',
    (tester) async {
      await pumpAlbum(tester);
      final byline = find.textContaining(' · 1975 · 2 faixas, 8 min');
      expect(byline, findsOneWidget);
      final artist = find.descendant(of: byline, matching: find.text('Aerosmith'));
      final picture = find.descendant(of: byline, matching: coverOf('ar-ar1'));
      expect(tester.getSize(picture), const Size(24, 24));
      expect(tester.getRect(picture).right, lessThan(tester.getRect(artist).left));
      expect(tester.getCenter(picture).dy, moreOrLessEquals(tester.getCenter(artist).dy, epsilon: 1));
      await tester.tap(picture);
      await tester.pumpAndSettle();
      expect(find.byType(ArtistPage), findsOneWidget, reason: 'the picture is part of the link');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('an album of an hour or more says how long in hours and minutes', (tester) async {
    await pumpAlbum(tester, more: 20); // 494 seconds, and 20 songs of 200
    expect(find.textContaining(' · 1975 · 22 faixas, 1 h 14 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('over the songs, a header names their columns, lined up with them: #, the title, the duration', (
    tester,
  ) async {
    await pumpAlbum(tester);
    final first = song('Walk This Way');
    expect(
      tester.getRect(find.text('#')).left,
      tester.getRect(find.descendant(of: first, matching: find.text('1'))).left,
    );
    expect(tester.getRect(find.text('#')).left, 16, reason: 'at the start of the column, the page\'s margin');
    expect(
      tester.getRect(find.descendant(of: song('Sweet Emotion'), matching: find.text('2'))).left,
      16,
      reason: 'each number',
    );
    expect(tester.getRect(find.text('Título')).left, tester.getRect(find.text('Walk This Way')).left);
    expect(
      tester.getRect(find.text('Walk This Way')).left,
      16 + SongListHeader.numberWidth + SongListHeader.numberGap,
      reason: 'the room after the number, narrower than Material\'s',
    );
    expect(
      tester.getRect(find.byTooltip('Duração')).right,
      moreOrLessEquals(tester.getRect(find.text('3:40')).right, epsilon: 1),
    );
    expect(tester.getRect(find.text('Título')).bottom, lessThan(tester.getRect(first).top));
    expect(Focus.maybeOf(tester.element(find.text('Título')))?.canRequestFocus ?? false, isFalse, reason: 'no stop');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('each song\'s menu ends its line, after its duration, the durations ending together, a longer one too', (
    tester,
  ) async {
    await pumpAlbum(
      tester,
      others: [
        {'id': 's9', 'title': 'Long Song', 'artist': 'Aerosmith', 'duration': 625},
      ],
    );

    Rect menu(String title) =>
        tester.getRect(find.descendant(of: song(title), matching: find.byTooltip('Mais opções')));

    expect(menu('Walk This Way').left, greaterThan(tester.getRect(find.text('3:40')).right));
    expect(menu('Long Song').left, greaterThan(tester.getRect(find.text('10:25')).right));
    expect(tester.getRect(find.text('10:25')).right, tester.getRect(find.text('3:40')).right);
    expect(menu('Long Song').left, menu('Walk This Way').left);
    // Its icon, 8 inside it, as far from the line's end as the number is from its start.
    expect(menu('Walk This Way').right - 8, tester.getRect(song('Walk This Way')).right - 16);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, no header over the songs, which keep their numbers', (tester) async {
    await pumpAlbum(tester, size: const Size(360, 640));
    expect(find.text('Título'), findsNothing);
    expect(find.byTooltip('Duração'), findsNothing);
    expect(find.descendant(of: song('Walk This Way'), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: song('Walk This Way'), matching: find.text('3:40')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the album\'s name is in a bar with the back arrow, centered, which stays as the page scrolls '
    'under it and the system\'s, taking the page\'s color, and the cover is under them',
    (tester) async {
      await pumpAlbum(tester, more: 20, size: const Size(360, 640));
      tester.view.padding = const FakeViewPadding(top: 24);
      final opened = Navigator.of(tester.element(find.byType(AlbumPage))).push(
        MaterialPageRoute<void>(
          builder: (context) => const AlbumPage(Album(id: 'a1', name: 'Toys in the Attic')),
        ),
      );
      await tester.pumpAndSettle();
      final page = find.byType(AlbumPage).last;
      final title = find.descendant(of: find.byType(AppBar), matching: find.text('Toys in the Attic'));
      final (arrow, name) = (tester.getRect(find.byType(BackButton)), tester.getRect(title));
      final cover = tester.getRect(find.byTooltip('Ver a capa'));
      expect(
        find.descendant(of: page, matching: find.text('Toys in the Attic')),
        findsOneWidget,
        reason: 'there alone',
      );
      expect(arrow.center.dy, 24 + kToolbarHeight / 2, reason: 'under the system\'s bar');
      expect(name.center.dy, moreOrLessEquals(arrow.center.dy, epsilon: 1), reason: 'on the arrow\'s line');
      expect(name.center.dx, moreOrLessEquals(180, epsilon: 1), reason: 'centered on the page');
      expect(name.left, greaterThanOrEqualTo(arrow.right));
      expect(cover.top, 24 + kToolbarHeight + 8, reason: 'under them');
      final list = find.descendant(of: page, matching: find.byType(CustomScrollView));
      expect(tester.getRect(list).top, 0, reason: 'the page goes on under the bars, to the top of the screen');
      // Clear at the top of the page, more of the page's color as the cover goes up under the bar, all of it once half
      // the cover has.
      final appBar = find.descendant(of: page, matching: find.byType(AppBar));
      Color bar() => tester.widget<Material>(find.descendant(of: appBar, matching: find.byType(Material)).first).color!;
      expect(bar().a, 0);

      await tester.drag(list, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(bar().a, inExclusiveRange(0, 1), reason: 'some of it');

      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byTooltip('Ver a capa')).top, lessThan(0), reason: 'the cover gone up under the bars');
      expect(bar().a, 1, reason: 'all of it');
      expect((tester.getRect(find.byType(BackButton)), tester.getRect(title)), (arrow, name), reason: 'the bar stays');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await opened;
      expect(find.byType(BackButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a wide screen, the album\'s name and byline are beside its cover, the play button under them', (
    tester,
  ) async {
    await pumpAlbum(tester);
    final cover = tester.getRect(find.byTooltip('Ver a capa'));
    final name = tester.getRect(find.text('Toys in the Attic'));
    final byline = tester.getRect(find.textContaining(' · 1975 · 2 faixas, 8 min'));
    final play = tester.getRect(playButton);
    expect(name.left, greaterThan(cover.right));
    expect(play.bottom, lessThanOrEqualTo(cover.bottom), reason: 'all beside it');
    expect((byline.left, play.left), (name.left, name.left));
    expect(play.top, greaterThan(byline.bottom));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the byline is under the cover, from the page\'s margin, the play button at the end of its line',
    (tester) async {
      await pumpAlbum(tester, size: const Size(360, 640));
      await pushAlbum(tester);
      final cover = tester.getRect(find.byTooltip('Ver a capa'));
      // The artist with their picture, which the songs' have not.
      final artist = tester.getRect(find.ancestor(of: coverOf('ar-ar1'), matching: find.byTooltip('Abrir o artista')));
      final details = tester.getRect(find.text('1975 · 2 faixas'));
      // Its round edge, without the room Material leaves around it on a touch screen.
      final play = tester.getRect(find.byTooltip('Tocar o álbum'));
      expect(artist.top, greaterThanOrEqualTo(cover.bottom));
      expect(details.top, greaterThanOrEqualTo(artist.bottom), reason: 'the year and the songs under the artist');
      expect((artist.left, details.left), (16, 16), reason: 'from the page\'s margin, not the cover\'s');
      expect(cover.left, greaterThan(16));
      expect(play.right, 360 - 16);

      for (final text in [artist, details]) {
        expect(play.left, greaterThanOrEqualTo(text.right));
      }

      expect(play.center.dy, moreOrLessEquals((artist.top + details.bottom) / 2, epsilon: 1));
      expect(play.bottom, lessThan(tester.getRect(song('Walk This Way')).top));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a phone, how long the album\'s songs last ends the list, between its release date and its labels: '
      'the line under the artist, with how many they are, has no room for it', (tester) async {
    await pumpAlbum(
      tester,
      releaseDate: {'year': 1975, 'month': 4, 'day': 8},
      recordLabels: ['Columbia'],
      size: const Size(360, 640),
    );
    final (date, length, labels) = (
      tester.getRect(find.text('8 de abril de 1975')),
      tester.getRect(find.text('8 min')),
      tester.getRect(find.text('Columbia')),
    );
    expect(date.top, greaterThan(tester.getRect(song('Sweet Emotion')).bottom));
    expect(length.top, greaterThanOrEqualTo(date.bottom));
    expect(labels.top, greaterThanOrEqualTo(length.bottom));
    expect((length.left, labels.left), (date.left, date.left));
    expect(find.text('1975 · 2 faixas'), findsOneWidget, reason: 'the year and the songs under the artist');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the cover is centered, as wide as the page less its margins, up to 280', (tester) async {
    for (final (width, side) in [(300.0, 300.0 - 2 * 16), (360.0, 280.0)]) {
      await pumpAlbum(tester, size: Size(width, 800));
      await pushAlbum(tester);
      final cover = find.byTooltip('Ver a capa');
      expect(tester.getSize(cover), Size.square(side), reason: '$width');
      expect(tester.getCenter(cover).dx, width / 2, reason: '$width');
      expect(
        find.descendant(of: cover, matching: coverAt(800)),
        findsOneWidget,
        reason: 'asked of the server as the player\'s, for a phone\'s pixels',
      );
      expect(
        find.descendant(of: cover, matching: coverAt(300)),
        findsOneWidget,
        reason: 'under it, as it comes',
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('on a wide screen, once the cover has gone up, the album\'s name stays in a bar at the top of the page, '
      'after the play button, coming in with the page\'s color; nothing there until then, where the cover takes taps', (
    tester,
  ) async {
    final engine = await pumpAlbum(tester, more: 20);
    final list = find.byType(CustomScrollView);
    final position = tester
        .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)))
        .position;
    Finder inBar(Finder finder) => find.descendant(of: find.byType(PageBarSliver), matching: finder);
    double shown() => tester.widget<Opacity>(inBar(find.byType(Opacity))).opacity;
    expect(inBar(find.byType(Opacity)), findsNothing, reason: 'nothing while the cover shows');
    expect(find.byTooltip('Ver a capa').hitTestable(at: Alignment.topCenter), findsOneWidget, reason: 'to its top');

    position.jumpTo(150);
    await tester.pumpAndSettle();
    expect(shown(), inExclusiveRange(0, 1), reason: 'coming in as the cover goes up');

    position.jumpTo(300);
    await tester.pumpAndSettle();
    expect(shown(), 1, reason: 'the cover gone');
    final (page, bar) = (tester.getRect(list), tester.getRect(inBar(find.byType(Material)).first));
    expect(bar, Rect.fromLTWH(page.left, page.top, page.width, kToolbarHeight + 1), reason: 'at the top, a line under');
    final play = tester.getRect(inBar(find.byTooltip('Tocar o álbum')));
    final name = tester.getRect(inBar(find.text('Toys in the Attic')));
    expect(name.left, greaterThan(play.right), reason: 'after the play button');
    expect(name.center.dy, moreOrLessEquals(page.top + kToolbarHeight / 2, epsilon: 1));
    expect(play.center.dy, moreOrLessEquals(page.top + kToolbarHeight / 2, epsilon: 1));

    await tester.tap(inBar(find.byTooltip('Tocar o álbum')));
    await tester.pumpAndSettle();
    expect(engine.tracks, hasLength(22), reason: 'the album, from its first song');
    expect(engine.index, 0);

    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(inBar(find.byType(Opacity)), findsNothing, reason: 'gone with the cover back');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a window widened with the page scrolled a little shows no bar yet, where a phone\'s had some color', (
    tester,
  ) async {
    await pumpAlbum(tester, more: 20, size: const Size(360, 640));
    final list = find.byType(CustomScrollView);
    tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable))).position.jumpTo(100);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(PageBarSliver), matching: find.byType(Opacity)), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a wide screen, as the keyboard or a remote goes up the songs, the one it comes to is clear of the bar',
    (tester) async {
      await pumpAlbum(tester, more: 20);

      for (
        var i = 0;
        i < 10 && FocusManager.instance.primaryFocus?.rect != tester.getRect(song('Walk This Way'));
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }

      for (var i = 0; i < 21; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }

      final bar = find.descendant(of: find.byType(PageBarSliver), matching: find.byType(Material)).first;
      expect(bar, findsOneWidget, reason: 'down at the last song');

      for (var i = 20; i > 0; i--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus!.rect;
        expect(focused, tester.getRect(song(i == 1 ? 'Sweet Emotion' : 'Song ${i - 1}')));

        if (bar.evaluate().isNotEmpty) {
          expect(focused.top, greaterThanOrEqualTo(tester.getRect(bar).bottom), reason: 'under the bar, at song $i');
        }
      }

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a wide screen, the cover is 220, asked of the server as the phone\'s', (tester) async {
    await pumpAlbum(tester);
    final cover = find.byTooltip('Ver a capa');
    expect(tester.getSize(cover), const Size.square(220));
    expect(find.descendant(of: cover, matching: coverAt(800)), findsOneWidget);
    expect(
      find.descendant(of: cover, matching: coverAt(300)),
      findsOneWidget,
      reason: 'under it, as it comes',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song\'s number and duration are as big as the artist\'s line beside them, in its title\'s color', (
    tester,
  ) async {
    await pumpAlbum(tester);
    TextStyle? style(Finder text) => tester.renderObject<RenderParagraph>(text).text.style;
    Finder inSong(String title, String text) => find.descendant(of: song(title), matching: find.text(text));
    final (number, duration) = (inSong('Walk This Way', '1'), inSong('Walk This Way', '3:40'));
    final artist = inSong('Walk This Way', 'Aerosmith');

    for (final (column, text) in [('number', number), ('duration', duration)]) {
      expect(style(text)?.fontSize, style(artist)?.fontSize, reason: column);
      expect(style(text)?.fontSize, greaterThan(11), reason: '$column, bigger than a list tile\'s own');
    }

    await tester.tap(find.text('Walk This Way'));
    await tester.pump();
    await tester.pump(kThemeChangeDuration); // the tile's colors change in this
    expect(
      style(duration)?.color,
      style(inSong('Walk This Way', 'Walk This Way'))?.color,
      reason: 'the song that plays',
    );
    final (otherNumber, otherDuration) = (inSong('Sweet Emotion', '2'), inSong('Sweet Emotion', '4:34'));
    expect(style(duration)?.color, isNot(style(otherDuration)?.color), reason: 'unlike the song that doesn\'t play');
    expect(style(otherNumber)?.color, style(otherDuration)?.color, reason: 'its number, as its duration');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only the artist\'s name is a link: the rest of its line, under the mouse, is the song\'s', (
    tester,
  ) async {
    final engine = await pumpAlbum(tester);
    final artist = find.descendant(of: song('Walk This Way'), matching: find.text('Aerosmith'));
    TextDecoration? decoration() => tester.widget<Text>(artist).style?.decoration;
    // On the artist's line, halfway along the song: well past their name.
    final besideName = Offset(tester.getCenter(song('Walk This Way')).dx, tester.getCenter(artist).dy);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(besideName);
    await tester.pump();
    expect(decoration(), isNot(TextDecoration.underline));
    await mouse.down(besideName);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsNothing);
    expect(engine.tracks, isNotEmpty, reason: 'the song played');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after the last song, the album\'s release date and its record labels, lined up with its cover', (
    tester,
  ) async {
    await pumpAlbum(tester, releaseDate: {'year': 1975, 'month': 4, 'day': 8}, recordLabels: ['Columbia', 'Sony']);
    final (date, labels) = (find.text('8 de abril de 1975'), find.text('Columbia, Sony'));
    expect(tester.getRect(date).top, greaterThan(tester.getRect(song('Sweet Emotion')).bottom));
    expect(tester.getRect(labels).top, greaterThanOrEqualTo(tester.getRect(date).bottom));
    expect(tester.getRect(date).left, tester.getRect(find.byTooltip('Ver a capa')).left);
    expect(tester.getRect(labels).left, tester.getRect(date).left);

    for (final text in [date, labels]) {
      expect(Focus.maybeOf(tester.element(text))?.canRequestFocus ?? false, isFalse, reason: 'no stop');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, the album\'s type is above its name, lined up with it', (tester) async {
    await pumpAlbum(tester, releaseTypes: ['EP']);
    final (type, name) = (tester.getRect(find.text('EP')), tester.getRect(find.text('Toys in the Attic')));
    expect(type.bottom, lessThanOrEqualTo(name.top));
    expect(type.left, name.left);
    expect(find.textContaining('EP ·'), findsNothing, reason: 'not in the byline too');
    expect(find.byTooltip('Tocar o EP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the album\'s type is before its year, under the artist', (tester) async {
    await pumpAlbum(tester, releaseTypes: ['EP'], size: const Size(360, 640));
    expect(find.text('EP · 1975 · 2 faixas'), findsOneWidget);
    expect(find.text('EP'), findsNothing, reason: 'not above the name too');
    expect(find.byTooltip('Tocar o EP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('each type has its name, which the play button says too; an album the server says nothing of has none', (
    tester,
  ) async {
    for (final (types, name, play) in [
      (['album'], 'Álbum', 'Tocar o álbum'),
      (['single'], 'Single', 'Tocar o single'),
      (['album', 'compilation'], 'Coletânea', 'Tocar a coletânea'),
    ]) {
      await pumpAlbum(tester, releaseTypes: types);
      expect(find.text(name), findsOneWidget, reason: '$types');
      expect(find.byTooltip(play), findsOneWidget, reason: '$types');
      await tester.pumpWidget(const SizedBox());
    }

    await pumpAlbum(tester);
    expect(find.text('Álbum'), findsNothing, reason: 'not an album where it doesn\'t say');
    expect(find.byTooltip('Tocar o álbum'), findsOneWidget, reason: 'but its play button says album');
    expect(find.text('Toys in the Attic'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('where the server says no release date or type, MusicBrainz\'s, as they come', (tester) async {
    final brainz = MusicBrainz(
      spacing: Duration.zero,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'release-groups': [
              {
                'title': 'Toys in the Attic',
                'first-release-date': '1975-04-08',
                'primary-type': 'EP',
                'artist-credit': [
                  {'name': 'Aerosmith', 'joinphrase': ''},
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );
    await pumpAlbum(tester, musicBrainz: brainz);
    expect(find.text('8 de abril de 1975'), findsOneWidget);
    expect(find.text('EP'), findsOneWidget);
    expect(find.byTooltip('Tocar o EP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the release date as precisely as the server knows it', (tester) async {
    for (final (date, text) in [
      ({'year': 1975, 'month': 4, 'day': 1}, '1º de abril de 1975'),
      ({'year': 1975, 'month': 4}, 'abril de 1975'),
      ({'year': 1975}, '1975'),
    ]) {
      await pumpAlbum(tester, releaseDate: date);
      expect(find.text(text), findsOneWidget, reason: '$date');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('as the keyboard or a remote comes to the last song, the list scrolls on to the labels', (tester) async {
    await pumpAlbum(tester, more: 20, recordLabels: ['Columbia']);

    for (var i = 0; i < 10 && FocusManager.instance.primaryFocus?.rect != tester.getRect(song('Walk This Way')); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    for (var i = 0; i < 21; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }

    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(song('Song 20')));
    expect(
      tester.getRect(find.text('Columbia')).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(CustomScrollView)).bottom),
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
    testWidgets('on $screen, a button at the end of the album\'s byline opens its credits over the window, under its '
        'cover: who performed it, wrote it and produced it, one a line, what they did beside them; an album without '
        'any has no button', (tester) async {
      final narrow = size.width < 600;
      await pumpAlbum(tester, contributors: serverCredits, size: size);
      final button = find.byTooltip('Ver os créditos');
      final details = narrow ? find.text('1975 · 2 faixas') : find.textContaining('2 faixas, 8 min');

      if (narrow) {
        // At the end of the line under the artist.
        expect(tester.getCenter(button).dy, moreOrLessEquals(tester.getCenter(details).dy, epsilon: 1));
        expect(tester.getCenter(button).dx, greaterThan(tester.getRect(details).right));
      } else {
        // At the end of the byline, beside the cover.
        expect(tester.getRect(details).contains(tester.getCenter(button)), isTrue);
        expect(tester.getCenter(button).dx, greaterThan(tester.getCenter(details).dx));
      }

      await tester.tap(button);
      await tester.pumpAndSettle();
      final page = find.byType(CreditsPage);
      expect(page, findsOneWidget);
      Finder inPage(String text) => find.descendant(of: page, matching: find.text(text));
      expect(tester.widget<LargeCover>(find.descendant(of: page, matching: find.byType(LargeCover))).id, 'al-a1');
      expect(inPage('Toys in the Attic'), findsOneWidget);
      expect(inPage('Aerosmith · 1975'), findsOneWidget);
      final titles = [
        for (final title in ['Intérpretes', 'Composição', 'Produção']) tester.getRect(inPage(title)),
      ];
      expect(titles[0].bottom, lessThan(titles[1].top));
      expect(titles[1].bottom, lessThan(titles[2].top));
      expect(inPage('Gravação'), findsNothing, reason: 'only MusicBrainz says where');
      expect(inPage('Com dados do MusicBrainz'), findsNothing);

      // Each one a line, what they did beside them (wrapping, in the tests' wide letters), lined up; those on most
      // songs first.
      final lines = [
        (inPage('Steven Tyler').first, inPage('voz principal, gaita (faixa 2)')),
        (inPage('Joe Perry').first, inPage('guitarra')),
        (inPage('Steven Tyler').last, inPage('música')),
        (inPage('Joe Perry').last, inPage('música (faixa 1)')),
        (inPage('Jack Douglas'), inPage('produção')),
        (inPage('Jay Messina'), inPage('mixagem (faixa 2)')),
      ];

      for (final (name, did) in lines) {
        expect(tester.getTopLeft(did).dx, tester.getTopLeft(lines.first.$2).dx);
        expect(tester.getTopLeft(did).dx, greaterThan(tester.getTopRight(name).dx));
        expect(tester.getTopLeft(did).dy, tester.getTopLeft(name).dy);
      }

      expect(tester.getTopLeft(lines[1].$1).dy, greaterThan(tester.getBottomLeft(lines[0].$1).dy));
      expect(tester.getTopLeft(lines[2].$1).dy, greaterThan(titles[1].bottom));
      expect(tester.getTopLeft(lines[4].$1).dy, greaterThan(titles[2].bottom));

      if (narrow) {
        await tester.tap(find.descendant(of: page, matching: find.byTooltip('Fechar')));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }

      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(song('Walk This Way'), findsOneWidget, reason: 'back on the album\'s page');

      await tester.pumpWidget(const SizedBox());
      await pumpAlbum(tester, size: size);
      expect(find.byTooltip('Ver os créditos'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the names of the library\'s artists among those credited are links to their pages, which close the '
      'credits', (tester) async {
    await pumpAlbum(tester, contributors: serverCredits);
    await tester.tap(find.byTooltip('Ver os créditos'));
    await tester.pumpAndSettle();
    final page = find.byType(CreditsPage);
    expect(find.descendant(of: page, matching: find.widgetWithText(TextLink, 'Steven Tyler')), findsNWidgets(2));
    expect(find.descendant(of: page, matching: find.widgetWithText(TextLink, 'Joe Perry')), findsNothing);

    await tester.tap(find.widgetWithText(TextLink, 'Steven Tyler').first);
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.byType(ArtistPage), findsOneWidget);
    expect(tester.widget<ArtistPage>(find.byType(ArtistPage)).artist.id, 'ar3');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'where the server credits no one, MusicBrainz does, by the album\'s MusicBrainz id: the button comes with '
    'its credits, and where the album was recorded, mixed and mastered, and when, then who made its cover; the page '
    'says MusicBrainz said so',
    (tester) async {
      final credits = Completer<void>();
      await pumpAlbum(
        tester,
        musicBrainzId: 'r1',
        musicBrainz: musicBrainzCredits(credits: credits.future),
      );
      expect(find.byTooltip('Ver os créditos'), findsNothing);
      credits.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ver os créditos'));
      await tester.pumpAndSettle();

      final page = find.byType(CreditsPage);
      Finder inPage(String text) => find.descendant(of: page, matching: find.text(text));
      // What is beside the name, on its line.
      String detail(String name, [int index = 0]) {
        final line = tester.getTopLeft(inPage(name).at(index)).dy;

        return [
          for (final element in find.descendant(of: page, matching: find.byType(Text)).evaluate())
            if ((element.widget as Text).data case final text? when text != name)
              if (tester.getTopLeft(find.byElementPredicate((found) => found == element)).dy == line) text,
        ].join(' | ');
      }

      expect(detail('Steven Tyler'), 'voz principal');
      expect(detail('Joe Perry'), 'guitarra (faixa 1)');
      expect(detail('Steven Tyler', 1), 'música (faixa 1)');
      expect(detail('Joe Perry', 1), 'letra (faixa 1)');
      expect(detail('George Marino'), 'masterização');
      expect(inPage('Gravação'), findsOneWidget);
      expect(detail('The Record Plant'), 'janeiro – fevereiro de 1975');
      expect(detail('Reino Unido'), 'faixa 1');
      expect(detail('Electric Lady Studios'), '1º de março de 1975 (faixa 2)');
      expect(detail('Media Sound'), 'janeiro de 1975 (faixa 2)');
      expect(detail('Sound City'), 'setembro de 1974 – março de 1975 (faixa 2)');
      expect(detail('Studio X'), 'faixa 2');
      // Where it was mixed and mastered after where it was recorded, saying so; then who made its cover.
      expect(detail('Electric Lady Studios', 1), 'mixagem, março de 1975 (faixa 2)');
      expect(detail('Sterling Sound'), 'masterização');
      expect(detail('Pacific Eye & Ear'), 'projeto gráfico');
      expect(detail('Bob Gruen'), 'fotografia');
      final lines = [
        for (final (name, index) in [
          ('Produção', 0),
          ('Gravação', 0),
          ('The Record Plant', 0),
          ('Reino Unido', 0),
          ('Electric Lady Studios', 0),
          ('Studio X', 0),
          ('Electric Lady Studios', 1),
          ('Sterling Sound', 0),
          ('Arte', 0),
          ('Pacific Eye & Ear', 0),
        ])
          tester.getTopLeft(inPage(name).at(index)).dy,
      ];
      expect(
        lines,
        orderedEquals([...lines]..sort()),
        reason:
            'after who produced it, where it was recorded, in the order of its songs, then mixed, then mastered; '
            'then who made its cover',
      );
      expect(inPage('Com dados do MusicBrainz'), findsOneWidget);
      expect(
        find.descendant(of: page, matching: find.widgetWithText(TextLink, 'Steven Tyler')),
        findsNWidgets(2),
        reason: 'in the library by their MusicBrainz id',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('MusicBrainz\'s credits fill the sections the server has none in, as they come, also on the page open', (
    tester,
  ) async {
    final credits = Completer<void>();
    await pumpAlbum(
      tester,
      contributors: {
        's2': [contributor('composer', 'ar6', 'Brad Whitford')],
      },
      musicBrainzId: 'r1',
      musicBrainz: musicBrainzCredits(credits: credits.future),
    );
    await tester.tap(find.byTooltip('Ver os créditos'));
    await tester.pumpAndSettle();
    final page = find.byType(CreditsPage);
    Finder inPage(String text) => find.descendant(of: page, matching: find.text(text));
    expect(inPage('Composição'), findsOneWidget);
    expect(inPage('Intérpretes'), findsNothing);
    expect(inPage('Gravação'), findsNothing);

    credits.complete();
    await tester.pumpAndSettle();
    expect(inPage('Intérpretes'), findsOneWidget);
    expect(inPage('Gravação'), findsOneWidget);
    expect(inPage('música (faixa 2)'), findsOneWidget, reason: 'the server\'s writers');
    expect(inPage('letra (faixa 1)'), findsNothing, reason: 'not MusicBrainz\'s');
    expect(inPage('Com dados do MusicBrainz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  /// One of Aerosmith's albums, [name], whose id is [id], from [year], of [releaseTypes].
  Map<String, Object?> aerosmithAlbum(String id, String name, int year, {List<String>? releaseTypes}) => {
    'id': id,
    'name': name,
    'artist': 'Aerosmith',
    'artistId': 'ar1',
    'year': year,
    'releaseTypes': ?releaseTypes,
  };

  testWidgets('after the songs and the release, a row of the artist\'s other albums under "Mais de" and their name, '
      'which opens their page: their albums, newest first, then their singles and EPs, as their page has them, each '
      'with its year and its type where it isn\'t an album; with no other, no row', (tester) async {
    await pumpAlbum(
      tester,
      recordLabels: ['Columbia'],
      moreByArtist: [
        aerosmithAlbum('a2', 'Dream On', 1973, releaseTypes: ['EP']),
        aerosmithAlbum('a3', 'Get Your Wings', 1974),
        aerosmithAlbum('a4', 'Pump', 1989),
        aerosmithAlbum('a5', 'Rocks', 1976, releaseTypes: ['album']),
      ],
      size: const Size(1000, 1000),
    );
    final title = find.text('Mais de Aerosmith');
    expect(tester.getRect(title).top, greaterThan(tester.getRect(find.text('Columbia')).bottom));
    final row = find.ancestor(of: title, matching: find.byType(TileRow));
    final names = [
      for (final tile in find.descendant(of: row, matching: find.byType(AlbumTile)).evaluate())
        (tile.widget as AlbumTile).album.name,
    ];
    expect(names, ['Pump', 'Rocks', 'Get Your Wings', 'Dream On'], reason: 'not this one');
    Finder inTile(String name, String text) =>
        find.descendant(of: find.widgetWithText(AlbumTile, name), matching: find.text(text));
    expect(inTile('Pump', '1989'), findsOneWidget);
    expect(inTile('Rocks', '1976'), findsOneWidget);
    expect(inTile('Dream On', '1973 · EP'), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Aerosmith')),
      findsNothing,
      reason: 'the title says whose',
    );

    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(tester.widget<ArtistPage>(find.byType(ArtistPage)).artist.id, 'ar1');
    await tester.pumpWidget(const SizedBox());

    await pumpAlbum(tester, size: const Size(1000, 1000));
    expect(title, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song\'s artist takes no focus: for the keyboard and a remote, each song is one stop', (tester) async {
    await pumpAlbum(tester);

    for (var i = 0; i < 10 && FocusManager.instance.primaryFocus?.rect != tester.getRect(song('Walk This Way')); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(song('Walk This Way')));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(song('Sweet Emotion')));
    await tester.pumpWidget(const SizedBox());
  });
}
