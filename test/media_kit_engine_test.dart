// MediaKitEngine on the real libmpv, with the audio sent nowhere. Pins media_kit behaviour the app
// depends on, so that an upgrade that changes it shows up here. Needs libmpv (the dev image has it).
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

/// A short tone as a WAV file's bytes.
Uint8List wav(int n, {double seconds = 4}) {
  const rate = 8000;
  final samples = (rate * seconds).round();
  final data = ByteData(44 + samples * 2);

  void text(int offset, String s) => s.codeUnits.asMap().forEach((i, c) => data.setUint8(offset + i, c));

  text(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  text(8, 'WAVEfmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);

  for (var i = 0; i < samples; i++) {
    data.setInt16(44 + i * 2, (sin(2 * pi * (300 + 100 * n) * i / rate) * 8000).round(), Endian.little);
  }

  return data.buffer.asUint8List();
}

/// A short tone as a WAV file.
Uri tone(Directory dir, int n, {double seconds = 4}) =>
    (File('${dir.path}/t$n.wav')..writeAsBytesSync(wav(n, seconds: seconds))).uri;

/// Tracks over HTTP, as a media server gives them: `ok<n>` a tone of 4 s and `short<n>` one of 1 s;
/// `fail<n>` an error 500, as for a file the server can't read; `json<n>` an error in JSON, which
/// isn't audio; and `flaky<n>` the error while [flakyFails], the tone after. It keeps the paths asked
/// of it in [requests].
class TrackServer {
  TrackServer._(this._server) {
    _server.listen(_answer);
  }

  static Future<TrackServer> start() async => TrackServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final requests = <String>[];
  bool flakyFails = true;

  /// With a query, as the media server's stream URLs have, which mpv's log must give back as is.
  Uri track(String name) => Uri.parse('http://127.0.0.1:${_server.port}/$name?id=$name&u=a%20b&t=c%2Fd');

  Future<void> _answer(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    final n = int.parse(path.replaceAll(RegExp('[^0-9]'), ''));
    requests.add(path);

    if (path.startsWith('/fail') || (path.startsWith('/flaky') && flakyFails)) {
      response.statusCode = HttpStatus.internalServerError;
    } else if (path.startsWith('/json')) {
      response.headers.contentType = ContentType.json;
      response.write('{"error": "not found"}');
    } else {
      response.headers.contentType = ContentType('audio', 'wav');
      response.add(wav(n, seconds: path.startsWith('/short') ? 1 : 4));
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

  // Opened paused, as the app opens on the last playback, the track loads only when it plays.

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

    test('opened paused, it is asked of the server, and fails, only when it plays: in its place', () async {
      final tracks = [server.track('ok0'), server.track('fail1'), server.track('ok2')];
      await engine.open(tracks, index: 1, position: const Duration(seconds: 30), play: false);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(server.requests, isEmpty);
      expect(engine.failed, isFalse);
      expect((engine.index, engine.position, engine.playing), (1, const Duration(seconds: 30), false));
      await engine.play();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(server.requests, contains('/fail1'));
      expect(engine.failed, isTrue);
      expect((engine.index, engine.position, engine.playing), (1, const Duration(seconds: 30), false));
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
