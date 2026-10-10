// MediaKitEngine on the real libmpv, with the audio sent nowhere. Pins media_kit behaviour the app
// depends on, so that an upgrade that changes it shows up here. Needs libmpv (the dev image has it).
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:segue/player/engine.dart';
import 'package:segue/segue/protocol.dart';

bool get hasLibmpv {
  for (final name in ['libmpv.so.2', 'libmpv.so']) {
    try {
      DynamicLibrary.open(name);
      return true;
    } on ArgumentError {
      continue;
    }
  }

  return false;
}

/// The tones' sample rate.
const rate = 8000;

/// How loud the tones are: their loudest sample.
const loudness = 8000;

/// A short tone as a WAV file's bytes, of 300 + 100 [n] Hz, or [hertz], at [sampleRate], [tags] in an ID3 tag (as TXXX
/// frames, which ReplayGain's are) where it has some.
Uint8List wav(int n, {double seconds = 4, Map<String, String> tags = const {}, double? hertz, int sampleRate = rate}) {
  final samples = (sampleRate * seconds).round();
  final id3 = _id3(tags);
  // An ID3 tag's chunk before the samples', of an even size.
  final id3Chunk = id3.isEmpty ? 0 : 8 + id3.length + id3.length % 2;
  final data = ByteData(44 + id3Chunk + samples * 2);

  void text(int offset, String s) => s.codeUnits.asMap().forEach((i, c) => data.setUint8(offset + i, c));

  text(0, 'RIFF');
  data.setUint32(4, 36 + id3Chunk + samples * 2, Endian.little);
  text(8, 'WAVEfmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);

  if (id3.isNotEmpty) {
    text(36, 'id3 ');
    data.setUint32(40, id3.length, Endian.little);
    data.buffer.asUint8List().setAll(44, id3);
  }

  final samplesAt = 36 + id3Chunk;
  text(samplesAt, 'data');
  data.setUint32(samplesAt + 4, samples * 2, Endian.little);

  final pitch = hertz ?? 300 + 100 * n;

  for (var i = 0; i < samples; i++) {
    data.setInt16(samplesAt + 8 + i * 2, (sin(2 * pi * pitch * i / sampleRate) * loudness).round(), Endian.little);
  }

  return data.buffer.asUint8List();
}

/// An ID3v2.3 tag with [tags], each as a TXXX frame (its name, then its value, in Latin-1); none for no tags.
Uint8List _id3(Map<String, String> tags) {
  final frames = BytesBuilder();

  for (final MapEntry(:key, :value) in tags.entries) {
    final content = [0, ...latin1.encode(key), 0, ...latin1.encode(value)];
    frames
      ..add(ascii.encode('TXXX'))
      ..add((ByteData(4)..setUint32(0, content.length)).buffer.asUint8List())
      ..add([0, 0])
      ..add(content);
  }

  if (frames.isEmpty) {
    return Uint8List(0);
  }

  // Its size in 7 bits a byte.
  final size = frames.length;
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    3,
    0,
    0,
    for (final shift in [21, 14, 7, 0]) (size >> shift) & 0x7f,
    ...frames.takeBytes(),
  ]);
}

/// A short tone as a WAV file, with [gain], and the ReplayGain [tags] where it has some.
TrackSource tone(
  Directory dir,
  int n, {
  double seconds = 4,
  TrackGain gain = TrackGain.none,
  Map<String, String> tags = const {},
}) => TrackSource(
  (File('${dir.path}/t$n.wav')..writeAsBytesSync(wav(n, seconds: seconds, tags: tags))).uri,
  gain: gain,
);

/// The loudest sample in each second of [file], raw samples as [MediaKitEngine]'s audioFile has them, at [sampleRate],
/// but at its edges, where one track's gain may still hold for the next.
List<int> loudestBySecond(File file, {int sampleRate = rate}) {
  final samples = ByteData.sublistView(file.readAsBytesSync());
  return [
    for (var start = 0; start + sampleRate * 2 <= samples.lengthInBytes; start += sampleRate * 2)
      [
        for (var i = start + sampleRate ~/ 2; i < start + sampleRate * 3 ~/ 2; i += 2)
          samples.getInt16(i, Endian.little).abs(),
      ].reduce(max),
  ];
}

/// The equalizer's ten bands, each at 0 dB but for [gains], or all at [all].
Map<int, double> bands(Map<int, double> gains, {double all = 0}) => {
  for (final frequency in [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]) frequency: gains[frequency] ?? all,
};

/// A tone's loudest sample with [decibels] of gain.
Matcher withGain(double decibels) => closeTo(loudness * pow(10, decibels / 20), loudness / 100);

/// Tracks over HTTP, as a media server gives them: `ok<n>` a tone of 4 s, `short<n>` one of 1 s and
/// `slow<n>` the tone of 4 s half a second late; `fail<n>` an error 500, as for a file the server
/// can't read; `json<n>` an error in JSON, which isn't audio; and `flaky<n>` the error while
/// [flakyFails], the tone after. `long<n>` is a tone of 20 s from its query's timeOffset on, in seconds, as a song the
/// server transcodes. Each comes as the server sends a song it transcodes as it goes, of no length told, which mpv
/// can't seek in. It keeps the paths asked of it in [requests], and their timeOffset in [offsets] (0 for none).
class TrackServer {
  TrackServer._(this._server) {
    _server.listen(_answer);
  }

  static Future<TrackServer> start() async => TrackServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final requests = <String>[];
  final offsets = <int>[];
  bool flakyFails = true;

  /// The timeOffsets of the requests for [name].
  List<int> offsetsOf(String name) => [
    for (final (i, path) in requests.indexed)
      if (path == '/$name') offsets[i],
  ];

  TrackSource track(String name) => TrackSource(url(name));

  /// With a query, as the media server's stream URLs have; from [from] on, a timeOffset too.
  Uri url(String name, {Duration from = Duration.zero}) => Uri.parse(
    'http://127.0.0.1:${_server.port}/$name?id=$name&u=a%20b&t=c%2Fd${from > Duration.zero ? '&timeOffset=${from.inSeconds}' : ''}',
  );

  Future<void> _answer(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    final n = int.parse(path.replaceAll(RegExp('[^0-9]'), ''));
    final offset = int.parse(request.uri.queryParameters['timeOffset'] ?? '0');
    requests.add(path);
    offsets.add(offset);

    if (path.startsWith('/slow')) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    if (path.startsWith('/fail') || (path.startsWith('/flaky') && flakyFails)) {
      response.statusCode = HttpStatus.internalServerError;
    } else if (path.startsWith('/json')) {
      response.headers.contentType = ContentType.json;
      response.write('{"error": "not found"}');
    } else {
      response.headers.contentType = ContentType('audio', 'wav');
      response.add(wav(n, seconds: path.startsWith('/short') ? 1 : (path.startsWith('/long') ? 20.0 - offset : 4)));
    }

    await response.close();
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late MediaKitEngine engine;
  late Directory dir;

  setUp(() {
    MediaKit.ensureInitialized();
    engine = MediaKitEngine(silent: true);
    dir = Directory.systemTemp.createTempSync('segue-engine');
  });
  tearDown(() async {
    await engine.dispose();
    dir.deleteSync(recursive: true);
  });

  test('opening at another track says that track, right away and later', () async {
    final tracks = [for (var i = 0; i < 3; i++) tone(dir, i)];
    await engine.open(tracks, index: 0, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // What the app does when another song of the album is picked while one plays:
    await engine.open(tracks, index: 2, position: Duration.zero, play: true);
    expect(engine.index, 2);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(engine.index, 2);
    expect(engine.playing, isTrue);
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test(
    'the equalizer changes as a track plays, which goes on from where it was, though its stream can\'t seek',
    () async {
      final server = await TrackServer.start();
      addTearDown(server.close);
      await engine.open([server.track('ok0')], index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // On, a band moved, and off.
      for (final gains in [
        bands({1000: 6}),
        bands({1000: 3}),
        const <int, double>{},
      ]) {
        final before = engine.position;
        await engine.setEqualizer(gains);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(engine.playing, isTrue);
        expect(engine.position, greaterThan(before + const Duration(milliseconds: 300)));
      }

      expect(server.requests, ['/ok0'], reason: 'never loaded again');
    },
    skip: hasLibmpv ? false : 'needs libmpv',
  );

  test('jumping and moving on by itself announce the new track', () async {
    final tracks = [tone(dir, 0, seconds: 1), tone(dir, 1), tone(dir, 2)];
    final changes = <int>[];
    final subscription = engine.changes.listen((_) => changes.add(engine.index));
    await engine.open(tracks, index: 0, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 1800)); // the first track ends
    expect(engine.index, 1);
    expect(changes, contains(1));
    await engine.jump(2);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.index, 2);
    expect(changes.last, 2);
    await subscription.cancel();
  }, skip: hasLibmpv ? false : 'needs libmpv');

  // A jump is what a tap in the queue does: that track, from its start, playing.

  test('a jump plays, even from paused', () async {
    final tracks = [for (var i = 0; i < 3; i++) tone(dir, i)];
    await engine.open(tracks, index: 0, position: Duration.zero, play: false);
    await engine.jump(2);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.index, 2);
    expect(engine.playing, isTrue);
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('a jump to the current track starts it over', () async {
    final tracks = [for (var i = 0; i < 2; i++) tone(dir, i, seconds: 20)];
    await engine.open(tracks, index: 0, position: const Duration(seconds: 15), play: true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await engine.jump(0);
    // Past the time the engine trusts the position it commanded over media_kit's.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(engine.index, 0);
    expect(engine.playing, isTrue);
    expect(engine.position, lessThan(const Duration(seconds: 8)));
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('after the last track ends, a jump plays the track picked', () async {
    final tracks = [for (var i = 0; i < 3; i++) tone(dir, i, seconds: 1)];
    await engine.open(tracks, index: 2, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // the queue ends
    await engine.jump(1);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.index, 1);
    expect(engine.playing, isTrue);
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('after the last track ends, a jump to it plays it again', () async {
    final tracks = [for (var i = 0; i < 3; i++) tone(dir, i, seconds: 1)];
    await engine.open(tracks, index: 2, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // the queue ends
    await engine.jump(2);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.index, 2);
    expect(engine.playing, isTrue);
  }, skip: hasLibmpv ? false : 'needs libmpv');

  group('heard', () {
    late File heard;
    late MediaKitEngine listened;

    setUp(() {
      heard = File('${dir.path}/heard.raw');
      listened = MediaKitEngine(audioFile: heard.path);
    });
    tearDown(() => listened.dispose());

    /// The same tone each time (a tone's loudest sample depends on its pitch), with [gain] and [tags].
    TrackSource track(
      int n, {
      double seconds = 1,
      TrackGain gain = TrackGain.none,
      Map<String, String> tags = const {},
    }) => TrackSource(
      (File('${dir.path}/heard$n.wav')..writeAsBytesSync(wav(0, seconds: seconds, tags: tags))).uri,
      gain: gain,
    );

    // These tracks play in a moment, their audio written as fast as mpv decodes it, but for the end of the last one,
    // which mpv may keep until the queue ends: the last a second longer, for the seconds heard to be whole.

    test(
      'each track plays with its gain, asked for as it loads: the one given, or its file\'s ReplayGain tags',
      () async {
        const tags = {'REPLAYGAIN_TRACK_GAIN': '-12.00 dB', 'REPLAYGAIN_ALBUM_GAIN': '-6.00 dB'};
        final tracks = [
          track(0, gain: const TrackGain(-12)),
          track(1, gain: const TrackGain(-6)),
          track(2),
          track(3, gain: const TrackGain.tagged(album: false), tags: tags),
          track(4, gain: const TrackGain.tagged(album: true), tags: tags),
          track(5, gain: const TrackGain.tagged(album: false)),
          track(6, gain: const TrackGain(-3), tags: tags),
          track(7, seconds: 2, gain: const TrackGain(3), tags: tags),
        ];
        await listened.open(tracks, index: 0, position: Duration.zero, play: true);
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(loudestBySecond(heard).take(8), [
          withGain(-12),
          withGain(-6),
          withGain(0),
          withGain(-12),
          withGain(-6),
          withGain(0), // no tags
          withGain(-3), // the gain given, whatever the tags say
          withGain(3),
        ]);
      },
    );

    test('a file\'s tags play with the preamp given, no louder than their peak lets them', () async {
      const gain = TrackGain.tagged(album: false, preamp: 4);
      final tracks = [
        track(0, gain: gain, tags: {'REPLAYGAIN_TRACK_GAIN': '-12.00 dB'}),
        track(1, gain: gain, tags: {'REPLAYGAIN_TRACK_GAIN': '-2.00 dB', 'REPLAYGAIN_TRACK_PEAK': '0.500000'}),
        track(2, seconds: 2, gain: gain, tags: {'REPLAYGAIN_TRACK_GAIN': '-2.00 dB'}),
      ];
      await listened.open(tracks, index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(loudestBySecond(heard).take(3), [
        withGain(-8),
        withGain(2), // under the 6 dB its peak lets it
        withGain(0), // where no peak is said, no louder than it is
      ]);
    });

    test('a new gain holds at once for the track that plays', () async {
      var gain = TrackGain.none;
      final file = File('${dir.path}/t0.wav')..writeAsBytesSync(wav(0, seconds: 2));
      final source = TrackSource.resolved(() => file.uri, gain: () => gain);
      await listened.open([source], index: 0, position: Duration.zero, play: false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      gain = const TrackGain(-12);
      await listened.updateGain();
      await listened.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(loudestBySecond(heard).take(1), [withGain(-12)]);
    });

    group('through the equalizer', () {
      /// A tone of [hertz], at [sampleRate].
      TrackSource tone(int n, double hertz, {double seconds = 1, int sampleRate = rate}) => TrackSource(
        (File(
          '${dir.path}/eq$n.wav',
        )..writeAsBytesSync(wav(0, hertz: hertz, seconds: seconds, sampleRate: sampleRate))).uri,
      );

      /// The loudest sample in each second, at the equalizer's sample rate.
      List<int> heardAt48kHz() => loudestBySecond(heard, sampleRate: 48000);

      // What FFmpeg's bands make of these tones, in dB, as the engine reckons it.

      test(
        'a band raises or lowers its frequencies, the whole lowered by as much as the bands raise the most',
        () async {
          await listened.setEqualizer(bands({63: 6, 1000: -6}));
          await listened.open(
            [tone(0, 63), tone(1, 1000), tone(2, 300, seconds: 2)],
            index: 0,
            position: Duration.zero,
            play: true,
          );
          await Future<void>.delayed(const Duration(seconds: 1));
          expect(heardAt48kHz().take(3), [
            withGain(0), // +6, and the whole -6
            withGain(-11.97),
            withGain(-6.17), // a little of each band
          ]);
        },
      );

      test('every band raised, the tracks play no louder than they were', () async {
        await listened.setEqualizer(bands({}, all: 12));
        await listened.open(
          [tone(0, 63), tone(1, 250), tone(2, 1000, seconds: 2)],
          index: 0,
          position: Duration.zero,
          play: true,
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        // Each a little under the loudest, some 4 kHz, which plays as loud as it was.
        expect(heardAt48kHz().take(3), [withGain(-1.46), withGain(-0.75), withGain(-0.62)]);
      });

      test('a track of 32 kHz plays with the band at its half, 16 kHz, which FFmpeg alone would make silent', () async {
        await listened.setEqualizer(bands({16000: 6}));
        await listened.open(
          [tone(0, 1000, seconds: 2, sampleRate: 32000)],
          index: 0,
          position: Duration.zero,
          play: true,
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(heardAt48kHz().take(1), [withGain(-5.97)]);
      });

      test('off, the tracks play as they are', () async {
        await listened.setEqualizer(bands({1000: -6}));
        await listened.setEqualizer(const {});
        await listened.open([tone(0, 1000, seconds: 2)], index: 0, position: Duration.zero, play: true);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(loudestBySecond(heard).take(1), [withGain(0)], reason: 'at the track\'s own sample rate');
      });
    });
  }, skip: hasLibmpv ? false : 'needs libmpv');

  // The player reports its position to the hub right after each of these: a position still at the
  // old place goes to the other devices, which then count from there.

  test('a seek shows in the position as soon as it returns', () async {
    await engine.open([tone(dir, 0)], index: 0, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await engine.seek(Duration.zero);
    expect(engine.position, lessThan(const Duration(milliseconds: 500)));
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('opening at a position shows it as soon as it returns', () async {
    await engine.open([tone(dir, 0)], index: 0, position: const Duration(seconds: 2), play: false);
    expect(engine.position.inMilliseconds, closeTo(2000, 200));
  }, skip: hasLibmpv ? false : 'needs libmpv');

  // Opened paused, as the app opens on the last playback, the track loads all the same, so that play
  // starts it at once.

  test('opened paused at a position, it plays from there', () async {
    await engine.open([tone(dir, 0), tone(dir, 1)], index: 1, position: const Duration(seconds: 2), play: false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.position.inMilliseconds, closeTo(2000, 200), reason: 'still there');
    expect(engine.playing, isFalse);
    await engine.play();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(engine.index, 1);
    expect(engine.playing, isTrue);
    expect(engine.position, greaterThan(const Duration(seconds: 2)));
    expect(engine.position, lessThan(const Duration(milliseconds: 3500)));
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('opened paused, a seek moves where it plays from', () async {
    await engine.open([tone(dir, 0)], index: 0, position: Duration.zero, play: false);
    await engine.seek(const Duration(seconds: 2));
    expect(engine.position.inMilliseconds, closeTo(2000, 200));
    await engine.play();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(engine.playing, isTrue);
    expect(engine.position, greaterThan(const Duration(seconds: 2)));
  }, skip: hasLibmpv ? false : 'needs libmpv');

  group('opened paused from the media server', () {
    late TrackServer server;

    setUp(() async => server = await TrackServer.start());
    tearDown(() => server.close());

    test('it is asked of the server at once, and play starts it from its place without asking again', () async {
      final tracks = [server.track('ok0'), server.track('ok1')];
      await engine.open(tracks, index: 1, position: const Duration(seconds: 2), play: false);
      expect(server.requests, contains('/ok1'));
      expect((engine.index, engine.playing), (1, false));
      expect(engine.position.inMilliseconds, closeTo(2000, 200));
      server.requests.clear();
      await engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.requests, isEmpty);
      expect(engine.playing, isTrue);
      expect(engine.position, greaterThan(const Duration(seconds: 2)));
      expect(engine.position, lessThan(const Duration(milliseconds: 3500)));
    });

    test('while it loads, a seek moves where it plays from, and play plays it from there once loaded', () async {
      final opening = engine.open([server.track('slow0')], index: 0, position: Duration.zero, play: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.seek(const Duration(seconds: 2));
      expect(engine.position.inMilliseconds, closeTo(2000, 200));
      await engine.play();
      await opening;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(engine.playing, isTrue);
      expect(engine.position, greaterThan(const Duration(seconds: 2)));
      expect(engine.position, lessThan(const Duration(milliseconds: 3500)));
    });

    test('while it loads, a jump plays the track picked from its start', () async {
      final tracks = [server.track('ok0'), server.track('slow1'), server.track('ok2')];
      final opening = engine.open(tracks, index: 1, position: const Duration(seconds: 2), play: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.jump(2);
      await opening;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(engine.index, 2);
      expect(engine.playing, isTrue);
      expect(engine.position, lessThan(const Duration(milliseconds: 1500)));
    });
  }, skip: hasLibmpv ? false : 'needs libmpv');

  // A song the media server transcodes as it goes comes with no length told, and mpv can't seek in it: the engine loads
  // it again, asking for it from the point sought (timeOffset).
  group('a stream that can\'t seek', () {
    late TrackServer server;

    setUp(() async => server = await TrackServer.start());
    tearDown(() => server.close());

    /// `long<n>`, which starts later when asked.
    TrackSource long(int n) =>
        TrackSource.resolved(() => server.url('long$n'), addressFrom: (from) async => server.url('long$n', from: from));

    test('a seek loads it again from there, and the position counts from the track\'s start', () async {
      await engine.open([long(0), long(1)], index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await engine.seek(const Duration(seconds: 10, milliseconds: 600));
      expect(server.offsetsOf('long0'), [0, 10], reason: 'the track again, from the second sought');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect((engine.index, engine.playing), (0, true));
      expect(engine.position, greaterThan(const Duration(seconds: 10)));
      expect(engine.position, lessThan(const Duration(seconds: 12)));
    });

    test('opened paused at a point, it loads it again to start there, and plays from there', () async {
      await engine.open([long(0)], index: 0, position: const Duration(seconds: 12), play: false);
      expect(server.offsets, [0, 12], reason: 'from its start, which can\'t seek, then from there');
      expect(engine.playing, isFalse);
      expect(engine.position.inMilliseconds, closeTo(12000, 300));
      await engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(engine.playing, isTrue);
      expect(engine.position, greaterThan(const Duration(seconds: 12)));
      expect(engine.position, lessThan(const Duration(seconds: 14)));
    });

    test('before where its stream starts, it loads it again from there, or from its start', () async {
      await engine.open([long(0)], index: 0, position: const Duration(seconds: 12), play: true);
      await engine.seek(const Duration(seconds: 3));
      await engine.seek(Duration.zero);
      expect(server.offsets, [0, 12, 3, 0]);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(engine.playing, isTrue);
      expect(engine.position, lessThan(const Duration(seconds: 2)));
    });

    test('repeating it, a stream that starts later starts over from the track\'s start', () async {
      await engine.setRepeat(Repeat.one);
      await engine.open([long(0)], index: 0, position: const Duration(seconds: 17), play: true);
      await Future<void>.delayed(const Duration(seconds: 3)); // through the 3 s left
      expect(server.offsets, [0, 17, 0]);
      expect(engine.index, 0);
      expect(engine.position, lessThan(const Duration(seconds: 2)));
    });

    test('a track that can\'t start later seeks in what mpv has of it', () async {
      await engine.open([server.track('long0')], index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await engine.seek(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.requests, ['/long0'], reason: 'asked once');
      expect(engine.position, greaterThan(const Duration(seconds: 2)));
      expect(engine.position, lessThan(const Duration(seconds: 4)));
    });
  }, skip: hasLibmpv ? false : 'needs libmpv');

  // mpv opens the next track's stream as the one before plays, so that it plays right after it, with no gap, however
  // late the media server answers.
  group('the next track', () {
    late TrackServer server;

    setUp(() async => server = await TrackServer.start());
    tearDown(() => server.close());

    /// The track [n] in the quality [quality] gives, as the second number of its name, as a media server's addresses
    /// have it.
    TrackSource track(int n, int Function() quality) => TrackSource.resolved(() => server.url('ok$n${quality()}'));

    test('is asked of the server as the one before plays, and plays from what came', () async {
      await engine.open([server.track('ok0'), server.track('slow1')], index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(server.requests, ['/ok0', '/slow1']);
      expect((engine.index, engine.playing), (0, true));
      await engine.jump(1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.requests, ['/ok0', '/slow1'], reason: 'not asked again');
      expect((engine.index, engine.playing), (1, true));
      expect(engine.position, greaterThan(Duration.zero), reason: 'playing already, though the server answers late');
    });

    test('a file isn\'t opened ahead, as it opens at once', () async {
      await engine.open([server.track('ok0'), tone(dir, 1)], index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await engine.jump(1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((engine.index, engine.playing, engine.failed), (1, true, false));
    });

    test('plays from the stream it gives as it loads, of another quality since it was opened, and the one after it is '
        'asked ahead in that quality', () async {
      var quality = 0;
      await engine.open(
        [for (var n = 1; n <= 3; n++) track(n, () => quality)],
        index: 0,
        position: Duration.zero,
        play: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      quality = 1; // as the phone goes over to mobile data
      await engine.jump(1);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.requests, ['/ok10', '/ok20', '/ok21', '/ok31']);
      expect((engine.index, engine.playing), (1, true));
      expect(engine.order, [0, 1, 2]);
      server.requests.clear();
      await engine.jump(2);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.requests, isEmpty, reason: 'opened ahead');
      expect((engine.index, engine.playing), (2, true));
    });

    test('asked ahead in another quality, it keeps its place in the play order and in the order unshuffled', () async {
      var quality = 0;
      await engine.setShuffle(true);
      await engine.open(
        [for (var n = 1; n <= 5; n++) track(n, () => quality)],
        index: 0,
        position: Duration.zero,
        play: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final order = engine.order;
      // Another track than the current one, which a jump would only start over, and not the last.
      final target = engine.index == 1 ? 2 : 1;
      quality = 1;
      await engine.jump(target);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.requests.last, '/ok${order[target + 1] + 1}1');
      expect(engine.index, target);
      expect(engine.order, order);
      await engine.setShuffle(false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.index, order[target]);
      expect(engine.order, [0, 1, 2, 3, 4]);
    });

    test('failing as it is asked ahead stops nothing: it fails as it is to play', () async {
      await engine.open([server.track('short0'), server.track('fail1')], index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.requests, ['/short0', '/fail1']);
      expect((engine.index, engine.failed, engine.playing), (0, false, true));
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect((engine.index, engine.failed, engine.playing), (1, true, false));
    });
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('after a jump, a seek while the track loads goes there once it has', () async {
    final server = await TrackServer.start();
    addTearDown(server.close);
    // Not the next track, which would be there already, opened ahead.
    final tracks = [server.track('ok0'), server.track('ok1'), server.track('slow2')];
    await engine.open(tracks, index: 0, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await engine.jump(2);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(engine.position, Duration.zero, reason: 'the start of the track loading, not the one before\'s place');
    await engine.seek(const Duration(seconds: 2));
    expect(engine.position, const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 1000)); // it loads after half a second
    expect((engine.index, engine.playing), (2, true));
    expect(engine.position, greaterThan(const Duration(seconds: 2)));
    expect(engine.position, lessThan(const Duration(milliseconds: 3500)));
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('a new track, by a jump or moving on by itself, announces itself at its start', () async {
    final tracks = [tone(dir, 0, seconds: 1), tone(dir, 1), tone(dir, 2)];
    final announced = <int, Duration>{}; // track → the position when it was first announced
    final subscription = engine.changes.listen((_) => announced.putIfAbsent(engine.index, () => engine.position));
    await engine.open(tracks, index: 0, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 2200)); // moves on to track 1 at 1 s
    await engine.jump(2);
    expect(engine.position, lessThan(const Duration(milliseconds: 500)));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(announced.keys, containsAll([1, 2]));
    expect(announced[1], lessThan(const Duration(milliseconds: 500)));
    expect(announced[2], lessThan(const Duration(milliseconds: 500)));
    await subscription.cancel();
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('shuffle keeps the current track playing, and off brings back the order it had', () async {
    final tracks = [for (var i = 0; i < 5; i++) tone(dir, i)];
    await engine.open(tracks, index: 2, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(engine.order, [0, 1, 2, 3, 4]);
    await engine.setShuffle(true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.shuffle, isTrue);
    expect([...engine.order]..sort(), [0, 1, 2, 3, 4]);
    expect(engine.order[engine.index], 2, reason: 'the same track, still current');
    expect(engine.playing, isTrue);
    expect(engine.position, greaterThan(const Duration(milliseconds: 500)), reason: 'not started over');
    await engine.setShuffle(false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.order, [0, 1, 2, 3, 4]);
    expect(engine.index, 2);
  }, skip: hasLibmpv ? false : 'needs libmpv');

  group('tracks added', () {
    test('play next, right after the current one, or after the last, the current one playing on', () async {
      final server = await TrackServer.start();
      addTearDown(server.close);
      await engine.open(
        [server.track('short0'), server.track('short1')],
        index: 0,
        position: Duration.zero,
        play: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.requests, ['/short0', '/short1'], reason: 'the next track asked ahead');
      server.requests.clear();
      expect(await engine.add([server.track('short2')], next: false), 2);
      expect(await engine.add([server.track('short3'), server.track('short4')], next: true), 1);
      expect(engine.order, [0, 1, 2, 3, 4]);
      expect(engine.index, 0);
      expect(engine.playing, isTrue);
      await Future<void>.delayed(const Duration(seconds: 5)); // to the end of the queue
      expect(server.requests, ['/short3', '/short4', '/short1', '/short2']);
      expect(engine.index, 4);
    }, skip: hasLibmpv ? false : 'needs libmpv');

    test('never take the current track elsewhere, or back to its start, even for a moment', () async {
      final tracks = [for (var i = 0; i < 3; i++) tone(dir, i, seconds: 20)];
      await engine.open(tracks, index: 1, position: const Duration(seconds: 10), play: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final told = <(int, Duration)>[];
      final subscription = engine.changes.listen((_) => told.add((engine.order[engine.index], engine.position)));
      await engine.add([tone(dir, 3), tone(dir, 4)], next: true);
      await engine.add([tone(dir, 5)], next: false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(told, isNotEmpty);
      expect(
        told,
        everyElement(predicate<(int, Duration)>((told) => told.$1 == 1 && told.$2 > const Duration(seconds: 10))),
      );
      await subscription.cancel();
    }, skip: hasLibmpv ? false : 'needs libmpv');

    test('shuffled, play next all the same, and go where they would have unshuffled as shuffle goes off', () async {
      for (var round = 0; round < 3; round++) {
        final tracks = [for (var i = 0; i < 6; i++) tone(dir, i, seconds: 20)];
        await engine.setShuffle(true);
        await engine.open(tracks, index: 2, position: const Duration(seconds: 3), play: true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final current = engine.index;
        expect(await engine.add([tone(dir, 6), tone(dir, 7)], next: true), 3);
        expect(await engine.add([tone(dir, 8)], next: false), 8);
        expect(engine.index, current);
        expect(engine.order.sublist(current, current + 3), [2, 3, 4], reason: 'the current track, then those added');
        expect(engine.order.last, 8);

        final told = <(int, Duration)>[];
        final subscription = engine.changes.listen((_) => told.add((engine.order[engine.index], engine.position)));
        await engine.setShuffle(false);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(engine.order, [0, 1, 2, 3, 4, 5, 6, 7, 8]);
        expect(engine.index, 2);
        expect(engine.playing, isTrue);
        expect(
          told,
          everyElement(predicate<(int, Duration)>((told) => told.$1 == 2 && told.$2 > const Duration(seconds: 3))),
        );
        await subscription.cancel();
      }
    }, skip: hasLibmpv ? false : 'needs libmpv');
  });

  group('tracks moved and removed', () {
    test('the queue plays in its new order, the current track playing on', () async {
      final server = await TrackServer.start();
      addTearDown(server.close);
      await engine.open(
        [for (var i = 0; i < 4; i++) server.track('short$i')],
        index: 0,
        position: Duration.zero,
        play: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.requests, ['/short0', '/short1'], reason: 'the next track asked ahead');
      server.requests.clear();
      expect(await engine.move(3, 1), (from: 3, to: 1));
      expect(await engine.remove(2), 2);
      expect(engine.order, [0, 1, 2]);
      expect(engine.index, 0);
      expect(engine.playing, isTrue);
      await Future<void>.delayed(const Duration(seconds: 4)); // to the end of the queue
      expect(server.requests, ['/short3', '/short2']);
      expect(engine.index, 2);
    }, skip: hasLibmpv ? false : 'needs libmpv');

    test('never take the current track elsewhere, or back to its start, even for a moment', () async {
      final tracks = [for (var i = 0; i < 5; i++) tone(dir, i, seconds: 20)];
      await engine.open(tracks, index: 2, position: const Duration(seconds: 10), play: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // The current track's place after each change: a track before it to the end, then the first out, then the current
      // track itself moved down. Unshuffled, that is its place in the order unshuffled too, by which the engine tells the
      // current track while it moves tracks: in mpv's playlist it may be in between for a moment.
      final places = [2, 1, 0, 2];
      var step = 0;
      final told = <(int, int, Duration)>[];
      final subscription = engine.changes.listen((_) => told.add((step, engine.order[engine.index], engine.position)));
      step = 1;
      await engine.move(0, 4);
      step = 2;
      expect(await engine.remove(0), 0);
      step = 3;
      await engine.move(0, 2);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.index, 2);
      expect(engine.playing, isTrue);
      expect(told, isNotEmpty);

      for (final (step, track, position) in told) {
        expect(track, isIn([places[step - 1], places[step]]), reason: 'in step $step');
        expect(position, greaterThan(const Duration(seconds: 10)), reason: 'in step $step');
      }

      await subscription.cancel();
    }, skip: hasLibmpv ? false : 'needs libmpv');

    test('shuffled, a move changes the play order alone, which shuffle going off forgets', () async {
      final tracks = [for (var i = 0; i < 6; i++) tone(dir, i, seconds: 20)];
      await engine.setShuffle(true);
      await engine.open(tracks, index: 2, position: const Duration(seconds: 3), play: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final other = engine.index == 5 ? 4 : 5;
      final moved = engine.order[other];
      expect(await engine.move(other, 0), isNull);
      expect(engine.order.first, moved);
      expect(engine.order[engine.index], 2, reason: 'the same track, still current');

      // A removal takes the track out of the order unshuffled too.
      final removed = engine.order[engine.index == 1 ? 2 : 1];
      expect(await engine.remove(engine.index == 1 ? 2 : 1), removed);
      expect([...engine.order]..sort(), [0, 1, 2, 3, 4]);
      await engine.setShuffle(false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.order, [0, 1, 2, 3, 4]);
      expect(engine.index, removed < 2 ? 1 : 2);
      expect(engine.playing, isTrue);
      expect(engine.position, greaterThan(const Duration(seconds: 3)));
    }, skip: hasLibmpv ? false : 'needs libmpv');

    test('the current track stays, and a place past the queue changes nothing', () async {
      final tracks = [for (var i = 0; i < 3; i++) tone(dir, i, seconds: 20)];
      await engine.open(tracks, index: 1, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await engine.remove(1), -1);
      expect(await engine.remove(3), -1);
      expect(await engine.move(3, 0), isNull);
      expect(await engine.move(0, 3), isNull);
      expect(engine.order, [0, 1, 2]);
      expect(engine.index, 1);
    }, skip: hasLibmpv ? false : 'needs libmpv');
  });

  test('shuffle stays on for the tracks opened next', () async {
    final tracks = [for (var i = 0; i < 8; i++) tone(dir, i)];
    await engine.setShuffle(true);
    await engine.open(tracks, index: 3, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(engine.shuffle, isTrue);
    expect(engine.order[engine.index], 3);
    expect(engine.order, isNot([0, 1, 2, 3, 4, 5, 6, 7])); // 1 in 40320 to be so by chance
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('repeat one starts the track over, and says so', () async {
    // With the audio sent nowhere, mpv goes through a track faster than it lasts: this one, of 2 s,
    // starts over after about 1.3 s.
    final tracks = [tone(dir, 0, seconds: 2), tone(dir, 1)];
    await engine.setRepeat(Repeat.one);
    expect(engine.repeat, Repeat.one);
    final opened = DateTime.now();
    final restarts = <Duration>[];
    final subscription = engine.changes.listen((_) {
      if (DateTime.now().difference(opened) > const Duration(milliseconds: 400)) {
        restarts.add(engine.position);
      }
    });
    await engine.open(tracks, index: 0, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(engine.index, 0);
    expect(restarts, contains(lessThan(const Duration(milliseconds: 500))));
    await subscription.cancel();
  }, skip: hasLibmpv ? false : 'needs libmpv');

  test('repeat all goes back to the first track after the last', () async {
    final tracks = [tone(dir, 0, seconds: 1), tone(dir, 1, seconds: 1)];
    await engine.setRepeat(Repeat.all);
    await engine.open(tracks, index: 1, position: Duration.zero, play: true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(engine.index, 0);
    expect(engine.playing, isTrue);
  }, skip: hasLibmpv ? false : 'needs libmpv');

  // mpv moves on from a track it can't load, and from the next, through the whole queue, in a moment:
  // as when the media server can't read its disk.
  group('a track that fails to load', () {
    late TrackServer server;

    setUp(() async => server = await TrackServer.start());
    tearDown(() => server.close());

    test('stops the engine on it, paused, and says so', () async {
      final tracks = [server.track('ok0'), server.track('fail1'), server.track('ok2')];
      final changes = <(int, bool)>[];
      final subscription = engine.changes.listen((_) => changes.add((engine.index, engine.failed)));
      await engine.open(tracks, index: 1, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(engine.index, 1);
      expect(engine.failed, isTrue);
      expect(engine.playing, isFalse);
      expect(changes.last, (1, true));
      await subscription.cancel();
    });

    test('fails too when what the server sends isn\'t audio', () async {
      // mpv tells of this one after it has moved on to the next track.
      await engine.open([server.track('json0'), server.track('ok1')], index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(engine.index, 0);
      expect(engine.failed, isTrue);
      expect(engine.playing, isFalse);
    });

    test('stops on the last track too', () async {
      await engine.open([server.track('ok0'), server.track('fail1')], index: 1, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(engine.index, 1);
      expect(engine.failed, isTrue);
      expect(engine.playing, isFalse);
    });

    test('play tries it again, and a jump plays another', () async {
      final tracks = [server.track('ok0'), server.track('fail1'), server.track('ok2')];
      await engine.open(tracks, index: 1, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      server.requests.clear();
      await engine.play();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(server.requests, contains('/fail1'));
      expect(engine.index, 1);
      expect(engine.failed, isTrue);
      expect(engine.playing, isFalse);
      await engine.jump(2);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(engine.index, 2);
      expect(engine.failed, isFalse);
      expect(engine.playing, isTrue);
    });

    test('opening at a position on it returns at once, without playing', () async {
      final tracks = [server.track('ok0'), server.track('fail1'), server.track('ok2')];
      // The engine waits for the track to load before it seeks: for 10 s, if nothing told it of the
      // failure.
      await engine
          .open(tracks, index: 1, position: const Duration(seconds: 30), play: true)
          .timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(engine.index, 1);
      expect(engine.failed, isTrue);
      expect(engine.playing, isFalse);
    });

    // As when the app opens on the last playback: no one asked it to play.
    test('opened paused, it is asked of the server at once, but fails only once play tries it again', () async {
      final tracks = [server.track('ok0'), server.track('fail1'), server.track('ok2')];
      final told = <bool>[];
      final subscription = engine.changes.listen((_) => told.add(engine.failed));
      await engine.open(tracks, index: 1, position: const Duration(seconds: 30), play: false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.requests, contains('/fail1'));
      expect(engine.failed, isFalse);
      expect(told, everyElement(isFalse));
      expect((engine.index, engine.position, engine.playing), (1, const Duration(seconds: 30), false));
      server.requests.clear();
      await engine.play();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(server.requests, contains('/fail1'));
      expect(engine.failed, isTrue);
      expect(told.last, isTrue);
      expect((engine.index, engine.position, engine.playing), (1, const Duration(seconds: 30), false));
      await subscription.cancel();
    });

    test('opened paused, a jump from its failure plays the track picked, with nothing to tell', () async {
      final tracks = [server.track('ok0'), server.track('fail1'), server.track('ok2')];
      final told = <bool>[];
      final subscription = engine.changes.listen((_) => told.add(engine.failed));
      await engine.open(tracks, index: 1, position: Duration.zero, play: false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await engine.jump(2);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((engine.index, engine.failed, engine.playing), (2, false, true));
      expect(told, everyElement(isFalse));
      await subscription.cancel();
    });

    test('once the server gives it, play goes on from its place', () async {
      final tracks = [server.track('ok0'), server.track('flaky1'), server.track('ok2')];
      await engine.open(tracks, index: 1, position: const Duration(seconds: 2), play: false);
      await engine.play();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(engine.failed, isTrue);
      server.flakyFails = false; // the server reads its disk again
      await engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(engine.failed, isFalse);
      expect(engine.index, 1);
      expect(engine.playing, isTrue);
      expect(engine.position, greaterThan(const Duration(seconds: 2)));
      expect(engine.position, lessThan(const Duration(milliseconds: 3500)));
    });

    test('but one that loads plays to its end and moves on, as before', () async {
      await engine.open([server.track('short0'), server.track('ok1')], index: 0, position: Duration.zero, play: true);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      expect(engine.index, 1);
      expect(engine.failed, isFalse);
      expect(engine.playing, isTrue);
    });
  }, skip: hasLibmpv ? false : 'needs libmpv');
}
