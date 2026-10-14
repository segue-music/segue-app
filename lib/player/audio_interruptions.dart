import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:logging/logging.dart';

import 'player.dart';

final _log = Logger('AudioInterruptions');

/// What the system does to this device's playback, on iOS and Android: a call or another app's audio interrupts it,
/// and the car or the headphones going away stops it. libmpv knows of neither: without this the player would go on
/// "playing" in silence through a call, or carry on out of the phone's speaker after leaving the car.
///
/// On Android the audio also goes to one app at a time (the audio focus): an app asks for it as it plays, and the one
/// that had it is told to stop. libmpv doesn't ask, so without [activate] another app's music played on alongside.
class AudioInterruptions {
  AudioInterruptions(Stream<AudioInterruptionEvent> interruptions, Stream<void> becomingNoisy, {this._activate}) {
    interruptions.listen(_interrupted);
    becomingNoisy.listen((_) => _pause());
  }

  /// Sets the app's audio session up for music, on iOS and Android: calls interrupt it, and on iOS it keeps playing in
  /// the background and with the silent switch on. Null elsewhere, or when it can't.
  static Future<AudioInterruptions?> start() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return null;
    }

    try {
      final session = await AudioSession.instance;

      await session.configure(const AudioSessionConfiguration.music());

      return AudioInterruptions(
        session.interruptionEventStream,
        session.becomingNoisyEventStream,
        // iOS's session is active as the music plays; Android's audio focus is asked for.
        activate: Platform.isAndroid ? session.setActive : null,
      );
    } on Object catch (e) {
      _log.warning('audio session unavailable', e);
      return null;
    }
  }

  /// Takes the audio from the other apps (true), saying whether the system gave it, or gives it back (false):
  /// audio_session's `setActive`.
  final Future<bool> Function(bool active)? _activate;

  PlayerController? _player;

  // Whether the player was playing at its last change, so that the audio is asked for as it starts.
  bool _playing = false;

  // Whether an interruption paused the music, which then plays again when it ends.
  bool _resume = false;

  /// Acts on [player], this device's; null (signed out, or the app closed) on nothing, the audio given back.
  void attach(PlayerController? player) {
    _player?.removeListener(_playerChanged);
    _player = player;
    _playing = false;
    _resume = false;

    if (player == null) {
      unawaited(_setActive(false));

      return;
    }

    player.addListener(_playerChanged);
    _playerChanged();
  }

  void _playerChanged() {
    final player = _player;
    final playing = player != null && player.playing;

    if (player != null && playing && !_playing) {
      unawaited(_takeAudio(player));
    }

    _playing = playing;
  }

  Future<void> _takeAudio(PlayerController player) async {
    final granted = await _setActive(true);

    if (granted != false || player != _player) {
      return;
    }

    // Android refuses it during a call. audio_session keeps a refused request as though it were held, and doesn't ask
    // again while it does: giving it back makes the next play ask.
    unawaited(_setActive(false));

    if (player.playing) {
      unawaited(player.pause());
    }
  }

  // Null where the platform has no audio to ask for, or the request failed.
  Future<bool?> _setActive(bool active) async {
    final activate = _activate;

    if (activate == null) {
      return null;
    }

    try {
      return await activate(active);
    } on Object catch (e) {
      _log.warning('audio session not ${active ? 'activated' : 'deactivated'}', e);
      return null;
    }
  }

  void _interrupted(AudioInterruptionEvent event) {
    final player = _player;

    if (player == null) {
      return;
    }

    if (event.begin) {
      // The system lowers our volume itself (Android from 8 on), and raises it again.
      if (event.type == AudioInterruptionType.duck) {
        return;
      }

      final playing = player.playing;

      _pause();
      _resume = playing;
    } else {
      // A pause is the system saying to resume; unknown, that we shouldn't.
      if (_resume && event.type == AudioInterruptionType.pause) {
        unawaited(player.play());
      }

      _resume = false;
    }
  }

  void _pause() {
    _resume = false;
    final player = _player;

    if (player != null && player.playing) {
      unawaited(player.pause());
    }
  }
}
