import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/player/play_counter.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/subsonic/api.dart';

import 'fakes.dart';

const songs = [
  Song(id: 's1', title: 'One', duration: Duration(minutes: 3)),
  Song(id: 's2', title: 'Two', duration: Duration(minutes: 4)),
];

/// A player whose plays are counted on a server that keeps the query of each scrobble in [scrobbles].
PlayerController counted(List<Map<String, String>> scrobbles) {
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
    client: MockClient((request) async {
      if (request.url.path.endsWith('scrobble.view')) {
        scrobbles.add(request.url.queryParameters);
      }

      return http.Response(
        jsonEncode({
          'subsonic-response': {'status': 'ok'},
        }),
        200,
      );
    }),
  );
  final player = PlayerController(FakeEngine(), api);

  PlayCounter(player, api);

  return player;
}

void main() {
  test('a song\'s play counts once it has played half of it, its playing time added up across pauses', () {
    fakeAsync((async) {
      final scrobbles = <Map<String, String>>[];
      final player = counted(scrobbles);
      final start = clock.now();

      player.playQueue(songs); // One: 3 minutes
      async.elapse(const Duration(minutes: 1));
      player.pause();
      async.elapse(const Duration(minutes: 10));
      player.play();
      async.elapse(const Duration(seconds: 29));
      expect(scrobbles, isEmpty, reason: 'a minute and 29 seconds of it');

      async.elapse(const Duration(seconds: 1));
      expect(scrobbles, hasLength(1));
      expect(scrobbles.single, containsPair('id', 's1'));
      expect(scrobbles.single, containsPair('submission', 'true'));
      expect(scrobbles.single, containsPair('time', '${start.millisecondsSinceEpoch}'), reason: 'when it started');
    });
  });

  test('a long song\'s play counts after four minutes, and a seek forward plays nothing', () {
    fakeAsync((async) {
      final scrobbles = <Map<String, String>>[];
      final player = counted(scrobbles);

      player.playQueue([const Song(id: 'l1', title: 'Long', duration: Duration(minutes: 12))]);
      async.elapse(const Duration(minutes: 1));
      player.seek(const Duration(minutes: 7));
      async.elapse(const Duration(minutes: 2, seconds: 59));
      expect(scrobbles, isEmpty);

      async.elapse(const Duration(seconds: 1));
      expect(scrobbles.single, containsPair('id', 'l1'));
    });
  });

  test('a song of 30 seconds or less never counts, nor one skipped before half of it, and the next counts', () {
    fakeAsync((async) {
      final scrobbles = <Map<String, String>>[];
      final player = counted(scrobbles);

      player.playQueue([const Song(id: 'j1', title: 'Jingle', duration: Duration(seconds: 30)), ...songs]);
      async.elapse(const Duration(minutes: 1));
      player.next(); // One, 3 minutes
      async.elapse(const Duration(minutes: 1));
      player.next(); // Two, 4 minutes
      async.elapse(const Duration(minutes: 2));
      expect([for (final scrobble in scrobbles) scrobble['id']], ['s2']);
    });
  });

  test('a song counts again when it starts over, as repeated, but a pause is no new play', () {
    fakeAsync((async) {
      final scrobbles = <Map<String, String>>[];
      final player = counted(scrobbles);

      player.playQueue(songs);
      async.elapse(const Duration(minutes: 2));
      player.pause();
      player.play();
      async.elapse(const Duration(minutes: 2));
      expect(scrobbles, hasLength(1));

      player.jump(0); // the current track: it starts over
      async.elapse(const Duration(seconds: 90));
      expect([for (final scrobble in scrobbles) scrobble['id']], ['s1', 's1']);
    });
  });

  test('nothing counts while the player is paused, as the last playback opens, or stopped', () {
    fakeAsync((async) {
      final scrobbles = <Map<String, String>>[];
      final player = counted(scrobbles);

      player.playQueue(songs, position: const Duration(minutes: 1), play: false);
      async.elapse(const Duration(minutes: 10));
      player.play();
      async.elapse(const Duration(minutes: 1));
      player.stop();
      async.elapse(const Duration(minutes: 10));
      expect(scrobbles, isEmpty);
    });
  });
}
