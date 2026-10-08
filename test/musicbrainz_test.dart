import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/releases/musicbrainz.dart';
import 'package:segue/server/models.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A release group of MusicBrainz's, of the primary type [type], credited to [credit]: names, each with what joins it
/// to the next.
Map<String, Object?> group({
  String title = 'Toys in the Attic',
  String date = '1975-04-08',
  String type = 'Album',
  List<(String, String)> credit = const [('Aerosmith', '')],
}) => {
  'id': 'rg1',
  'title': title,
  'first-release-date': date,
  'primary-type': type,
  'secondary-types': <String>[],
  'artist-credit': [
    for (final (name, join) in credit) {'name': name, 'joinphrase': join},
  ],
};

/// MusicBrainz, answering a release's lookup with [release] (null: none), a search of release groups with [groups], an
/// artist's lookup with [artist] (null: none) and an area's with [areas]' by its id (none for another); [asked] gets
/// every request.
MusicBrainz musicBrainz({
  Map<String, Object?>? release,
  List<Map<String, Object?>> groups = const [],
  Map<String, Object?>? artist,
  Map<String, Map<String, Object?>> areas = const {},
  List<http.Request>? asked,
  Duration spacing = Duration.zero,
  bool remembersCountries = false,
}) => MusicBrainz(
  spacing: spacing,
  remembersCountries: remembersCountries,
  client: MockClient((request) async {
    asked?.add(request);
    return switch (request.url.pathSegments) {
      [..., 'release', _] when release != null => json(release),
      [..., 'artist', _] when artist != null => json(artist),
      [..., 'area', final id] when areas.containsKey(id) => json(areas[id]!),
      [..., 'release-group'] => json({'release-groups': groups}),
      _ => json({'error': 'Not Found'}, 404),
    };
  }),
);

/// Toys in the Attic, by Aerosmith, of 1975, as the media server gives it.
Album album({
  String name = 'Toys in the Attic',
  String artist = 'Aerosmith',
  int? year = 1975,
  ReleaseDate? releaseDate,
  List<String> recordLabels = const [],
  String? musicBrainzId,
  ReleaseType? releaseType,
}) => Album(
  id: 'a1',
  name: name,
  artist: artist,
  year: year,
  releaseDate: releaseDate,
  recordLabels: recordLabels,
  musicBrainzId: musicBrainzId,
  releaseType: releaseType,
);

(int?, int?, int?) parts(ReleaseDate? date) => (date?.year, date?.month, date?.day);

/// An artist of MusicBrainz's, of [type], with the life span of [begin], [end] and [ended].
Map<String, Object?> lifeSpan({String type = 'Group', String? begin, String? end, bool ended = false}) => {
  'id': 'mb1',
  'name': 'Os Mutantes',
  'type': type,
  'life-span': {'begin': begin, 'end': end, 'ended': ended},
};

/// A relation of a band's to one of its members, [name], whose MusicBrainz id is [id] (and sort name [sortName]), from
/// [begin] to [end], in which they played [attributes]: as MusicBrainz gives it, one for each time and instrument.
Map<String, Object?> membership(
  String id,
  String name, {
  String? sortName,
  String? begin,
  String? end,
  bool? ended,
  List<String> attributes = const [],
  String type = 'member of band',
  String direction = 'backward',
}) => {
  'type': type,
  'direction': direction,
  'begin': begin,
  'end': end,
  'ended': ended ?? end != null,
  'attributes': attributes,
  'artist': {'id': id, 'name': name, 'sort-name': sortName ?? name, 'type': 'Person'},
};

/// An area of MusicBrainz's, [name], whose id is [id], with its [codes] (ISO 3166-1's for a country, 3166-2's for a
/// subdivision), part of [partOf] (none: of none), as a lookup of it with its relations gives it. A relation's area has
/// its codes too.
Map<String, Object?> area(String id, String name, {List<String>? codes, Map<String, Object?>? partOf}) => {
  'id': id,
  'name': name,
  if (codes case final codes? when codes.first.contains('-')) 'iso-3166-2-codes': codes,
  if (codes case final codes? when !codes.first.contains('-')) 'iso-3166-1-codes': codes,
  'relations': [
    if (partOf != null) {'type': 'part of', 'direction': 'backward', 'area': partOf},
  ],
};

/// Boston's areas: Boston, part of Suffolk County, which doesn't say its country, part of Massachusetts, which does.
final boston = {
  'boston': area('boston', 'Boston', partOf: area('suffolk', 'Suffolk County')),
  'suffolk': area('suffolk', 'Suffolk County', partOf: area('ma', 'Massachusetts', codes: ['US-MA'])),
};

/// Os Mutantes, as the media server gives them, with their MusicBrainz id.
const mutantes = Artist(id: 'ar1', name: 'Os Mutantes', musicBrainzId: 'mb1');

/// A release of Toys in the Attic: a reissue of 2012, under Columbia (twice, for two catalog numbers), with a catalog
/// number of no label and MusicBrainz's "[no label]".
const reissue = {
  'id': 'r1',
  'date': '2012-11-02',
  'label-info': [
    {
      'catalog-number': '1',
      'label': {'name': 'Columbia'},
    },
    {
      'catalog-number': '2',
      'label': {'name': 'Columbia'},
    },
    {'catalog-number': '3', 'label': null},
    {
      'catalog-number': null,
      'label': {'name': '[no label]'},
    },
  ],
  'release-group': {
    'id': 'rg1',
    'first-release-date': '1975-04-08',
    'primary-type': 'Album',
    'secondary-types': <String>[],
  },
};

void main() {
  test('by the album\'s MusicBrainz id, its release\'s date and labels, asked as an app MusicBrainz knows', () async {
    final asked = <http.Request>[];
    final found = await musicBrainz(release: reissue, asked: asked).complete(album(musicBrainzId: 'r1'));
    expect(parts(found.date), (2012, 11, 2), reason: 'the edition\'s');
    expect(found.labels, ['Columbia']);
    expect(found.type, ReleaseType.album, reason: 'its release group\'s');
    final url = asked.single.url;
    expect(url.path, '/ws/2/release/r1');
    expect(url.queryParameters, {'inc': 'labels release-groups', 'fmt': 'json'});
    expect(asked.single.headers['User-Agent'], startsWith('Segue/'));
  });

  test('a date of only a year takes a fuller one of that year: the edition\'s, else the first', () async {
    final brainz = musicBrainz(release: reissue);
    final first = await brainz.complete(album(releaseDate: const ReleaseDate(1975), musicBrainzId: 'r1'));
    expect(parts(first.date), (1975, 4, 8));
    final other = await brainz.complete(album(releaseDate: const ReleaseDate(1980), musicBrainzId: 'r1'));
    expect(parts(other.date), (1980, null, null), reason: 'none of its year');
    final month = await brainz.complete(album(releaseDate: const ReleaseDate(1975, month: 5), musicBrainzId: 'r1'));
    expect(parts(month.date), (1975, 5, null), reason: 'none of its month');
  });

  test('what the media server says stays, and MusicBrainz isn\'t asked for what it says already', () async {
    final asked = <http.Request>[];
    final brainz = musicBrainz(release: reissue, asked: asked);
    const full = ReleaseDate(1975, month: 4, day: 8);
    const ep = ReleaseType.ep;
    final kept = await brainz.complete(
      album(releaseDate: full, recordLabels: ['Sony'], musicBrainzId: 'r1', releaseType: ep),
    );
    expect(parts(kept.date), (1975, 4, 8));
    expect(kept.labels, ['Sony']);
    expect(kept.type, ep);
    await brainz.complete(album(releaseDate: full, releaseType: ep));
    expect(asked, isEmpty, reason: 'without a MusicBrainz id, it would look for a date and a type only');
    final dated = await brainz.complete(
      album(releaseDate: const ReleaseDate(1975), recordLabels: ['Sony'], musicBrainzId: 'r1', releaseType: ep),
    );
    expect(parts(dated.date), (1975, 4, 8), reason: 'a fuller date');
    expect(dated.labels, ['Sony'], reason: 'its own labels');
    expect(dated.type, ep, reason: 'its own type');
    final typed = await brainz.complete(album(releaseDate: full, recordLabels: ['Sony'], musicBrainzId: 'r1'));
    expect(typed.type, ReleaseType.album, reason: 'a type where it has none');
  });

  test('without a MusicBrainz id, the date of the release group its name, artist and year match; no labels', () async {
    final asked = <http.Request>[];
    final found = await musicBrainz(
      groups: [
        group(title: 'Aerosmith / Get Your Wings / Toys in the Attic', date: '1998-06-30'),
        group(credit: [('Kau Tau', '')], date: '2013-02-26'),
        group(title: 'Toys In The Attic'),
      ],
      asked: asked,
    ).complete(album());
    expect(parts(found.date), (1975, 4, 8));
    expect(found.labels, isEmpty);
    expect(asked.single.url.path, '/ws/2/release-group');
    expect(asked.single.url.queryParameters['query'], 'releasegroup:"Toys in the Attic" AND artist:"Aerosmith"');
  });

  test('release groups of different dates, or none of the album\'s year, give no date', () async {
    // A MusicBrainz for each, as each asks once for an album.
    Future<(int?, int?, int?)> date(List<Map<String, Object?>> groups, int? year) async =>
        parts((await musicBrainz(groups: groups).complete(album(year: year))).date);

    expect(await date([group(), group(date: '1976')], null), (null, null, null));
    expect(await date([group(), group(date: '1976')], 1976), (1976, null, null), reason: 'the one of its year');
    expect(await date([group()], 1993), (null, null, null));
  });

  test('the type of its release group: a compilation over its primary one, which names the others', () async {
    Future<ReleaseType?> type(Map<String, Object?> releaseGroup) async =>
        (await musicBrainz(release: {...reissue, 'release-group': releaseGroup}).complete(album(musicBrainzId: 'r1')))
            .type;

    expect(await type({'primary-type': 'EP', 'secondary-types': <String>[]}), ReleaseType.ep);
    expect(await type({'primary-type': 'Single'}), ReleaseType.single);
    expect(
      await type({
        'primary-type': 'Album',
        'secondary-types': ['Live', 'Compilation'],
      }),
      ReleaseType.compilation,
    );
    expect(await type({'primary-type': 'Broadcast'}), isNull, reason: 'none the page names');
    expect(await type({'primary-type': null}), isNull);
  });

  test('without a MusicBrainz id, the type of the release groups it matches, when they have one', () async {
    // A MusicBrainz for each, as each asks once for an album.
    Future<ReleaseType?> type(List<Map<String, Object?>> groups) async =>
        (await musicBrainz(groups: groups).complete(album())).type;

    expect(
      await type([group(type: 'EP'), group(type: 'EP', date: '1975'), group(title: 'Rocks')]),
      ReleaseType.ep,
      reason: 'of different dates, one type',
    );
    expect(await type([group(type: 'EP'), group(type: 'Single')]), isNull);
    expect(
      await type([group(type: 'EP', date: '1993')]),
      isNull,
      reason: 'none of its year',
    );
  });

  test('artists credited together match the album\'s, however their names are joined', () async {
    final found = await musicBrainz(
      groups: [
        group(title: 'Walk This Way', date: '1986-07-04', credit: [('Run‐DMC', ' & '), ('Aerosmith', '')]),
      ],
    ).complete(album(name: 'Walk This Way', artist: 'Run-DMC, Aerosmith', year: null));
    expect(parts(found.date), (1986, 7, 4));
  });

  test('a name with quotes stays one phrase in the search', () async {
    final asked = <http.Request>[];
    await musicBrainz(asked: asked).complete(album(name: r'The "Best" \ Rest'));
    expect(asked.single.url.queryParameters['query'], startsWith(r'releasegroup:"The \"Best\" \\ Rest" AND'));
  });

  test('a failure leaves the media server\'s, and asks again the next time; what it found, it asks no more', () async {
    var status = 500;
    final asked = <http.Request>[];
    final brainz = MusicBrainz(
      spacing: Duration.zero,
      client: MockClient((request) async {
        asked.add(request);
        return status == 200 ? json(reissue) : http.Response('', status);
      }),
    );
    final failed = await brainz.complete(album(releaseDate: const ReleaseDate(1975), musicBrainzId: 'r1'));
    expect(parts(failed.date), (1975, null, null));
    expect(failed.labels, isEmpty);
    status = 200;
    final found = await brainz.complete(album(releaseDate: const ReleaseDate(1975), musicBrainzId: 'r1'));
    expect(parts(found.date), (1975, 4, 8));
    expect(found.labels, ['Columbia']);
    await brainz.complete(album(releaseDate: const ReleaseDate(1975), musicBrainzId: 'r1'));
    expect(asked, hasLength(2));
  });

  test('a request refused for the rate, or as MusicBrainz is busy (503), goes once more, a second later', () {
    fakeAsync((async) {
      final statuses = [503, 503, 503, 200];
      final asked = <http.Request>[];
      final brainz = MusicBrainz(
        client: MockClient((request) async {
          asked.add(request);
          return statuses.removeAt(0) == 200 ? json(reissue) : http.Response('', 503);
        }),
      );
      AlbumRelease? first;
      brainz.complete(album(musicBrainzId: 'r1')).then((found) => first = found).ignore();
      async.flushMicrotasks();
      expect(asked, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(asked, hasLength(2), reason: 'once more');
      async.elapse(const Duration(seconds: 5));
      expect(asked, hasLength(2), reason: 'no more');
      expect(first?.labels, isEmpty);
      AlbumRelease? second;
      brainz.complete(album(musicBrainzId: 'r1')).then((found) => second = found).ignore();
      async.elapse(const Duration(seconds: 1));
      expect(asked, hasLength(4));
      expect(second?.labels, ['Columbia']);
    });
  });

  test(
    'a band\'s years, by the artist\'s MusicBrainz id: from the one it formed in to the one it broke up in',
    () async {
      final asked = <http.Request>[];
      final brainz = musicBrainz(
        artist: lifeSpan(begin: '1966-05', end: '1978', ended: true),
        asked: asked,
      );
      expect((await brainz.band(mutantes))?.years, (begin: 1966, end: 1978, ended: true));
      final url = asked.single.url;
      expect(url.path, '/ws/2/artist/mb1');
      expect(url.queryParameters, {'inc': 'artist-rels', 'fmt': 'json'}, reason: 'its members too');
      await brainz.band(mutantes);
      expect(asked, hasLength(1), reason: 'what it found, it asks no more');
    },
  );

  test('a band that hasn\'t broken up, or whose years MusicBrainz knows only one of', () async {
    for (final (span, years) in [
      (lifeSpan(begin: '1985'), (begin: 1985, end: null, ended: false)),
      (lifeSpan(end: '1978', ended: true), (begin: null, end: 1978, ended: true)),
      (lifeSpan(begin: '1966', ended: true), (begin: 1966, end: null, ended: true)),
      (lifeSpan(type: 'Orchestra', begin: '1842'), (begin: 1842, end: null, ended: false)),
      (lifeSpan(type: 'Choir', begin: '1498'), (begin: 1498, end: null, ended: false)),
    ]) {
      expect((await musicBrainz(artist: span).band(mutantes))?.years, years, reason: '$span');
    }
  });

  test(
    'no years of a person, whose are their life\'s, of a band of none, or of an artist without a MusicBrainz id',
    () async {
      final asked = <http.Request>[];

      for (final span in [
        lifeSpan(type: 'Person', begin: '1947', end: '2016', ended: true),
        lifeSpan(type: 'Character', begin: '1978'),
        lifeSpan(ended: true),
        {'id': 'mb1', 'name': 'Os Mutantes', 'type': null},
      ]) {
        expect(await musicBrainz(artist: span).band(mutantes), isNull, reason: '$span');
      }

      final brainz = musicBrainz(
        artist: lifeSpan(begin: '1966'),
        asked: asked,
      );
      expect(await brainz.band(const Artist(id: 'ar1', name: 'Os Mutantes')), isNull);
      expect(asked, isEmpty);
      expect(await musicBrainz().band(mutantes), isNull, reason: 'an id MusicBrainz no longer has');
    },
  );

  test('a group\'s members, from its relations: each once, with each time they have been in it, the first first, and '
      'whether they are in it now; in the order they came in, those who came together by name', () async {
    final band = await musicBrainz(
      artist: {
        ...lifeSpan(begin: '1970'),
        'relations': [
          membership('tabano', 'Ray Tabano', sortName: 'Tabano, Ray', begin: '1970-10', end: '1971-04'),
          membership('perry', 'Joe Perry', sortName: 'Perry, Joe', begin: '1970-10', end: '1979-07'),
          // One for each instrument, the same years.
          membership('hamilton', 'Tom Hamilton', sortName: 'Hamilton, Tom', begin: '1970-10', attributes: ['bass']),
          membership('hamilton', 'Tom Hamilton', sortName: 'Hamilton, Tom', begin: '1970-10', attributes: ['vocals']),
          membership('tyler', 'Steven Tyler', sortName: 'Tyler, Steven', begin: '1970-10'),
          membership('whitford', 'Brad Whitford', sortName: 'Whitford, Brad', begin: '1971-04', end: '1981-07'),
          membership('crespo', 'Jimmy Crespo', sortName: 'Crespo, Jimmy', begin: '1979-07', end: '1984-04'),
          // Who left and came back.
          membership('perry', 'Joe Perry', sortName: 'Perry, Joe', begin: '1984-04'),
          membership('whitford', 'Brad Whitford', sortName: 'Whitford, Brad', begin: '1984-04'),
          // Not members of it: a band it is a member of, and musicians who have played with it.
          membership('supergroup', 'A Supergroup', begin: '1990', direction: 'forward'),
          membership('session', 'Richie Supa', begin: '1974', type: 'instrumental supporting musician'),
        ],
      },
    ).band(mutantes);
    expect(band?.years, (begin: 1970, end: null, ended: false));
    // As lists: a record's list equals only itself.
    expect(
      [
        for (final member in band!.members) [member.id, member.name, member.current, member.years],
      ],
      [
        [
          'hamilton',
          'Tom Hamilton',
          true,
          [(begin: 1970, end: null, ended: false)],
        ],
        [
          'perry',
          'Joe Perry',
          true,
          [(begin: 1970, end: 1979, ended: true), (begin: 1984, end: null, ended: false)],
        ],
        [
          'tyler',
          'Steven Tyler',
          true,
          [(begin: 1970, end: null, ended: false)],
        ],
        // Of those who came in 1970, the one who left the next year last.
        [
          'tabano',
          'Ray Tabano',
          false,
          [(begin: 1970, end: 1971, ended: true)],
        ],
        [
          'whitford',
          'Brad Whitford',
          true,
          [(begin: 1971, end: 1981, ended: true), (begin: 1984, end: null, ended: false)],
        ],
        [
          'crespo',
          'Jimmy Crespo',
          false,
          [(begin: 1979, end: 1984, ended: true)],
        ],
      ],
    );
  });

  test('a band that has broken up: of its members who came in together, the one who stayed longest first; times that '
      'overlap, one; a member it knows no year of, last', () async {
    final band = await musicBrainz(
      artist: {
        ...lifeSpan(begin: '1960-03-27', end: '1970-04-10', ended: true),
        'relations': [
          membership('sutcliffe', 'Stuart Sutcliffe', begin: '1960-01', end: '1961'),
          membership('nobody', 'Someone', ended: true),
          membership('lennon', 'John Lennon', begin: '1960', end: '1969-09'),
          membership('mccartney', 'Paul McCartney', begin: '1960', end: '1965'),
          membership('mccartney', 'Paul McCartney', begin: '1963', end: '1970-04-10'),
          membership('starr', 'Ringo Starr', begin: '1962-08', end: '1970-04-10'),
          membership('moore', 'Tommy Moore', begin: '1960-05', end: '1960-06'),
        ],
      },
    ).band(mutantes);
    expect(band?.years, (begin: 1960, end: 1970, ended: true));
    expect(
      [
        for (final member in band!.members) [member.name, member.years],
      ],
      [
        [
          'Paul McCartney',
          [(begin: 1960, end: 1970, ended: true)],
        ],
        [
          'John Lennon',
          [(begin: 1960, end: 1969, ended: true)],
        ],
        [
          'Stuart Sutcliffe',
          [(begin: 1960, end: 1961, ended: true)],
        ],
        [
          'Tommy Moore',
          [(begin: 1960, end: 1960, ended: true)],
        ],
        [
          'Ringo Starr',
          [(begin: 1962, end: 1970, ended: true)],
        ],
        ['Someone', isEmpty],
      ],
    );
    expect(band.members.where((member) => member.current), isEmpty);
  });

  test('an orchestra\'s and a choir\'s years, but not their members, who would be a crowd; a group\'s members, with '
      'no years', () async {
    final relations = [membership('m1', 'Someone', begin: '1990')];

    for (final type in ['Orchestra', 'Choir']) {
      final band = await musicBrainz(
        artist: {
          ...lifeSpan(type: type, begin: '1882'),
          'relations': relations,
        },
      ).band(mutantes);
      expect(band?.years, (begin: 1882, end: null, ended: false), reason: type);
      expect(band?.members, isEmpty, reason: type);
    }

    final group = await musicBrainz(artist: {...lifeSpan(), 'relations': relations}).band(mutantes);
    expect(group?.years, isNull);
    expect([for (final member in group!.members) member.name], ['Someone']);
  });

  test('where an artist comes from: the place they formed or were born in, and, at once, the artist\'s country, which '
      'the place\'s turns out to be, by what it\'s part of, one area at a time; each asked once, the artist\'s with '
      'their years', () async {
    final asked = <http.Request>[];
    final brainz = musicBrainz(
      artist: {
        ...lifeSpan(begin: '1970'),
        'country': 'US',
        'begin-area': {'id': 'boston', 'name': 'Boston'},
      },
      areas: boston,
      asked: asked,
    );
    expect(await brainz.origin(mutantes).toList(), [(place: 'Boston', country: 'US')], reason: 'nothing to correct');
    expect(
      [for (final request in asked) request.url.path],
      ['/ws/2/artist/mb1', '/ws/2/area/boston', '/ws/2/area/suffolk'],
    );
    expect(asked[1].url.queryParameters, {'inc': 'area-rels', 'fmt': 'json'});

    expect((await brainz.band(mutantes))?.years, (begin: 1970, end: null, ended: false));
    expect(await brainz.origin(mutantes).toList(), [(place: 'Boston', country: 'US')]);
    expect(asked, hasLength(3), reason: 'what it found, it asks no more');
  });

  test('a person born abroad: their country at once, then the place\'s', () async {
    final brainz = musicBrainz(
      artist: {
        ...lifeSpan(type: 'Person', begin: '1952'),
        'country': 'US',
        'area': {
          'id': 'us',
          'name': 'United States',
          'iso-3166-1-codes': ['US'],
        },
        'begin-area': {'id': 'dumbarton', 'name': 'Dumbarton'},
      },
      areas: {
        'dumbarton': area('dumbarton', 'Dumbarton', partOf: area('sct', 'Scotland', codes: ['GB-SCT'])),
      },
    );
    expect(await brainz.origin(mutantes).toList(), [
      (place: 'Dumbarton', country: 'US'),
      (place: 'Dumbarton', country: 'GB'),
    ]);
  });

  test('the places\' countries found are kept for the next launches, the areas\' between too: then each comes at once, '
      'and right', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    Map<String, Object?> bornIn(String id, String name) => {
      ...lifeSpan(type: 'Person'),
      'country': 'GB',
      'begin-area': {'id': id, 'name': name},
    };
    final first = musicBrainz(artist: bornIn('boston', 'Boston'), areas: boston, remembersCountries: true);
    expect(await first.origin(mutantes).toList(), [(place: 'Boston', country: 'GB'), (place: 'Boston', country: 'US')]);

    final asked = <http.Request>[];
    final next = musicBrainz(artist: bornIn('boston', 'Boston'), areas: boston, asked: asked, remembersCountries: true);
    expect(await next.origin(mutantes).toList(), [(place: 'Boston', country: 'US')]);
    expect([for (final request in asked) request.url.path], ['/ws/2/artist/mb1']);

    // Another place in the county that one was in asks for itself alone.
    asked.clear();
    final another = musicBrainz(
      artist: bornIn('chelsea', 'Chelsea'),
      areas: {'chelsea': area('chelsea', 'Chelsea', partOf: area('suffolk', 'Suffolk County'))},
      asked: asked,
      remembersCountries: true,
    );
    expect(await another.origin(mutantes).toList(), [
      (place: 'Chelsea', country: 'GB'),
      (place: 'Chelsea', country: 'US'),
    ]);
    expect([for (final request in asked) request.url.path], ['/ws/2/artist/mb1', '/ws/2/area/chelsea']);
  });

  test('a place that is a country: that country alone; a state: with its own; no place: the artist\'s country, or '
      'their area\'s, alone; neither: nothing', () async {
    final asked = <http.Request>[];

    for (final (artist, origins) in <(Map<String, Object?>, List<Origin>)>[
      (
        {
          'country': 'US',
          'begin-area': {
            'id': 'gb',
            'name': 'United Kingdom',
            'iso-3166-1-codes': ['GB'],
          },
        },
        [(place: null, country: 'GB')],
      ),
      (
        {
          'begin-area': {
            'id': 'ca',
            'name': 'California',
            'iso-3166-2-codes': ['US-CA'],
          },
        },
        [(place: 'California', country: 'US')],
      ),
      ({'country': 'BR'}, [(place: null, country: 'BR')]),
      (
        {
          'area': {
            'id': 'su',
            'name': 'Soviet Union',
            'iso-3166-1-codes': ['SU'],
          },
        },
        [(place: null, country: 'SU')],
      ),
      (<String, Object?>{}, []),
    ]) {
      final found = await musicBrainz(artist: {...lifeSpan(), ...artist}, asked: asked).origin(mutantes).toList();
      expect(found, origins, reason: '$artist');
    }

    expect(asked.where((request) => request.url.path.contains('/area/')), isEmpty, reason: 'no area to look up');
    expect(await musicBrainz().origin(mutantes).toList(), isEmpty, reason: 'an id MusicBrainz no longer has');
    expect(await musicBrainz().origin(const Artist(id: 'ar1', name: 'Os Mutantes')).toList(), isEmpty);
  });

  test('a place whose country MusicBrainz doesn\'t say, or fails to: with the artist\'s, or alone; one that failed, '
      'asked again the next time', () async {
    Map<String, Object?> from(String? country) => {
      ...lifeSpan(),
      'country': ?country,
      'begin-area': {'id': 'somewhere', 'name': 'Somewhere'},
    };
    expect(await musicBrainz(artist: from('US')).origin(mutantes).toList(), [(place: 'Somewhere', country: 'US')]);
    expect(await musicBrainz(artist: from(null)).origin(mutantes).toList(), [(place: 'Somewhere', country: null)]);

    var status = 500;
    final asked = <http.Request>[];
    final brainz = MusicBrainz(
      spacing: Duration.zero,
      client: MockClient((request) async {
        asked.add(request);
        return switch (request.url.pathSegments.last) {
          'mb1' => json({
            ...lifeSpan(),
            'begin-area': {'id': 'boston', 'name': 'Boston'},
          }),
          _ when status != 200 => http.Response('', status),
          _ => json(area('boston', 'Boston', partOf: area('ma', 'Massachusetts', codes: ['US-MA']))),
        };
      }),
    );
    expect(await brainz.origin(mutantes).toList(), [(place: 'Boston', country: null)]);
    status = 200;
    expect(await brainz.origin(mutantes).toList(), [
      (place: 'Boston', country: null),
      (place: 'Boston', country: 'US'),
    ]);
    expect([for (final request in asked) request.url.pathSegments.last], ['mb1', 'boston', 'boston']);
  });

  test('a band\'s years that fail are none, and asked again the next time', () async {
    var status = 500;
    final asked = <http.Request>[];
    final brainz = MusicBrainz(
      spacing: Duration.zero,
      client: MockClient((request) async {
        asked.add(request);
        return status == 200 ? json(lifeSpan(begin: '1966')) : http.Response('', status);
      }),
    );
    expect(await brainz.band(mutantes), isNull);
    status = 200;
    expect((await brainz.band(mutantes))?.years, (begin: 1966, end: null, ended: false));
    expect(asked, hasLength(2));
  });

  test('requests go one at a time, a second apart, as MusicBrainz asks', () {
    fakeAsync((async) {
      final asked = <http.Request>[];
      final brainz = musicBrainz(release: reissue, asked: asked, spacing: const Duration(seconds: 1));
      brainz.complete(Album(id: 'a1', name: 'Toys in the Attic', musicBrainzId: 'r1')).ignore();
      brainz.complete(Album(id: 'a2', name: 'Rocks', musicBrainzId: 'r2')).ignore();
      async.flushMicrotasks();
      expect(asked, hasLength(1));
      async.elapse(const Duration(milliseconds: 999));
      expect(asked, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(asked, hasLength(2));
      expect(asked.last.url.path, '/ws/2/release/r2');
    });
  });
}
