import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/lyrics/lrclib.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A song of LRCLIB's.
Map<String, Object?> record({
  String title = 'Sweet Emotion',
  double duration = 274,
  String? synced,
  String? plain,
  bool instrumental = false,
}) => {
  'id': 1,
  'trackName': title,
  'artistName': 'Aerosmith',
  'albumName': 'Toys in the Attic',
  'duration': duration,
  'instrumental': instrumental,
  'plainLyrics': plain,
  'syncedLyrics': synced,
};

/// LRCLIB, answering /api/get with [get] (null: none) and /api/search with [search]; [asked] gets every
/// request.
Lrclib lrclib({Map<String, Object?>? get, List<Map<String, Object?>> search = const [], List<http.Request>? asked}) =>
    Lrclib(
      client: MockClient((request) async {
        asked?.add(request);

        return switch (request.url.path) {
          '/api/get' when get != null => json(get),
          '/api/get' => json({'code': 404, 'name': 'TrackNotFound'}, 404),
          '/api/search' => json(search),
          _ => http.Response('', 404),
        };
      }),
    );

Future<List<(Duration?, String)>?> lines(Lrclib lrclib) async {
  final lyrics = await lrclib.find(
    title: 'Sweet Emotion',
    artist: 'Aerosmith',
    album: 'Toys in the Attic',
    duration: const Duration(seconds: 274),
  );

  return lyrics == null ? null : [for (final line in lyrics.lines) (line.start, line.text)];
}

void main() {
  test('a song is LRCLIB\'s get, by its title, artist, album and length, as an app it knows', () async {
    final asked = <http.Request>[];
    final found = lrclib(
      get: record(synced: '[00:01.50] Sweet emotion\n[00:03.00]\n[01:02.25] Talk about things'),
      asked: asked,
    );

    expect(await lines(found), [
      (const Duration(milliseconds: 1500), 'Sweet emotion'),
      (const Duration(seconds: 3), ''),
      (const Duration(milliseconds: 62250), 'Talk about things'),
    ]);

    final get = asked.single;

    expect(get.url.host, 'lrclib.net');
    expect(get.url.queryParameters, {
      'track_name': 'Sweet Emotion',
      'artist_name': 'Aerosmith',
      'album_name': 'Toys in the Attic',
      'duration': '274',
    });
    expect(get.headers['user-agent'], startsWith('Segue '));
    expect(
      (await found.find(title: 'Sweet Emotion', artist: 'Aerosmith'))?.provider,
      'LRCLIB',
      reason: 'and says so',
    );
  });

  test('with no such song there, the first of that title by that artist that lasts as long', () async {
    final asked = <http.Request>[];
    final found = lrclib(
      search: [
        record(duration: 180, plain: 'Another one'),
        record(duration: 275.4, plain: 'Sweet emotion\nTalk about things'),
      ],
      asked: asked,
    );

    expect(await lines(found), [(null, 'Sweet emotion'), (null, 'Talk about things')], reason: 'not synced');
    expect(asked.last.url.path, '/api/search');
    expect(asked.last.url.queryParameters, {'track_name': 'Sweet Emotion', 'artist_name': 'Aerosmith'});
  });

  test('synced lyrics win: an exact match with plain ones only gives way to a song of the same title, lasting '
      'about as long, with synced ones', () async {
    // As LRCLIB has some songs twice: from the album, with plain lyrics, and from a single, a few seconds
    // longer, with synced ones.
    final found = lrclib(
      get: record(plain: 'Plain'),
      search: [
        record(plain: 'Plain'),
        record(title: 'Sweet Emotion (Live)', synced: '[00:01.00] Live'),
        record(duration: 277, synced: '[00:01.00] Synced'),
      ],
    );

    expect(await lines(found), [(const Duration(seconds: 1), 'Synced')]);
  });

  test('plain lyrics when no synced ones are near enough', () async {
    final found = lrclib(
      get: record(plain: 'Plain'),
      search: [
        record(duration: 290, synced: '[00:01.00] Another version'),
        record(title: 'Sweet Emotion (Live)', synced: '[00:01.00] Live'),
      ],
    );

    expect(await lines(found), [(null, 'Plain')]);
  });

  test('none found is none; an instrumental, a part with no singing', () async {
    expect(await lines(lrclib(search: [record(duration: 100, plain: 'Too short')])), isNull);
    expect(await lines(lrclib(get: record(instrumental: true))), [(Duration.zero, '')]);
  });

  test('a server that fails says so', () async {
    final failing = Lrclib(client: MockClient((_) async => http.Response('', 500)));

    await expectLater(failing.find(title: 'Sweet Emotion', artist: 'Aerosmith'), throwsA(anything));
  });

  test('LRC: a line at several times comes at each, and the offset shifts them all, sooner', () {
    final lines = parseLrc('[ar:Aerosmith]\n[offset:+500]\n[00:10.00][00:20.00] Chorus\n[00:15.00] Verse\nNo time');

    expect(
      [for (final line in lines) (line.start, line.text)],
      [
        (const Duration(milliseconds: 9500), 'Chorus'),
        (const Duration(milliseconds: 14500), 'Verse'),
        (const Duration(milliseconds: 19500), 'Chorus'),
      ],
    );
  });
}
