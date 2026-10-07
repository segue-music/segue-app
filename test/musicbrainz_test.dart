import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/releases/musicbrainz.dart';
import 'package:segue/server/models.dart';

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

/// MusicBrainz, answering a release's lookup with [release] (null: none) and a search of release groups with [groups];
/// [asked] gets every request.
MusicBrainz musicBrainz({
  Map<String, Object?>? release,
  List<Map<String, Object?>> groups = const [],
  List<http.Request>? asked,
  Duration spacing = Duration.zero,
}) => MusicBrainz(
  spacing: spacing,
  client: MockClient((request) async {
    asked?.add(request);
    return switch (request.url.pathSegments) {
      [..., 'release', _] when release != null => json(release),
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
