import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'player.dart';

/// Pauses this device's player after a while, or as the song that plays ends: to fall asleep to music. Over the last
/// [fade] of a while the music gets quieter, down to nothing, and it plays as loud as before as it plays again. Only this
/// device's: the protocol has no timer for another device to set, nor to show.
class SleepTimer extends ChangeNotifier {
  SleepTimer(this._player);

  final PlayerController _player;

  /// How long the music fades out for, before a while is up.
  static const fade = Duration(seconds: 30);

  /// The whiles it offers.
  static const whiles = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(hours: 1),
  ];

  DateTime? _endsAt;
  bool _untilSongEnds = false;
  Timer? _ticks;
  StreamSubscription<void>? _songEnded;

  // The minutes left that the listeners were last told of.
  int? _minutesTold;

  // As the music fades out: the volume it had before, which it gets back, and the one the fade last set, which the next
  // launches don't keep. A volume the user picks meanwhile stays, and the music fades no more ([_faded]).
  int? _volumeBefore;
  int? _volumeSet;
  bool _faded = false;

  /// When it pauses the music; null where it doesn't, or does as the song ends ([untilSongEnds]).
  DateTime? get endsAt => _endsAt;

  /// Whether it pauses the music as the song that plays ends.
  bool get untilSongEnds => _untilSongEnds;

  bool get on => _endsAt != null || _untilSongEnds;

  /// How many minutes are left until it pauses the music, rounded up, so that the last one is 1; null where it isn't
  /// counting down.
  int? get minutesLeft => switch (_endsAt) {
    final endsAt? => (endsAt.difference(clock.now()).inMilliseconds / Duration.millisecondsPerMinute).ceil(),
    null => null,
  };

  /// Pauses the music in [after], instead of as it would before.
  void start(Duration after) {
    _reset();
    _endsAt = clock.now().add(after);
    _minutesTold = minutesLeft;
    _ticks = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _player.addListener(_playerChanged);
    notifyListeners();
  }

  /// Pauses the music as the song that plays ends, instead of as it would before.
  void startUntilSongEnds() {
    _reset();
    _untilSongEnds = true;
    _songEnded = _player.songEnded.listen((_) => _songEndedNow());
    _player.addListener(_playerChanged);
    notifyListeners();
  }

  /// Lets the music play on, as loud as before.
  void cancel() {
    _reset();
    notifyListeners();
  }

  /// The player stopped (another device took the music, say): there is nothing left to pause.
  void _playerChanged() {
    if (_player.queue.isEmpty) {
      cancel();
    }
  }

  void _tick() {
    final left = _endsAt!.difference(clock.now());

    if (left <= Duration.zero) {
      unawaited(_end());
      return;
    }

    if (left < fade) {
      _fadeOut(left);
    }

    if (minutesLeft != _minutesTold) {
      _minutesTold = minutesLeft;
      notifyListeners();
    }
  }

  /// The music as loud, of what it was as it started fading out, as [left] is of [fade].
  void _fadeOut(Duration left) {
    if (_volumeSet case final set? when _player.volume != set) {
      _faded = true;
      _volumeBefore = _volumeSet = null;
    }

    if (_faded || !_player.playing) {
      return;
    }

    final before = _volumeBefore ??= _player.volume;
    final volume = (before * left.inMilliseconds / fade.inMilliseconds).round();

    if (volume != _volumeSet) {
      _volumeSet = volume;
      unawaited(_player.setVolume(volume, keep: false));
    }
  }

  /// The while is up: the music pauses, then gets its volume back, for when it plays again.
  Future<void> _end() async {
    final before = _fadedFrom;

    _stop();
    notifyListeners();

    if (_player.playing) {
      await _player.pause();
    }

    if (before != null) {
      await _player.setVolume(before);
    }
  }

  /// The song ended: the next one, which started, pauses at its start, from where play goes on.
  Future<void> _songEndedNow() async {
    _stop();
    notifyListeners();

    if (_player.playing) {
      await _player.pause();
      await _player.seek(Duration.zero);
    }
  }

  /// Stops, the music as loud as before, should it have faded.
  void _reset() {
    final before = _fadedFrom;

    _stop();

    if (before != null) {
      unawaited(_player.setVolume(before));
    }
  }

  /// The volume the music had before it faded, where it faded, and the user picked none since.
  int? get _fadedFrom => _volumeSet != null && _player.volume == _volumeSet ? _volumeBefore : null;

  void _stop() {
    _player.removeListener(_playerChanged);
    _ticks?.cancel();
    _ticks = null;
    unawaited(_songEnded?.cancel());
    _songEnded = null;
    _endsAt = null;
    _untilSongEnds = false;
    _minutesTold = null;
    _volumeBefore = _volumeSet = null;
    _faded = false;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
