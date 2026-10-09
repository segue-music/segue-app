import 'dart:async';

import 'package:clock/clock.dart';
import 'package:segue/player/engine.dart';
import 'package:segue/segue/protocol.dart';

/// An engine with no audio: a queue and a clock, like the real one. Its clock is [clock], so that a test
/// in fake time (fake_async) plays in it.
class FakeEngine implements AudioEngine {
  final _changes = StreamController<void>.broadcast(sync: true);

  /// The tracks open got, and their streams as they were then, from the start: those once open returns.
  List<TrackSource> opened = [];
  List<Uri> tracks = [];
  int _index = 0;
  bool _playing = false;
  int _volume = 100;
  List<int> _order = [];
  Repeat _repeat = Repeat.off;
  bool _shuffle = false;
  Duration _position = Duration.zero;
  DateTime _since = clock.now();
  bool _failed = false;

  /// The current track's gain, as [updateGain] last asked it; null before it did.
  TrackGain? gain;

  /// The equalizer's gains, as [setEqualizer] last set them; null before it did.
  Map<int, double>? equalizer;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  bool get playing => _playing;

  @override
  int get index => _index;

  @override
  Duration get position => _playing ? _position + clock.now().difference(_since) : _position;

  @override
  int get volume => _volume;

  @override
  List<int> get order => _order;

  @override
  Repeat get repeat => _repeat;

  @override
  bool get shuffle => _shuffle;

  @override
  bool get failed => _failed;

  /// As when the current track fails to load: the engine stops on it, paused.
  void fail() {
    _failed = true;
    _seek(Duration.zero);
    _playing = false;
    _changes.add(null);
  }

  @override
  Future<void> open(
    List<TrackSource> tracks, {
    required int index,
    required Duration position,
    required bool play,
  }) async {
    _failed = false;
    opened = tracks;
    _order = [for (var i = 0; i < tracks.length; i++) i];
    _index = index;

    if (_shuffle) {
      _shuffleOrder();
    }

    _seek(position);
    _playing = play;
    _changes.add(null);
    // Last, so that the rest changes at once, as before the tracks' streams were asked for.
    this.tracks = [for (final track in tracks) (await track.address(Duration.zero))!];
  }

  @override
  Future<void> setRepeat(Repeat mode) async {
    _repeat = mode;
    _changes.add(null);
  }

  @override
  Future<void> setShuffle(bool on) async {
    if (on == _shuffle) {
      return;
    }

    _shuffle = on;

    if (on) {
      _shuffleOrder();
    } else if (_order.isNotEmpty) {
      _index = _order[_index];
      _order = [for (var i = 0; i < _order.length; i++) i];
    }

    _changes.add(null);
  }

  /// A predictable shuffle: the current track first, then the others backwards.
  void _shuffleOrder() {
    if (_order.isEmpty) {
      return;
    }

    final current = _order[_index];
    _order = [current, ..._order.reversed.where((track) => track != current)];
    _index = 0;
  }

  @override
  Future<void> play() async => _setPlaying(true);

  @override
  Future<void> pause() async => _setPlaying(false);

  @override
  Future<void> stop() async {
    _failed = false;
    opened = [];
    tracks = [];
    _order = [];
    _index = 0;
    _seek(Duration.zero);
    _playing = false;
    _changes.add(null);
  }

  @override
  Future<void> jump(int index) async {
    _failed = false;
    _index = index;
    _seek(Duration.zero);
    _playing = true;
    _changes.add(null);
  }

  @override
  Future<void> seek(Duration position) async => _seek(position); // like media_kit: not a change

  @override
  Future<void> setVolume(int volume) async {
    _volume = volume;
    _changes.add(null);
  }

  @override
  Future<void> updateGain() async => gain = opened.isEmpty ? null : opened[_order[_index]].gain();

  @override
  Future<void> setEqualizer(Map<int, double> gains) async => equalizer = gains;

  @override
  Future<void> dispose() => _changes.close();

  void _setPlaying(bool playing) {
    _failed &= !playing; // play tries the track again
    _seek(position);
    _playing = playing;
    _changes.add(null);
  }

  void _seek(Duration position) {
    _position = position;
    _since = clock.now();
  }
}
