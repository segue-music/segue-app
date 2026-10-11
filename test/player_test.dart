import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/equalizer_choice.dart';
import 'package:segue/player/engine.dart';
import 'package:segue/player/player.dart';
import 'package:segue/quality_choice.dart';
import 'package:segue/replay_gain_choice.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/server/models.dart';
import 'package:segue/subsonic/api.dart';

import 'fakes.dart';

final api = SubsonicApi(
  Uri.parse('https://music.test'),
  const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
);

const songs = [
  Song(id: 's1', title: 'One', duration: Duration(minutes: 3)),
  Song(id: 's2', title: 'Two', duration: Duration(minutes: 4)),
];

void main() {
  late FakeEngine engine;
  late PlayerController player;
  late List<PlayerState> reports;

  setUp(() {
    engine = FakeEngine();
    player = PlayerController(engine, api);
    reports = [];
    player.onReport = reports.add;
  });

  test('plays a queue from the server, and reports it once', () async {
    await player.playQueue(songs, index: 1);
    expect(engine.tracks.last.queryParameters['id'], 's2');
    expect(player.current?.title, 'Two');
    expect(reports.first.queue?.map((item) => item.id), ['s1', 's2']);
    expect(reports.first.status, PlaybackStatus.playing);

    await player.toggle();
    expect(reports.last.status, PlaybackStatus.paused);
    expect(reports.last.queue, isNull, reason: 'the queue goes only when it changes');
    expect(player.report(full: true).queue, hasLength(2));
  });

  test('streams in the quality in use as each song loads: a new one holds from the next song on', () async {
    var quality = StreamQuality.normal;
    player = PlayerController(engine, api, quality: () => quality);
    await player.playQueue(songs);
    expect(engine.tracks.first.queryParameters, containsPair('maxBitRate', '160'));

    quality = StreamQuality.original;
    final next = engine.opened.last.address();
    expect(next.queryParameters['id'], 's2');
    expect(next.queryParameters.containsKey('maxBitRate'), isFalse);
  });

  test('a song the server transcodes starts later where it can; the file as it is never needs to', () async {
    final offsets = SubsonicApi(
      Uri.parse('https://music.test'),
      const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'openSubsonicExtensions': [
                {
                  'name': 'transcodeOffset',
                  'versions': [1],
                },
              ],
            },
          }),
          200,
        ),
      ),
    );
    var quality = StreamQuality.low;
    player = PlayerController(engine, offsets, quality: () => quality);
    await player.playQueue(songs);

    final later = await engine.opened.first.addressFrom(const Duration(seconds: 42));
    expect(later?.queryParameters, containsPair('maxBitRate', '96'));
    expect(later?.queryParameters, containsPair('timeOffset', '42'));

    quality = StreamQuality.original;
    expect(await engine.opened.first.addressFrom(const Duration(seconds: 42)), isNull);
  });

  group('ReplayGain', () {
    // Two songs of an album, its third, another album's, and a song with no gain from the server. Each plays
    // replayGainPreamp louder than its gain, still under 0 dB, where a gain with no peak said stops.
    const queue = [
      Song(id: 's1', title: 'One', albumId: 'a1', replayGain: ReplayGain(trackGain: -16, albumGain: -14)),
      Song(id: 's2', title: 'Two', albumId: 'a1', replayGain: ReplayGain(trackGain: -13, albumGain: -14)),
      Song(id: 's3', title: 'Three', albumId: 'a2', replayGain: ReplayGain(trackGain: -18, albumGain: -17)),
      Song(id: 's4', title: 'Four', albumId: 'a2'),
      Song(id: 's5', title: 'Five', albumId: 'a3', replayGain: ReplayGain(trackGain: -15, albumGain: -13)),
    ];

    List<TrackGain> gains() => [for (final track in engine.opened) track.gain()];

    test('the automatic way levels a song by its album\'s gain where it plays among its album\'s, in their order, and '
        'by its own otherwise; a song the server gave no gain for, by its file\'s tags', () async {
      final choice = ReplayGainChoice(ReplayGainMode.automatic);
      addTearDown(choice.dispose);
      player = PlayerController(engine, api, replayGain: choice);
      await player.playQueue(queue);
      expect(gains(), const [
        TrackGain(-14 + replayGainPreamp),
        TrackGain(-14 + replayGainPreamp),
        TrackGain(-17 + replayGainPreamp),
        TrackGain.tagged(album: true, preamp: replayGainPreamp),
        TrackGain(-15 + replayGainPreamp),
      ]);

      await player.setShuffle(true);
      expect(gains(), const [
        TrackGain(-16 + replayGainPreamp),
        TrackGain(-13 + replayGainPreamp),
        TrackGain(-18 + replayGainPreamp),
        TrackGain.tagged(album: false, preamp: replayGainPreamp),
        TrackGain(-15 + replayGainPreamp),
      ], reason: 'shuffled, a song plays among others');
    });

    test('a song added plays among the songs around it where it went, and so do they', () async {
      final choice = ReplayGainChoice(ReplayGainMode.automatic);
      addTearDown(choice.dispose);
      player = PlayerController(engine, api, replayGain: choice);
      await player.playQueue([queue[0], queue[2]]);
      expect(gains(), const [TrackGain(-16 + replayGainPreamp), TrackGain(-18 + replayGainPreamp)]);

      await player.addToQueue([queue[1]], next: true);
      expect(gains(), const [
        TrackGain(-14 + replayGainPreamp),
        TrackGain(-14 + replayGainPreamp),
        TrackGain(-18 + replayGainPreamp),
      ]);
    });

    test('by song, by album, or not at all, as picked; a pick holds at once for the song that plays', () async {
      final choice = ReplayGainChoice(ReplayGainMode.track);
      addTearDown(choice.dispose);
      player = PlayerController(engine, api, replayGain: choice);
      await player.playQueue(queue, index: 1);
      expect(gains(), const [
        TrackGain(-16 + replayGainPreamp),
        TrackGain(-13 + replayGainPreamp),
        TrackGain(-18 + replayGainPreamp),
        TrackGain.tagged(album: false, preamp: replayGainPreamp),
        TrackGain(-15 + replayGainPreamp),
      ]);

      choice.value = ReplayGainMode.album;
      await pumpEventQueue();
      expect(engine.gain, const TrackGain(-14 + replayGainPreamp), reason: 'the song that plays, at once');
      expect(gains(), const [
        TrackGain(-14 + replayGainPreamp),
        TrackGain(-14 + replayGainPreamp),
        TrackGain(-17 + replayGainPreamp),
        TrackGain.tagged(album: true, preamp: replayGainPreamp),
        TrackGain(-13 + replayGainPreamp),
      ]);

      choice.value = ReplayGainMode.off;
      await pumpEventQueue();
      expect(engine.gain, TrackGain.none);
      expect(gains(), everyElement(TrackGain.none));
    });

    test('songs another device sent, which have no album ids, play among their album\'s by its name', () async {
      final choice = ReplayGainChoice(ReplayGainMode.automatic);
      addTearDown(choice.dispose);
      player = PlayerController(engine, api, replayGain: choice);
      await player.obey(
        const Command.setQueue(
          queue: [
            QueueItem(id: 's1', title: 'One', album: 'Toys in the Attic'),
            QueueItem(id: 's2', title: 'Two', album: 'Toys in the Attic'),
            QueueItem(id: 's3', title: 'Three', album: 'Rocks'),
            QueueItem(id: 's4', title: 'Four'),
            QueueItem(id: 's5', title: 'Five'),
          ],
          index: 0,
          positionMs: 0,
          play: true,
        ),
      );
      expect(gains(), const [
        TrackGain.tagged(album: true, preamp: replayGainPreamp),
        TrackGain.tagged(album: true, preamp: replayGainPreamp),
        TrackGain.tagged(album: false, preamp: replayGainPreamp),
        TrackGain.tagged(album: false, preamp: replayGainPreamp),
        TrackGain.tagged(album: false, preamp: replayGainPreamp),
      ], reason: 'songs of no album aren\'t of the same one');
    });

    test('with no way given, the songs play as they are', () async {
      await player.playQueue(queue);
      expect(gains(), everyElement(TrackGain.none));
    });

    test('a player gone no longer follows the way picked', () async {
      final choice = ReplayGainChoice(ReplayGainMode.automatic);
      addTearDown(choice.dispose);
      player = PlayerController(engine, api, replayGain: choice);
      await player.playQueue(queue);
      await player.dispose();
      choice.value = ReplayGainMode.off;
      await pumpEventQueue();
      expect(engine.gain, isNull);
    });
  });

  group('equalizer', () {
    test('the songs play through the equalizer as set, from the start, and as it changes', () async {
      final choice = EqualizerChoice(const EqualizerSettings(on: true, preset: EqualizerPreset.rock));
      addTearDown(choice.dispose);
      player = PlayerController(engine, api, equalizer: choice);
      await pumpEventQueue();
      expect(engine.equalizer, {31: 5, 63: 5, 125: 4, 250: 3, 500: 1, 1000: -1, 2000: 1, 4000: 3, 8000: 4, 16000: 5});

      choice.value = choice.value.copyWith(preset: EqualizerPreset.custom, custom: [5, 5, 4, 3, 1, 6, 1, 3, 4, 5]);
      await pumpEventQueue();
      expect(engine.equalizer, containsPair(1000, 6), reason: 'the band moved');
      expect(engine.equalizer, containsPair(31, 5), reason: 'the others as they were');

      choice.value = choice.value.copyWith(on: false);
      await pumpEventQueue();
      expect(engine.equalizer, isEmpty, reason: 'off, the songs as they are');
    });

    test('with no equalizer given, the engine is never asked', () async {
      await player.playQueue(songs);
      expect(engine.equalizer, isNull);
    });

    test('a player gone no longer follows the equalizer', () async {
      final choice = EqualizerChoice();
      addTearDown(choice.dispose);
      player = PlayerController(engine, api, equalizer: choice);
      await pumpEventQueue();
      await player.dispose();
      choice.value = choice.value.copyWith(on: true);
      await pumpEventQueue();
      expect(engine.equalizer, isEmpty);
    });
  });

  test('a seek is reported, though the engine says nothing', () async {
    await player.playQueue(songs);
    await player.seek(const Duration(seconds: 42));
    expect(reports.last.positionMs, greaterThanOrEqualTo(42000));
  });

  test('obeys commands, and refuses a track that is not there', () async {
    await player.playQueue(songs);
    await player.obey(const Command(CommandAction.next));
    expect(player.index, 1);
    await expectLater(player.obey(const Command(CommandAction.next)), throwsA(isA<CommandFailed>()));
    await player.obey(const Command.setVolume(30));
    expect(player.volume, 30);
    await player.obey(const Command(CommandAction.stop));
    expect(player.status, PlaybackStatus.stopped);
  });

  test('previous goes back to the start of the track, and to the previous one in its first seconds', () async {
    await player.playQueue(songs, index: 1, position: const Duration(seconds: 40));
    await player.previous();
    expect(player.index, 1);
    expect(player.position.inSeconds, 0);
    await player.previous();
    expect(player.index, 0);
    await player.seek(const Duration(seconds: 1));
    await player.previous(); // the first track: back to its start, never an error
    expect(player.index, 0);
    expect(player.position.inSeconds, 0);
  });

  test('a jump plays the track at that place in the queue from its start, even paused', () async {
    const three = [...songs, Song(id: 's3', title: 'Three')];
    await player.playQueue(three, position: const Duration(seconds: 30), play: false);
    await player.jump(2);
    expect(player.current?.id, 's3');
    expect(player.playing, isTrue);
    expect(player.position.inSeconds, 0);
    expect(reports.last.index, 2);
    expect(reports.last.status, PlaybackStatus.playing);

    await player.seek(const Duration(seconds: 30));
    await player.jump(2);
    expect(player.index, 2);
    expect(player.position.inSeconds, 0, reason: 'the current track starts over');

    await player.obey(const Command.jump(0));
    expect(player.current?.id, 's1');
    await expectLater(player.obey(const Command.jump(3)), throwsA(isA<CommandFailed>()));
    expect(player.current?.id, 's1');
  });

  test('with shuffle on, a jump goes by the play order', () async {
    const three = [...songs, Song(id: 's3', title: 'Three')];
    await player.playQueue(three);
    await player.setShuffle(true);
    expect(player.queue.map((song) => song.id), ['s1', 's3', 's2']); // the fake's shuffle
    await player.jump(1);
    expect(player.current?.id, 's3');
  });

  test('setQueue skips items without an id and keeps the current track current', () async {
    await player.obey(
      const Command.setQueue(
        queue: [
          QueueItem(title: 'Untranslatable'),
          QueueItem(id: 's1', title: 'One'),
          QueueItem(id: 's2', title: 'Two'),
        ],
        index: 2,
        positionMs: 5000,
        play: false,
      ),
    );
    expect(player.queue.map((song) => song.id), ['s1', 's2']);
    expect(player.current?.title, 'Two');
    expect(player.position, const Duration(seconds: 5));
    expect(player.playing, isFalse);
  });

  test('setQueue plays in the modes it brings: shuffled, in the order it came, which shuffle going off takes back to '
      'the one unshuffled, the items it skips left out; and repeating', () async {
    await player.obey(
      const Command.setQueue(
        // Unshuffled: Untranslatable, One, Two, Three.
        queue: [
          QueueItem(id: 's3', title: 'Three'),
          QueueItem(title: 'Untranslatable'),
          QueueItem(id: 's1', title: 'One'),
          QueueItem(id: 's2', title: 'Two'),
        ],
        index: 2,
        positionMs: 0,
        play: false,
        repeat: Repeat.all,
        shuffle: true,
        order: [3, 0, 1, 2],
      ),
    );
    expect(player.queue.map((song) => song.title), ['Three', 'One', 'Two'], reason: 'as it came, not shuffled again');
    expect(player.current?.title, 'One');
    expect((player.shuffle, player.repeat), (true, Repeat.all));
    expect(player.report(full: true).order, [2, 0, 1], reason: 'each song\'s place among them unshuffled');

    await player.setShuffle(false);
    expect(player.queue.map((song) => song.title), ['One', 'Two', 'Three']);
    expect(player.current?.title, 'One');
    expect(player.report(full: true).order, isNull, reason: 'none, unshuffled');

    // Not shuffled, as it comes; without modes, in the player's own.
    await player.setShuffle(true);
    await player.obey(
      const Command.setQueue(
        queue: [
          QueueItem(id: 's2', title: 'Two'),
          QueueItem(id: 's1', title: 'One'),
        ],
        index: 0,
        positionMs: 0,
        play: false,
        shuffle: false,
      ),
    );
    expect(player.queue.map((song) => song.title), ['Two', 'One']);
    expect(player.shuffle, isFalse);
    expect(player.repeat, Repeat.all, reason: 'as it was');
  });

  test('a queue opening in modes tells of itself alone: not of the one before, shuffled as shuffle goes on', () async {
    await player.playQueue([...songs, const Song(id: 's3', title: 'Three')]);
    reports.clear();
    await player.obey(
      const Command.setQueue(
        queue: [
          QueueItem(id: 's5', title: 'Five'),
          QueueItem(id: 's4', title: 'Four'),
        ],
        index: 0,
        positionMs: 0,
        play: true,
        shuffle: true,
        order: [1, 0],
      ),
    );
    expect(reports, hasLength(1));
    expect(reports.single.queue?.map((item) => item.title), ['Five', 'Four']);
    expect(reports.single.order, [1, 0]);
  });

  test('next after the last track goes to the first, unless repeat is off', () async {
    await player.playQueue(songs, index: 1);
    await expectLater(player.next(), throwsA(isA<CommandFailed>()));
    await player.setRepeat(Repeat.all);
    await player.next();
    expect(player.index, 0);
  });

  test('another track ends repeating one track, and the queue goes on repeating', () async {
    const three = [...songs, Song(id: 's3', title: 'Three')];
    await player.playQueue(three);
    await player.setRepeat(Repeat.one);
    await player.next();
    expect(player.index, 1);
    expect(player.repeat, Repeat.all);
    expect(reports.last.repeat, Repeat.all);

    await player.setRepeat(Repeat.one);
    await player.previous();
    expect(player.index, 0);
    expect(player.repeat, Repeat.all);

    await player.setRepeat(Repeat.one);
    await player.obey(const Command.jump(2));
    expect(player.index, 2);
    expect(player.repeat, Repeat.all);

    await player.setRepeat(Repeat.one);
    await player.next(); // after the last track, the first
    expect(player.index, 0);
    expect(player.repeat, Repeat.all);
  });

  test('starting the track over keeps repeating it', () async {
    await player.playQueue(songs, index: 1, position: const Duration(seconds: 40));
    await player.setRepeat(Repeat.one);
    await player.previous();
    expect(player.position.inSeconds, 0);
    await player.jump(1);
    expect(player.index, 1);
    expect(player.repeat, Repeat.one);
    await player.playQueue(songs.take(1).toList());
    await player.next(); // the only track: the next one is itself
    expect(player.repeat, Repeat.one);
  });

  test('shuffle reorders the queue, keeping the current song, and off puts it back', () async {
    const three = [...songs, Song(id: 's3', title: 'Three')];
    await player.playQueue(three, index: 1);
    reports.clear();
    await player.setShuffle(true);
    expect(player.shuffle, isTrue);
    expect(player.queue.map((song) => song.id), ['s2', 's3', 's1']); // the fake's shuffle
    expect(player.current?.id, 's2');
    // The queue goes once, in the report after the change; the others leave it out.
    expect(reports.lastWhere((report) => report.queue != null).queue?.map((item) => item.id), ['s2', 's3', 's1']);
    expect(reports.last.shuffle, isTrue);
    await player.setShuffle(false);
    expect(player.queue.map((song) => song.id), ['s1', 's2', 's3']);
    expect(player.current?.id, 's2');
    expect(reports.last.shuffle, isFalse);
  });

  group('adding to the queue', () {
    const three = [...songs, Song(id: 's3', title: 'Three')];
    const added = [Song(id: 'a1', title: 'Added one'), Song(id: 'a2', title: 'Added two')];

    List<String> ids() => [for (final song in player.queue) song.id];

    test(
      'play next puts the songs right after the current one, which plays on where it was; add, after the last',
      () async {
        await player.playQueue(three, index: 1, position: const Duration(seconds: 30));
        reports.clear();
        await player.addToQueue(added, next: true);
        expect(ids(), ['s1', 's2', 'a1', 'a2', 's3']);
        expect(player.current?.id, 's2');
        expect(player.playing, isTrue);
        expect(player.position.inSeconds, 30);
        expect(reports.last.queue?.map((item) => item.id), ['s1', 's2', 'a1', 'a2', 's3']);
        expect(reports.last.index, 1);

        await player.addToQueue(const [Song(id: 'a3', title: 'Added three')], next: false);
        expect(ids(), ['s1', 's2', 'a1', 'a2', 's3', 'a3']);
        expect(engine.tracks.map((track) => track.queryParameters['id']), ['s1', 's2', 'a1', 'a2', 's3', 'a3']);
        await player.next();
        expect(player.current?.id, 'a1');
      },
    );

    test(
      'shuffled, play next goes after the current song in the play order, and stays after it as shuffle goes off',
      () async {
        await player.playQueue(three, index: 1);
        await player.setShuffle(true);
        expect(ids(), ['s2', 's3', 's1']); // the fake's shuffle
        await player.addToQueue(added.take(1).toList(), next: true);
        await player.addToQueue(added.skip(1).toList(), next: false);
        expect(ids(), ['s2', 'a1', 's3', 's1', 'a2']);
        expect(player.current?.id, 's2');

        await player.setShuffle(false);
        expect(ids(), ['s1', 's2', 'a1', 's3', 'a2']);
        expect(player.current?.id, 's2');
      },
    );

    test('adds made at once go in the order they were made', () async {
      await player.playQueue(songs);
      await Future.wait([
        player.addToQueue(added.take(1).toList(), next: true),
        player.addToQueue(added.skip(1).toList(), next: true),
      ]);
      expect(ids(), ['s1', 'a2', 'a1', 's2']);
    });

    test('to an empty queue, the songs are the queue, paused at the first', () async {
      await player.addToQueue(added, next: true);
      expect(ids(), ['a1', 'a2']);
      expect(player.index, 0);
      expect(player.playing, isFalse);
      expect(reports.lastWhere((report) => report.queue != null).queue?.map((item) => item.id), ['a1', 'a2']);
    });

    test('obeys addToQueue, skipping the items without an id, and fails with none left', () async {
      await player.playQueue(songs);
      await player.obey(
        const Command.addToQueue(
          queue: [
            QueueItem(title: 'Untranslatable'),
            QueueItem(id: 'a1', title: 'Added one'),
          ],
          next: true,
        ),
      );
      expect(ids(), ['s1', 'a1', 's2']);
      expect(player.queue[1].title, 'Added one');
      await expectLater(
        player.obey(const Command.addToQueue(queue: [QueueItem(title: 'Untranslatable')], next: false)),
        throwsA(isA<CommandFailed>()),
      );
      expect(ids(), ['s1', 'a1', 's2']);
    });
  });

  group('moving and removing songs in the queue', () {
    const four = [...songs, Song(id: 's3', title: 'Three'), Song(id: 's4', title: 'Four')];

    List<String> ids() => [for (final song in player.queue) song.id];

    test('a move takes the song to its new place, the current one playing on where it was, wherever it goes', () async {
      await player.playQueue(four, index: 1, position: const Duration(seconds: 30));
      reports.clear();
      await player.moveInQueue(3, 0);
      expect(ids(), ['s4', 's1', 's2', 's3']);
      expect(player.current?.id, 's2');
      expect(player.index, 2);
      expect(player.playing, isTrue);
      expect(player.position.inSeconds, 30);
      expect(reports.last.queue?.map((item) => item.id), ['s4', 's1', 's2', 's3']);
      expect(reports.last.index, 2);

      // The current song itself.
      await player.moveInQueue(2, 3);
      expect(ids(), ['s4', 's1', 's3', 's2']);
      expect(player.index, 3);
      expect(engine.tracks.map((track) => track.queryParameters['id']), ['s4', 's1', 's3', 's2']);
      await player.previous();
      await player.previous();
      expect(player.current?.id, 's3');
    });

    test("the reports during a move never have the current song's new place with the songs as they were", () async {
      await player.playQueue(four, index: 1);
      reports.clear();
      await player.moveInQueue(3, 0);
      var queue = four.map((song) => song.id).toList();

      for (final report in reports) {
        queue = report.queue?.map((item) => item.id!).toList() ?? queue;
        expect(queue[report.index!], 's2');
      }
    });

    test('shuffled, a move changes the play order alone, which shuffle going off forgets', () async {
      await player.playQueue(four.take(3).toList(), index: 1);
      await player.setShuffle(true);
      expect(ids(), ['s2', 's3', 's1']); // the fake's shuffle
      await player.moveInQueue(2, 1);
      expect(ids(), ['s2', 's1', 's3']);
      expect(player.current?.id, 's2');
      await player.setShuffle(false);
      expect(ids(), ['s1', 's2', 's3']);
      expect(player.current?.id, 's2');
    });

    test('a removal takes the song out, the current one playing on; the current one stays', () async {
      await player.playQueue(four, index: 2, position: const Duration(seconds: 30));
      reports.clear();
      await player.removeFromQueue(0);
      expect(ids(), ['s2', 's3', 's4']);
      expect(player.current?.id, 's3');
      expect(player.index, 1);
      expect(player.position.inSeconds, 30);
      expect(reports.last.queue?.map((item) => item.id), ['s2', 's3', 's4']);
      expect(reports.last.index, 1);

      await player.removeFromQueue(2);
      expect(ids(), ['s2', 's3']);
      expect(engine.tracks.map((track) => track.queryParameters['id']), ['s2', 's3']);
      await expectLater(
        player.removeFromQueue(1),
        throwsA(isA<CommandFailed>().having((e) => e.message, 'message', 'current track')),
      );
      await expectLater(
        player.moveInQueue(0, 2),
        throwsA(isA<CommandFailed>().having((e) => e.message, 'message', 'no such track')),
      );
      expect(ids(), ['s2', 's3']);
    });

    test('shuffled, a removal takes the song out of the play order and of the order unshuffled alike', () async {
      await player.playQueue(four.take(3).toList(), index: 1);
      await player.setShuffle(true);
      expect(ids(), ['s2', 's3', 's1']); // the fake's shuffle
      await player.removeFromQueue(1);
      expect(ids(), ['s2', 's1']);
      await player.setShuffle(false);
      expect(ids(), ['s1', 's2']);
      expect(player.current?.id, 's2');
    });

    test('changes made at once go in the order they were made', () async {
      await player.playQueue(four);
      await Future.wait([player.moveInQueue(3, 1), player.removeFromQueue(2), player.addToQueue(songs, next: false)]);
      expect(ids(), ['s1', 's4', 's3', 's1', 's2']);
    });

    test('obeys moveInQueue and removeFromQueue', () async {
      await player.playQueue(four);
      await player.obey(const Command.moveInQueue(index: 3, to: 1));
      expect(ids(), ['s1', 's4', 's2', 's3']);
      await player.obey(const Command.removeFromQueue(2));
      expect(ids(), ['s1', 's4', 's3']);
    });
  });

  group('autoplay', () {
    late ValueNotifier<bool> autoplay;
    late SubsonicApi server;

    // The songs the server gives as like the one asked about, by their ids; until [held] completes, none, and with
    // [fails], an error.
    late List<String> similar;
    late List<String> asked;
    Completer<void>? held;
    late bool fails;

    List<String> ids() => [for (final song in player.queue) song.id];

    setUp(() {
      autoplay = ValueNotifier(true);
      similar = ['s1', for (var i = 3; i <= 14; i++) 's$i'];
      asked = [];
      held = null;
      fails = false;
      server = SubsonicApi(
        Uri.parse('https://music.test'),
        const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
        client: MockClient((request) async {
          asked.add(request.url.queryParameters['id']!);
          await held?.future;

          return fails
              ? http.Response('', 500)
              : http.Response(
                  jsonEncode({
                    'subsonic-response': {
                      'status': 'ok',
                      'similarSongs2': {
                        'song': [
                          for (final id in similar) {'id': id, 'title': 'Song $id'},
                        ],
                      },
                    },
                  }),
                  200,
                );
        }),
      );
      engine = FakeEngine();
      player = PlayerController(engine, server, autoplay: autoplay);
      reports = [];
      player.onReport = reports.add;
    });

    test('as the queue\'s last song plays, repeat off, songs like it go after it: those the queue hasn\'t yet, '
        '${PlayerController.autoplaySize} at most', () async {
      await player.playQueue(songs);
      await pumpEventQueue();
      expect(asked, isEmpty, reason: 'not the last song');

      await player.next();
      await pumpEventQueue();
      expect(asked, ['s2'], reason: 'by the last song');
      expect(ids(), ['s1', 's2', for (var i = 3; i <= 12; i++) 's$i']);
      expect(engine.tracks.map((track) => track.queryParameters['id']), ids());
      expect(player.current?.id, 's2');
      expect(player.playing, isTrue);
      expect(reports.last.queue?.map((item) => item.id), ids());

      // The last of them goes on in turn.
      await player.jump(11);
      await pumpEventQueue();
      expect(asked, ['s2', 's12']);
      expect(ids().skip(12), ['s13', 's14']);
    });

    test('not with repeat on, nor paused, nor with autoplay off; as any of them changes, at once', () async {
      autoplay.value = false;
      await player.playQueue(songs, index: 1);
      await player.setRepeat(Repeat.all);
      autoplay.value = true;
      await player.pause();
      await pumpEventQueue();
      expect(asked, isEmpty);

      await player.setRepeat(Repeat.off);
      await pumpEventQueue();
      expect(asked, isEmpty, reason: 'paused');

      await player.play();
      await pumpEventQueue();
      expect(asked, ['s2']);
      expect(ids(), hasLength(12));
    });

    test('asked once for a song, which nothing new, or a failure, leaves to end the queue; the same songs played '
        'again, again', () async {
      similar = ['s1', 's2'];
      await player.playQueue(songs, index: 1);
      await pumpEventQueue();
      await player.pause();
      await player.play();
      await pumpEventQueue();
      expect(asked, ['s2']);
      expect(ids(), ['s1', 's2']);

      fails = true;
      await player.playQueue(songs, index: 1);
      await pumpEventQueue();
      expect(asked, ['s2', 's2']);
      expect(ids(), ['s1', 's2']);
      expect(player.playing, isTrue);
    });

    test('none go where the last song is no longer last as they come, nor with autoplay off or repeat on', () async {
      held = Completer();
      await player.playQueue(songs, index: 1);
      await player.playQueue(const [Song(id: 'o1', title: 'Other')]);
      held!.complete();
      await pumpEventQueue();
      expect(asked, ['s2', 'o1']);
      expect(ids(), ['o1', 's1', 's3', 's4', 's5', 's6', 's7', 's8', 's9', 's10', 's11'], reason: 'after o1 alone');

      held = Completer();
      await player.playQueue(songs, index: 1);
      await player.addToQueue(const [Song(id: 'a1', title: 'Added')], next: false);
      held!.complete();
      await pumpEventQueue();
      expect(ids(), ['s1', 's2', 'a1']);

      for (final change in <Future<void> Function()>[
        () async => autoplay.value = false,
        () => player.setRepeat(Repeat.one),
      ]) {
        autoplay.value = true;
        await player.setRepeat(Repeat.off);
        held = Completer();
        await player.playQueue(songs, index: 1);
        await change();
        held!.complete();
        await pumpEventQueue();
        expect(ids(), ['s1', 's2']);
      }
    });

    test('turned off, the songs it added that haven\'t played go out of the queue, in one report, the current one '
        'playing on; turned on again, they come again', () async {
      await player.playQueue(songs, index: 1);
      await pumpEventQueue();
      await player.addToQueue(const [Song(id: 'a1', title: 'Added')], next: false);
      await player.jump(3);
      reports.clear();
      autoplay.value = false;
      await pumpEventQueue();
      expect(ids(), [
        's1',
        's2',
        's3',
        's4',
        'a1',
      ], reason: 'those played and the one that plays stay, and the user\'s');
      expect(engine.tracks.map((track) => track.queryParameters['id']), ids());
      expect(player.current?.id, 's4');
      expect(player.playing, isTrue);
      expect([for (final report in reports) ?report.queue?.map((item) => item.id)], [ids()]);

      await player.playQueue(songs, index: 1);
      await pumpEventQueue();
      expect(asked, ['s2'], reason: 'off');
      autoplay.value = true;
      await pumpEventQueue();
      expect(ids(), hasLength(12));
      autoplay.value = false;
      await pumpEventQueue();
      expect(ids(), ['s1', 's2']);
      autoplay.value = true;
      await pumpEventQueue();
      expect(asked, ['s2', 's2', 's2'], reason: 'on the same song, again');
      expect(ids(), hasLength(12));
    });

    test('shuffled, the songs it added go out of the play order and of the order unshuffled alike', () async {
      await player.playQueue(songs, index: 1);
      await pumpEventQueue();
      await player.setShuffle(true);
      expect(ids(), ['s2', 's12', 's11', 's10', 's9', 's8', 's7', 's6', 's5', 's4', 's3', 's1']); // the fake's shuffle
      autoplay.value = false;
      await pumpEventQueue();
      expect(ids(), ['s2', 's1']);
      expect(engine.tracks.map((track) => track.queryParameters['id']), ['s1', 's2']);

      await player.setShuffle(false);
      expect(ids(), ['s1', 's2']);
      expect(player.current?.id, 's2');
    });

    test('with none given, never', () async {
      engine = FakeEngine();
      player = PlayerController(engine, server);
      await player.playQueue(songs, index: 1);
      await pumpEventQueue();
      expect(asked, isEmpty);
    });
  });

  group('crossfade', () {
    const three = [...songs, Song(id: 's3', title: 'Three', duration: Duration(minutes: 2))];
    late ValueNotifier<Duration> crossfade;
    late List<FakeEngine> made;

    setUp(() {
      crossfade = ValueNotifier(Duration.zero);
      made = [];
      player.onReport = null; // the one on the same engine, which this one takes the place of
      player = PlayerController(
        engine,
        api,
        crossfade: crossfade,
        crossfadeEngine: () {
          made.add(FakeEngine());

          return made.last;
        },
      );
      player.onReport = reports.add;
    });

    test('on, the queue goes on on the engine that crossfades, from where it was, in its order, as loud, repeating as '
        'it was; off, back on the one before, which the other then stopped', () async {
      await player.playQueue(three, index: 1);
      await player.setShuffle(true);
      await player.setVolume(40);
      await player.setRepeat(Repeat.all);
      await player.seek(const Duration(seconds: 30));
      final queue = player.queue;
      reports.clear();

      crossfade.value = const Duration(seconds: 6);
      await pumpEventQueue();
      expect(made, hasLength(1));
      final crossfading = made.single;
      expect(crossfading.tracks.map((track) => track.queryParameters['id']), ['s1', 's2', 's3']);
      expect(crossfading.orderOpened, [1, 2, 0]);
      expect(crossfading.index, 0);
      expect(crossfading.position, greaterThanOrEqualTo(const Duration(seconds: 30)));
      expect(crossfading.playing, isTrue);
      expect(crossfading.volume, 40);
      expect(crossfading.repeat, Repeat.all);
      expect(crossfading.shuffle, isTrue);
      expect(engine.playing, isFalse, reason: 'stopped');
      expect(player.queue, queue);
      expect(player.current?.id, 's2');
      expect(reports, hasLength(1), reason: 'told of once');
      expect(reports.single.queue, isNull, reason: 'the same queue');

      await player.next();
      expect(crossfading.index, 1, reason: 'what the player is asked goes to it');
      expect(engine.index, 0);

      crossfade.value = Duration.zero;
      await pumpEventQueue();
      expect(engine.opened, hasLength(3));
      expect(engine.orderOpened, [1, 2, 0]);
      expect(engine.index, 1);
      expect(engine.playing, isTrue);
      expect(player.current?.id, 's3');
      expect(made, hasLength(1));
    });

    test('a length for another stays on the same engine', () async {
      crossfade.value = const Duration(seconds: 6);
      await pumpEventQueue();
      crossfade.value = const Duration(seconds: 10);
      await pumpEventQueue();
      expect(made, hasLength(1));
    });

    test('on from the start, the songs play on the engine that crossfades, as long as the media server says', () async {
      crossfade.value = const Duration(seconds: 6);
      made.add(FakeEngine());
      player = PlayerController(engine, api, crossfade: crossfade, crossfadeEngine: () => made.first);
      await player.playQueue(three);
      expect(made.first.opened.map((track) => track.duration), [for (final song in three) song.duration]);
      expect(engine.opened, isEmpty);
    });

    test('the songs ended are the engine\'s that plays them', () async {
      final ended = <String?>[];
      player.songEnded.listen((_) => ended.add(player.current?.id));
      await player.playQueue(three);
      engine.endTrack();
      await pumpEventQueue();

      crossfade.value = const Duration(seconds: 6);
      await pumpEventQueue();
      made.single.endTrack();
      await pumpEventQueue();
      expect(ended, ['s2', 's3']);
    });
  });

  test('obeys setRepeat and setShuffle, and reports both', () async {
    await player.playQueue(songs);
    await player.obey(const Command.setRepeat(Repeat.one));
    expect(player.repeat, Repeat.one);
    expect(reports.last.repeat, Repeat.one);
    await player.obey(const Command.setShuffle(true));
    expect(player.shuffle, isTrue);
    expect(reports.last.shuffle, isTrue);
  });
}
