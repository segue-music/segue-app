import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/player/player.dart';
import 'package:segue/player/sleep_timer.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/server/models.dart';
import 'package:segue/subsonic/api.dart';

import 'fakes.dart';

const songs = [
  Song(id: 's1', title: 'Dream On', duration: Duration(minutes: 4)),
  Song(id: 's2', title: 'Sweet Emotion', duration: Duration(minutes: 5)),
];

/// This device's player, on [engine], playing [songs] from the first, and its sleep timer.
(PlayerController, SleepTimer) playing(FakeEngine engine) {
  final player = PlayerController(
    engine,
    SubsonicApi(Uri.parse('https://music.test'), const SubsonicCredentials(username: 'a', token: 't', salt: 's')),
  );
  player.playQueue(songs);
  return (player, SleepTimer(player));
}

void main() {
  test('after a while the music pauses, having faded out over the last 30 seconds, and plays as loud as before', () {
    fakeAsync((async) {
      final (player, timer) = playing(FakeEngine());
      timer.start(const Duration(minutes: 5));
      expect(timer.on, isTrue);
      expect(timer.minutesLeft, 5);

      async.elapse(const Duration(minutes: 4, seconds: 29));
      expect(player.playing, isTrue);
      expect(player.volume, 100, reason: 'not yet fading');
      expect(timer.minutesLeft, 1);

      async.elapse(const Duration(seconds: 16));
      expect(player.volume, inInclusiveRange(45, 55), reason: 'halfway through the fade');

      async.elapse(const Duration(seconds: 13));
      expect(player.volume, lessThan(10));
      expect(player.playing, isTrue);

      async.elapse(const Duration(seconds: 2));
      expect(player.playing, isFalse);
      expect(player.volume, 100, reason: 'for when it plays again');
      expect(timer.on, isFalse);
      expect(timer.minutesLeft, isNull);
    });
  });

  test('it tells its listeners as each minute goes, and as it ends', () {
    fakeAsync((async) {
      final (_, timer) = playing(FakeEngine());
      final told = <int?>[];
      timer.addListener(() => told.add(timer.minutesLeft));
      timer.start(const Duration(minutes: 3));
      async.elapse(const Duration(minutes: 3, seconds: 1));
      expect(told, [3, 2, 1, null]);
    });
  });

  test('a volume picked as the music fades stays, and it fades no more', () {
    fakeAsync((async) {
      final (player, timer) = playing(FakeEngine());
      timer.start(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 40));
      expect(player.volume, lessThan(100));

      player.setVolume(70);
      async.elapse(const Duration(seconds: 10));
      expect(player.volume, 70);

      async.elapse(const Duration(seconds: 11));
      expect(player.playing, isFalse);
      expect(player.volume, 70);
    });
  });

  test('turned off as the music fades, it plays on as loud as before', () {
    fakeAsync((async) {
      final (player, timer) = playing(FakeEngine());
      timer.start(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 45));
      expect(player.volume, lessThan(100));

      timer.cancel();
      async.flushMicrotasks();
      expect(player.volume, 100);
      expect(timer.on, isFalse);

      async.elapse(const Duration(minutes: 1));
      expect(player.playing, isTrue);
    });
  });

  test('another while takes the place of the one before, as loud as before', () {
    fakeAsync((async) {
      final (player, timer) = playing(FakeEngine());
      timer.start(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 45));
      timer.start(const Duration(minutes: 15));
      async.flushMicrotasks();
      expect(player.volume, 100);
      expect(timer.minutesLeft, 15);

      async.elapse(const Duration(minutes: 14));
      expect(player.playing, isTrue);
      async.elapse(const Duration(minutes: 1, seconds: 1));
      expect(player.playing, isFalse);
    });
  });

  test('at the song\'s end, the next one pauses at its start, from where play goes on', () {
    fakeAsync((async) {
      final engine = FakeEngine();
      final (player, timer) = playing(engine);
      timer.startUntilSongEnds();
      expect(timer.untilSongEnds, isTrue);
      expect(timer.minutesLeft, isNull);

      player.jump(0); // started over as picked, not ended
      async.elapse(const Duration(seconds: 30));
      expect(player.playing, isTrue);
      expect(timer.on, isTrue);

      engine.endTrack();
      async.flushMicrotasks();
      expect(player.playing, isFalse);
      expect(player.current?.title, 'Sweet Emotion', reason: 'the next one');
      expect(player.position, Duration.zero);
      expect(timer.on, isFalse);
    });
  });

  test('at the song\'s end, repeating it, it pauses as it starts over', () {
    fakeAsync((async) {
      final engine = FakeEngine();
      final (player, timer) = playing(engine);
      player.setRepeat(Repeat.one);
      timer.startUntilSongEnds();
      async.elapse(const Duration(minutes: 4));
      engine.endTrack();
      async.flushMicrotasks();
      expect(player.playing, isFalse);
      expect(player.current?.title, 'Dream On');
      expect(timer.on, isFalse);
    });
  });

  test('the queue\'s last song ending, the timer ends with it', () {
    fakeAsync((async) {
      final engine = FakeEngine();
      final (player, timer) = playing(engine);
      player.next();
      timer.startUntilSongEnds();
      engine.endTrack();
      async.flushMicrotasks();
      expect(player.playing, isFalse);
      expect(timer.on, isFalse);
    });
  });

  test('the player stopped, as another device takes the music, the timer goes off', () {
    fakeAsync((async) {
      final (player, timer) = playing(FakeEngine());
      timer.start(const Duration(minutes: 30));
      player.stop();
      async.flushMicrotasks();
      expect(timer.on, isFalse);
    });
  });
}
