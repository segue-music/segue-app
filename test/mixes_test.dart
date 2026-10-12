import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/mixes.dart';
import 'package:segue/pictures/fanart_tv.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/app/television_screen.dart';
import 'package:segue/ui/home/home_view.dart';
import 'package:segue/ui/home/mix_row.dart';
import 'package:segue/ui/widgets/cover.dart';

import 'fakes.dart';
import 'themed_icons.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The ids of the artists of the songs at random.
const artistIds = {
  'Aerosmith': 'r1',
  'Cheap Trick': 'r2',
  'Boston': 'r3',
  'Kiss': 'r4',
  'Heart': 'r5',
  'Journey': 'r6',
};

/// A song of the album whose id is [album], by [artist].
Map<String, Object?> song(String id, String album, String artist) => {
  'id': id,
  'title': 'Song $id',
  'artist': artist,
  'artistId': artistIds[artist],
  'albumId': album,
  'coverArt': 'al-$album',
};

/// A library whose most played albums (with [played]) are, the most first, one of rock of the 1970s, one of hard rock
/// of the 1980s, one of jazz of the 1950s and one of pop of the 1970s; and whose genres, with [genres], are rock, blues,
/// jazz, of a number of albums the server doesn't say, and spoken word, of none. Its songs at random, with [songs], are
/// six of five albums as a mix's first songs, and three, one of them among those, as its songs; the artists whose ids
/// are [pictured] have pictures, all of them by default, and each its MusicBrainz id, mb- and its own. [asked] gets the
/// queries of the songs asked for at random, and [askedArtists] the ids of the artists asked for.
http.Response server(
  http.Request request, {
  List<Map<String, String>>? asked,
  List<String>? askedArtists,
  bool played = true,
  bool genres = true,
  bool songs = true,
  Set<String>? pictured,
}) {
  final path = request.url.path;
  final query = request.url.queryParameters;

  if (path.endsWith('getAlbumList2.view')) {
    return subsonic({
      'albumList2': {
        'album': [
          if (query['type'] == 'frequent' && played) ...[
            {'id': 'a1', 'name': 'Toys in the Attic', 'genre': 'Rock', 'year': 1975, 'playCount': 20},
            {
              'id': 'a2',
              'name': 'Pump',
              'year': 1989,
              'playCount': 10,
              'genres': [
                {'name': 'hard rock'},
              ],
            },
            {'id': 'a3', 'name': 'Kind of Blue', 'genre': 'Jazz', 'year': 1959, 'playCount': 5},
            {'id': 'a4', 'name': 'Rumours', 'genre': 'Pop', 'year': 1977, 'playCount': 3},
          ],
        ],
      },
    });
  }

  if (path.endsWith('getGenres.view')) {
    return subsonic({
      'genres': {
        'genre': [
          if (genres) ...[
            {'value': 'Blues', 'albumCount': 1},
            {'value': 'Spoken', 'albumCount': 0},
            {'value': 'Jazz'},
            {'value': 'Rock', 'albumCount': 3},
          ],
        ],
      },
    });
  }

  if (path.endsWith('getArtist.view')) {
    final id = query['id']!;
    askedArtists?.add(id);
    return subsonic({
      'artist': {
        'id': id,
        'name': artistIds.entries.firstWhere((entry) => entry.value == id).key,
        'musicBrainzId': 'mb-$id',
        if (pictured?.contains(id) ?? true) 'coverArt': 'ar-$id',
      },
    });
  }

  if (path.endsWith('getRandomSongs.view')) {
    asked?.add(query);
    return subsonic({
      'randomSongs': {
        'song': [
          if (songs && query['size'] == '${SuggestedMixes.firstSize}') ...[
            song('s1', 'a1', 'Aerosmith'),
            song('s2', 'a1', 'Aerosmith'),
            song('s3', 'a2', 'Aerosmith'),
            song('s4', 'a5', 'Cheap Trick'),
            song('s5', 'a6', 'Boston'),
            song('s6', 'a7', 'Kiss'),
          ] else if (songs) ...[
            song('s5', 'a6', 'Boston'),
            song('s7', 'a8', 'Heart'),
            song('s8', 'a9', 'Journey'),
          ],
        ],
      },
    });
  }

  return http.Response('', 404);
}

SubsonicApi api({
  List<Map<String, String>>? asked,
  List<String>? askedArtists,
  bool played = true,
  bool genres = true,
  bool songs = true,
  Set<String>? pictured,
}) => SubsonicApi(
  Uri.parse('https://music.test'),
  credentials,
  client: MockClient(
    (request) async => server(
      request,
      asked: asked,
      askedArtists: askedArtists,
      played: played,
      genres: genres,
      songs: songs,
      pictured: pictured,
    ),
  ),
);

/// fanart.tv, with a picture of the artists whose ids are [pictured], by their MusicBrainz id; [asked] gets the ids.
FanartTv fanartTv(Set<String> pictured, {List<String>? asked}) => FanartTv(
  apiKey: 'key',
  client: MockClient((request) async {
    final id = request.url.pathSegments.last.replaceFirst('mb-', '');
    asked?.add(id);

    if (!pictured.contains(id)) {
      return http.Response('', 404);
    }

    return http.Response(
      jsonEncode({
        'artistthumb': [
          {'url': 'https://fanart.test/$id.jpg', 'likes': '3'},
        ],
      }),
      200,
    );
  }),
);

/// What [mixes] are of: a genre by its name, a decade by its first year.
List<Object> about(List<Mix> mixes) => [
  for (final mix in mixes)
    switch (mix) {
      GenreMix(:final genre) => genre.name,
      DecadeMix(:final decade) => decade,
    },
];

/// The home, over the library [server] has, with [played], [genres], [songs] and [pictured]; with [television], as on a
/// TV. Returns its player.
Future<PlayerController> pumpHome(
  WidgetTester tester, {
  List<Map<String, String>>? asked,
  bool played = true,
  bool genres = true,
  bool songs = true,
  Set<String>? pictured,
  bool television = false,
}) async {
  final server = api(asked: asked, played: played, genres: genres, songs: songs, pictured: pictured);
  final player = PlayerController(FakeEngine(), server);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    server,
    player,
    ConnectController(player: player),
  );
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(
        services: services,
        child: TelevisionScreen(enabled: television, child: child!),
      ),
      home: const Scaffold(body: HomeView()),
    ),
  );
  await tester.pumpAndSettle();

  return player;
}

/// The mix's tile that has [name].
Finder mixTile(String name) => find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;

/// Picks the mix that has [name], wherever in the row it came: past the screen's edge, the row scrolled to it.
Future<void> pick(WidgetTester tester, String name) async {
  final row = find.descendant(of: find.byType(MixRow), matching: find.byType(Scrollable));
  await tester.scrollUntilVisible(find.text(name), 100, scrollable: row);
  await tester.pumpAndSettle();
  await tester.tap(mixTile(name));
  await tester.pumpAndSettle();
}

GenreMix genre(List<Mix> mixes, String name) => mixes.whereType<GenreMix>().firstWhere((mix) => mix.genre.name == name);

/// A library whose most played albums are each of another genre, the first one the most played, and of another of
/// [decades] decades, from the 1950s: [genres] genres, the first albums of the first decades.
SubsonicApi manyGenres(int genres, int decades) => SubsonicApi(
  Uri.parse('https://music.test'),
  credentials,
  client: MockClient((request) async {
    if (!request.url.path.endsWith('getAlbumList2.view')) {
      return http.Response('', 404);
    }

    return subsonic({
      'albumList2': {
        'album': [
          for (var i = 0; i < max(genres, decades); i++)
            {
              'id': 'a$i',
              'name': 'Album $i',
              'genre': ?(i < genres ? 'Genre ${i + 1}' : null),
              'year': ?(i < decades ? 1950 + 10 * i : null),
              'playCount': 100 - i,
            },
        ],
      },
    });
  }),
);

void main() {
  test('the mixes are of the genres the user plays most, two, then of a decade they play most, and so on', () async {
    final mixes = about(await SuggestedMixes(api()).mixes);
    expect([for (final mix in mixes) mix is int], [false, false, true, false, false, true, true]);
    expect(mixes, unorderedEquals(['Rock', 'hard rock', 'Jazz', 'Pop', 1970, 1980, 1950]));
  });

  test('the mixes come in another order as the home loads again, the most played first more often', () async {
    final first = <Object, int>{};

    for (var seed = 0; seed < 200; seed++) {
      final mixes = about(await SuggestedMixes(api(), random: Random(seed)).mixes);
      first[mixes.first] = (first[mixes.first] ?? 0) + 1;
    }

    expect(first.keys, containsAll(['Rock', 'hard rock', 'Jazz', 'Pop']));
    expect(first['Rock'], greaterThan(first['hard rock']!));
    expect(first['hard rock'], greaterThan(first['Pop']!));
  });

  test('the mixes are 6 of the 12 genres the user plays most, and 3 of the 6 decades, another few each time, the most '
      'played more often', () async {
    final shown = <Object, int>{};

    for (var seed = 0; seed < 100; seed++) {
      final mixes = about(await SuggestedMixes(manyGenres(14, 8), random: Random(seed)).mixes);
      expect(mixes.whereType<String>(), hasLength(6));
      expect(mixes.whereType<int>(), hasLength(3));

      for (final mix in mixes) {
        shown[mix] = (shown[mix] ?? 0) + 1;
      }
    }

    expect(shown.keys, containsAll(['Genre 1', 'Genre 12', 1950, 2000]));
    expect(shown.keys, isNot(anyOf(contains('Genre 13'), contains('Genre 14'), contains(2010), contains(2020))));
    expect(shown['Genre 1'], greaterThan(shown['Genre 12']!));
    expect(shown[1950], greaterThan(shown[2000]!));
  });

  test('before anything has played, the mixes are of the genres with the most albums, but those of none', () async {
    expect(about(await SuggestedMixes(api(played: false)).mixes), unorderedEquals(['Rock', 'Blues', 'Jazz']));
  });

  test('a library without genres has no mixes', () async {
    expect(await SuggestedMixes(api(played: false, genres: false)).mixes, isEmpty);
  });

  test('a mix\'s first songs are asked for once, a few; a mix of a genre is of its songs, and of a decade of its '
      'years\'', () async {
    final asked = <Map<String, String>>[];
    final mixes = SuggestedMixes(api(asked: asked));
    final suggested = await mixes.mixes;
    final rock = genre(suggested, 'Rock');
    final seventies = suggested.whereType<DecadeMix>().firstWhere((mix) => mix.decade == 1970);
    final first = await mixes.firstSongs(rock);
    expect(identical(await mixes.firstSongs(rock), first), isTrue);
    expect(asked.single, allOf(containsPair('size', '12'), containsPair('genre', 'Rock')));

    await mixes.firstSongs(seventies);
    expect(asked.last, allOf(containsPair('fromYear', '1970'), containsPair('toYear', '1979')));
    expect(asked.last.containsKey('genre'), isFalse);

    await rock.songs(api(asked: asked));
    expect(asked.last, containsPair('size', '${Mix.size}'));
  });

  test(
    'a mix\'s picture is its first song\'s artist\'s, as the server has it, asked for once; none without songs',
    () async {
      final mixes = SuggestedMixes(api());
      final rock = genre(await mixes.mixes, 'Rock');
      final found = await mixes.picture(rock);
      expect(found?.artist.name, 'Aerosmith');
      expect(found?.artist.coverArt, 'ar-r1');
      expect(identical(await mixes.picture(rock), found), isTrue);

      final empty = SuggestedMixes(api(songs: false));
      expect(await empty.picture((await empty.mixes).first), isNull);
    },
  );

  test('where an artist has no picture, the next one\'s, in the order their songs play, each asked for once: the '
      'server\'s, or else fanart.tv\'s', () async {
    final askedArtists = <String>[];
    final askedFanart = <String>[];
    final mixes = SuggestedMixes(
      api(askedArtists: askedArtists, pictured: {'r3'}),
      fanartTv: fanartTv({'r4'}, asked: askedFanart),
    );
    var found = await mixes.picture(genre(await mixes.mixes, 'Rock'));
    expect(found?.artist.name, 'Boston');
    expect(found?.picture, isNull, reason: 'the server\'s');
    expect(askedArtists, ['r1', 'r2', 'r3'], reason: 'Aerosmith once, for its three songs');
    expect(askedFanart, ['r1', 'r2']);

    final fromFanart = SuggestedMixes(api(pictured: {}), fanartTv: fanartTv({'r2', 'r4'}));
    found = await fromFanart.picture(genre(await fromFanart.mixes, 'Rock'));
    expect(found?.artist.name, 'Cheap Trick');
    expect(found?.picture, Uri.parse('https://fanart.test/r2.jpg'));
  });

  test('where none of a mix\'s artists has a picture, none', () async {
    final askedArtists = <String>[];
    final mixes = SuggestedMixes(
      api(askedArtists: askedArtists, pictured: {}),
      fanartTv: fanartTv({}),
    );
    expect(await mixes.picture(genre(await mixes.mixes, 'Rock')), isNull);
    expect(askedArtists, ['r1', 'r2', 'r3', 'r4'], reason: 'every one');
  });

  test('a decade is called as it\'s usually said', () {
    final portuguese = lookupAppLocalizations(const Locale('pt'));
    final english = lookupAppLocalizations(const Locale('en'));
    final spanish = lookupAppLocalizations(const Locale('es'));
    expect(mixName(portuguese, const DecadeMix(1980)), 'Anos 80');
    expect(mixName(portuguese, const DecadeMix(2010)), 'Anos 2010');
    expect(mixName(portuguese, const DecadeMix(1910)), 'Anos 1910', reason: 'not the 2010s\'');
    expect(mixName(english, const DecadeMix(1980)), '1980s');
    expect(mixName(spanish, const DecadeMix(1980)), 'Años 80');
    expect(mixName(portuguese, const GenreMix(Genre(id: 'Rock', name: 'Rock'))), 'Rock');
  });

  testWidgets('the home starts with its mixes, each the picture of its first artist with its name over it, and under '
      'it the artists of its first songs', (tester) async {
    await pumpHome(tester);
    final mixes = tester.getRect(find.text('Mixes'));
    final rock = tester.getRect(find.text('Rock'));
    final hardRock = tester.getRect(find.text('hard rock'));
    expect(rock.top, greaterThan(mixes.bottom));
    // In whatever order, side by side: genres, which come before the last decade, where the screen shows them.
    expect(hardRock.bottom, rock.bottom, reason: 'at the bottom of their pictures');
    expect(tester.getRect(find.text('Lançamentos')).top, greaterThan(rock.bottom), reason: 'the albums\' rows after');

    final picture = find.descendant(of: mixTile('Rock'), matching: find.byType(Cover));
    expect(tester.widget<Cover>(picture).id, 'ar-r1', reason: 'Aerosmith\'s, the first song\'s artist');
    final over = tester.getRect(picture);
    expect(over.contains(rock.center), isTrue, reason: 'the name over the picture');
    expect(rock.bottom, greaterThan(over.center.dy), reason: 'at its bottom');

    final artists = find.descendant(of: mixTile('Rock'), matching: find.text('Aerosmith, Cheap Trick, Boston e mais'));
    expect(artists, findsOneWidget);
    expect(tester.getRect(artists).top, greaterThan(over.bottom));
  });

  testWidgets('a mix whose first artist has no picture shows the next one\'s', (tester) async {
    await pumpHome(tester, pictured: {'r2'});
    final picture = find.descendant(of: mixTile('Rock'), matching: find.byType(Cover));
    expect(tester.widget<Cover>(picture).id, 'ar-r2', reason: 'Cheap Trick\'s');
  });

  testWidgets('a mix none of whose artists has a picture shows its own: its kind\'s icon, on the theme\'s colors', (
    tester,
  ) async {
    await pumpHome(tester, pictured: {});
    expect(find.descendant(of: mixTile('Rock'), matching: find.byType(Cover)), findsNothing);
    final icon = find.descendant(of: mixTile('Rock'), matching: themedIcon(HugeIcons.strokeRoundedTag01));
    expect(icon, findsOneWidget);
    final tile = tester.getRect(find.descendant(of: mixTile('Rock'), matching: find.byType(ClipRRect)).first);
    expect(tester.getSize(icon).width, greaterThan(tile.width / 4), reason: 'big');
    final colors = Theme.of(tester.element(icon)).colorScheme;
    final art = tester.widget<DecoratedBox>(find.ancestor(of: icon, matching: find.byType(DecoratedBox)).first);
    expect((art.decoration as BoxDecoration).gradient?.colors, [colors.primaryContainer, colors.tertiaryContainer]);
  });

  testWidgets('a mix plays as it\'s picked: its first songs, which its tile shows, then the rest, each once', (
    tester,
  ) async {
    final asked = <Map<String, String>>[];
    final player = await pumpHome(tester, asked: asked);
    asked.clear();
    await pick(tester, 'Anos 70');
    expect([for (final song in player.queue) song.id], ['s1', 's2', 's3', 's4', 's5', 's6', 's7', 's8']);
    expect(player.playing, isTrue);
    expect(player.index, 0);
    expect(asked.single, allOf(containsPair('size', '100'), containsPair('fromYear', '1970')));
  });

  testWidgets('a mix with no songs says so, and plays nothing', (tester) async {
    final player = await pumpHome(tester, songs: false);
    await pick(tester, 'Rock');
    expect(find.text('Esse mix não tem músicas.'), findsOneWidget);
    expect(player.queue, isEmpty);
  });

  testWidgets(
    'on an iPhone, dragged past its end, the home bounces back to its end, rather than up to its first rows',
    (tester) async {
      await pumpHome(tester);
      // So short that, past the end, the mixes are far out of sight.
      tester.view.physicalSize = const Size(400, 300);
      await tester.pumpAndSettle();
      final home = find.descendant(of: find.byType(HomeView), matching: find.byType(Scrollable)).first;
      await tester.drag(home, const Offset(0, -900));
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(home).position;
      expect(position.pixels, position.maxScrollExtent);
      expect(tester.getRect(find.text('Adicionados recentemente')).top, lessThan(300), reason: 'the last row');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a library without genres has no row of mixes, nor its title', (tester) async {
    await pumpHome(tester, played: false, genres: false);
    expect(find.text('Mixes'), findsNothing);
    expect(tester.getRect(find.text('Lançamentos')).top, lessThan(100), reason: 'the first row');
  });
}
