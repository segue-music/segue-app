import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/player/crossfade_engine.dart';
import 'package:segue/player/engine.dart';
import 'package:segue/segue/protocol.dart';

import 'fakes.dart';

/// A track [seconds] long, as the media server says, or of a length it doesn't say.
TrackSource track(int n, {int? seconds = 60}) =>
    TrackSource(Uri.parse('https://music.test/$n'), duration: seconds == null ? null : Duration(seconds: seconds));

/// The engine, crossfading for 6 s, on [decks].
CrossfadeEngine crossfading(List<FakeEngine> decks) =>
    CrossfadeEngine(() => const Duration(seconds: 6), decks: decks, random: Random(1));

void main() {
  test('as a track nears its end the next one opens on the other deck, paused and silent, and then fades in as the one '
      'before fades out, at equal power, the next one current from its start', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);
      final tracks = [track(0), track(1), track(2)];
      final ended = <int>[];

      engine.ended.listen((_) => ended.add(engine.index));
      unawaited(engine.open(tracks, index: 0, position: Duration.zero, play: true));
      async.flushMicrotasks();
      expect(decks[0].opened, [tracks[0]]);
      expect(engine.playing, isTrue);

      async.elapse(const Duration(seconds: 43));
      expect(decks[1].opened, isEmpty, reason: '17 s left');

      async.elapse(const Duration(seconds: 2));
      expect(decks[1].opened, [tracks[1]], reason: '10 s before the crossfade');
      expect(decks[1].playing, isFalse);
      expect(decks[1].level, 0);
      expect(engine.index, 0);

      async.elapse(const Duration(seconds: 9));
      expect(engine.index, 1, reason: '6 s left');
      expect(ended, [1]);
      expect(decks[1].playing, isTrue);
      expect(decks[0].playing, isTrue);
      expect(engine.position, lessThan(const Duration(milliseconds: 100)));

      async.elapse(const Duration(seconds: 3));
      expect(decks[1].level, closeTo(sin(pi / 4), 0.01), reason: 'halfway');
      expect(decks[0].level, closeTo(cos(pi / 4), 0.01));
      expect(engine.position, const Duration(seconds: 3));

      async.elapse(const Duration(seconds: 3, milliseconds: 100));
      expect(decks[1].level, 1);
      expect(decks[0].playing, isFalse, reason: 'it ended');
      expect(decks[0].opened, isEmpty);
      expect(engine.index, 1);
      expect(ended, [1]);
    });
  });

  test('the next track changed after it opened ahead (one put next, say) opens there in its place', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);
      final tracks = [track(0), track(1)];

      unawaited(engine.open(tracks, index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 50));
      expect(decks[1].opened, [tracks[1]]);

      final next = track(2);

      unawaited(engine.add([next], next: true));
      async.elapse(const Duration(milliseconds: 100));
      expect(decks[1].opened, [next]);

      async.elapse(const Duration(seconds: 4));
      expect(engine.index, 1);
      expect(decks[1].playing, isTrue);
      expect(engine.order, [0, 1, 2]);
    });
  });

  test('the crossfade lasts half of a short track at most', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);

      unawaited(engine.open([track(0), track(1, seconds: 4), track(2)], index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 57, milliseconds: 900));
      expect(engine.index, 0);

      async.elapse(const Duration(milliseconds: 100));
      expect(engine.index, 1, reason: 'into it over 2 s');

      async.elapse(const Duration(seconds: 2));
      expect(engine.index, 2, reason: 'out of it over 2 s, as the one before it ends');
      expect(decks[1].playing, isTrue);
      expect(decks[0].opened, hasLength(1));
      expect(decks[0].playing, isTrue);
    });
  });

  test('where the deck says how long its track is, that goes before the media server', () {
    fakeAsync((async) {
      final decks = [FakeEngine()..duration = const Duration(seconds: 30), FakeEngine()];
      final engine = crossfading(decks);

      unawaited(engine.open([track(0), track(1)], index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 24));
      expect(engine.index, 1);
    });
  });

  test('a track whose length is unknown plays to its end, the next one starting then, whole', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);
      final tracks = [track(0, seconds: null), track(1, seconds: null)];
      final ended = <int>[];

      engine.ended.listen((_) => ended.add(engine.index));
      unawaited(engine.open(tracks, index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(minutes: 5));
      expect(engine.index, 0);
      expect(decks[1].opened, isEmpty);

      decks[0].endTrack();
      async.flushMicrotasks();
      expect(engine.index, 1);
      expect(ended, [1]);
      expect(decks[0].opened, [tracks[1]]);
      expect(decks[0].playing, isTrue);
      expect(decks[0].level, 1);
    });
  });

  test('repeating the current track, its deck starts it over, with no crossfade', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);
      var ended = 0;
      engine.ended.listen((_) => ended++);
      unawaited(engine.open([track(0), track(1)], index: 0, position: Duration.zero, play: true));
      unawaited(engine.setRepeat(Repeat.one));
      async.elapse(const Duration(seconds: 59));
      expect(decks[0].repeat, Repeat.one);
      expect(decks[1].opened, isEmpty);
      expect(engine.index, 0);

      decks[0].endTrack();
      async.flushMicrotasks();
      expect(ended, 1);
      expect(engine.index, 0);
      expect(engine.position, Duration.zero);
    });
  });

  test('repeating the queue, the last track crossfades into the first', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);

      unawaited(engine.open([track(0), track(1)], index: 1, position: Duration.zero, play: true));
      unawaited(engine.setRepeat(Repeat.all));
      async.elapse(const Duration(seconds: 55));
      expect(engine.index, 0);
      expect(decks[1].repeat, Repeat.off, reason: 'the engine goes on to the next itself');
    });
  });

  test('the last track, repeat off, plays to its end; play then starts the queue over from the first', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);
      final tracks = [track(0), track(1)];
      var ended = 0;
      engine.ended.listen((_) => ended++);
      unawaited(engine.open(tracks, index: 1, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 59));
      expect(decks[1].opened, isEmpty);

      decks[0].endTrack();
      async.flushMicrotasks();
      expect(ended, 1);
      expect(engine.index, 1);
      expect(engine.playing, isFalse);

      unawaited(engine.play());
      async.flushMicrotasks();
      expect(engine.index, 0);
      expect(engine.playing, isTrue);
      expect(engine.position, Duration.zero);
    });
  });

  test('paused during a crossfade, both tracks pause where they are, and play on together', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);

      unawaited(engine.open([track(0), track(1)], index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 56));
      unawaited(engine.pause());
      async.elapse(const Duration(seconds: 30));
      expect(engine.playing, isFalse);
      expect(decks.map((deck) => deck.playing), [false, false]);
      expect(decks[1].level, closeTo(sin(pi / 6), 0.01), reason: '2 s of 6 in');
      expect(decks[0].level, closeTo(cos(pi / 6), 0.01));

      unawaited(engine.play());
      async.elapse(const Duration(seconds: 1));
      expect(decks.map((deck) => deck.playing), [true, true]);
      expect(decks[1].level, closeTo(sin(pi / 4), 0.01));
    });
  });

  test('a seek during a crossfade stops the track fading out, the current one at the whole volume', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);

      unawaited(engine.open([track(0), track(1)], index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 56));
      unawaited(engine.seek(const Duration(seconds: 30)));
      async.flushMicrotasks();
      expect(decks[0].playing, isFalse);
      expect(decks[1].level, 1);
      expect(engine.position, const Duration(seconds: 30));
      expect(engine.index, 1);
    });
  });

  test('a jump during a crossfade, or to another track, stops the track before at once', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);
      final tracks = [track(0), track(1), track(2)];

      unawaited(engine.open(tracks, index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 56));
      unawaited(engine.jump(2));
      async.flushMicrotasks();
      expect(engine.index, 2);
      expect(decks[1].opened, [tracks[2]]);
      expect(decks[1].level, 1);
      expect(decks[0].playing, isFalse);
    });
  });

  test('a jump to the next track, opened ahead, starts it at once on its deck', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);
      final tracks = [track(0), track(1)];

      unawaited(engine.open(tracks, index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 50));
      unawaited(engine.jump(1));
      async.flushMicrotasks();
      expect(engine.index, 1);
      expect(decks[1].playing, isTrue);
      expect(decks[1].level, 1);
      expect(decks[0].playing, isFalse);
      expect(decks[0].opened, isEmpty);
    });
  });

  test('a jump to the current track starts it over on its deck', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);

      unawaited(engine.open([track(0), track(1)], index: 0, position: const Duration(seconds: 20), play: false));
      unawaited(engine.jump(0));
      async.elapse(const Duration(seconds: 1));
      expect(engine.playing, isTrue);
      expect(engine.position, const Duration(seconds: 1));
    });
  });

  test('the engine tells of its current deck\'s changes, not of the other\'s', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);

      unawaited(engine.open([track(0), track(1)], index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 40));
      var changes = 0;
      engine.changes.listen((_) => changes++);
      async.elapse(const Duration(seconds: 10));
      expect(decks[1].opened, hasLength(1));
      expect(changes, 0, reason: 'opened ahead');

      decks[0].fail();
      async.flushMicrotasks();
      expect(changes, 1);
      expect(engine.failed, isTrue);
    });
  });

  test('the volume is each deck\'s, whatever the level it plays at', () {
    fakeAsync((async) {
      final decks = [FakeEngine(), FakeEngine()];
      final engine = crossfading(decks);

      unawaited(engine.setVolume(40));
      unawaited(engine.open([track(0), track(1)], index: 0, position: Duration.zero, play: true));
      async.elapse(const Duration(seconds: 57));
      expect(engine.volume, 40);
      expect(decks.map((deck) => deck.volume), [40, 40]);
      expect(decks[1].level, lessThan(1));
    });
  });

  group('the queue', () {
    late List<TrackSource> tracks;

    setUp(() => tracks = [for (var i = 0; i < 4; i++) track(i)]);

    test('shuffled, the current track first, the others after it; off, back to their order', () {
      fakeAsync((async) {
        final engine = crossfading([FakeEngine(), FakeEngine()]);

        unawaited(engine.open(tracks, index: 2, position: Duration.zero, play: true));
        unawaited(engine.setShuffle(true));
        async.flushMicrotasks();
        expect(engine.order.first, 2);
        expect(engine.order.toSet(), {0, 1, 2, 3});
        expect(engine.index, 0);

        unawaited(engine.setShuffle(false));
        async.flushMicrotasks();
        expect(engine.order, [0, 1, 2, 3]);
        expect(engine.index, 2);
      });
    });

    test('opened shuffled, in the order given; otherwise shuffled anew', () {
      fakeAsync((async) {
        final engine = crossfading([FakeEngine(), FakeEngine()]);

        unawaited(engine.setShuffle(true));
        unawaited(engine.open(tracks, index: 1, position: Duration.zero, play: true, order: [3, 1, 0, 2]));
        async.flushMicrotasks();
        expect(engine.order, [3, 1, 0, 2]);
        expect(engine.index, 1);

        unawaited(engine.open(tracks, index: 1, position: Duration.zero, play: true));
        async.flushMicrotasks();
        expect(engine.order.first, 1);
        expect(engine.index, 0);
      });
    });

    test('tracks added play next, or after the last, in the play order and in their order alike', () {
      fakeAsync((async) {
        final engine = crossfading([FakeEngine(), FakeEngine()]);

        unawaited(engine.open(tracks, index: 1, position: Duration.zero, play: true));

        final (next, last) = (track(4), track(5));

        late int at;

        unawaited(engine.add([next], next: true).then((place) => at = place));
        async.flushMicrotasks();
        expect(at, 2);
        expect(engine.order, [0, 1, 2, 3, 4]);

        unawaited(engine.add([last], next: false).then((place) => at = place));
        async.flushMicrotasks();
        expect(at, 5);
        expect(engine.index, 1);
      });
    });

    test('a move takes a track to its new place, the current one playing on; shuffled, in the play order alone', () {
      fakeAsync((async) {
        final engine = crossfading([FakeEngine(), FakeEngine()]);

        unawaited(engine.open(tracks, index: 1, position: Duration.zero, play: true));

        ({int from, int to})? unshuffled;

        unawaited(engine.move(0, 3).then((moved) => unshuffled = moved));
        async.flushMicrotasks();
        expect(unshuffled, (from: 0, to: 3));
        expect(engine.index, 0, reason: 'the current track, where it went');

        unawaited(engine.setShuffle(true));
        async.flushMicrotasks();

        final order = engine.order;

        unawaited(engine.move(1, 3).then((moved) => unshuffled = moved));
        async.flushMicrotasks();
        expect(unshuffled, isNull);
        expect(engine.order, [order[0], order[2], order[3], order[1]]);
      });
    });

    test('a removal takes a track out, but never the current one', () {
      fakeAsync((async) {
        final engine = crossfading([FakeEngine(), FakeEngine()]);

        unawaited(engine.open(tracks, index: 2, position: Duration.zero, play: true));

        final removed = <int>[];

        unawaited(engine.remove(0).then(removed.add));
        async.flushMicrotasks();
        unawaited(engine.remove(1).then(removed.add));
        async.flushMicrotasks();
        expect(removed, [0, -1]);
        expect(engine.order, [0, 1, 2]);
        expect(engine.index, 1);
      });
    });
  });
}
