import 'dart:convert';

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
    final next = await engine.opened.last.address(Duration.zero);
    expect(next?.queryParameters['id'], 's2');
    expect(next?.queryParameters.containsKey('maxBitRate'), isFalse);
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

    final later = await engine.opened.first.address(const Duration(seconds: 42));
    expect(later?.queryParameters, containsPair('maxBitRate', '96'));
    expect(later?.queryParameters, containsPair('timeOffset', '42'));

    quality = StreamQuality.original;
    expect(await engine.opened.first.address(const Duration(seconds: 42)), isNull);
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
