import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';

import '../server/models.dart';
import '../server/server.dart';
import 'player.dart';

final _log = Logger('PlayCounter');

/// Counts the plays of what this device's player plays toward the user's most played on the media
/// server (MediaServer.scrobble): here, on the device that plays a song, whichever device commands it.
/// A song counts once it has played long enough, its playing time added up across pauses and seeks (a
/// seek forward plays nothing), so that a song moved to another device halfway doesn't count on both.
class PlayCounter {
  PlayCounter(this._player, this._api) {
    _player.addListener(_changed);
  }

  final PlayerController _player;
  final MediaServer _api;
  _Listen? _listen;
  Timer? _timer;

  /// The most a song plays before its play counts, however long it is.
  static const countAfter = Duration(minutes: 4);

  /// Up to how far into a song it has started over, which, once its play counted, starts another.
  static const startGrace = Duration(seconds: 3);

  /// How long [song] plays before its play counts: half of it, or [countAfter] for a longer one, as
  /// Last.fm counts, and with it most apps that scrobble; [countAfter] when its length is unknown. One
  /// of 30 seconds or less never counts: null.
  static Duration? playedEnough(Song song) {
    final duration = song.duration;

    if (duration == null) {
      return countAfter;
    }

    if (duration <= const Duration(seconds: 30)) {
      return null;
    }

    final half = duration ~/ 2;

    return half < countAfter ? half : countAfter;
  }

  /// A song's play starts when another song takes its place, and when it starts over (repeated, or
  /// back to its start) once counted.
  void _changed() {
    final now = clock.now();
    final song = _player.current;
    var listen = _listen;
    _timer?.cancel();
    listen?.pause(now);

    if (song == null) {
      _listen = null;
      return;
    }

    if (listen == null || !identical(listen.song, song) || (listen.counted && _player.position < startGrace)) {
      listen = _listen = _Listen(song);
    }

    final enough = playedEnough(song);

    if (!_player.playing || listen.counted || enough == null) {
      return;
    }

    listen.play(now);

    final left = enough - listen.played;
    _timer = Timer(left.isNegative ? Duration.zero : left, _count);
  }

  void _count() {
    final listen = _listen;

    if (listen == null || listen.counted) {
      return;
    }

    listen.counted = true;
    // Refused, or failing: that play goes uncounted (one out of reach the downloads keep).
    unawaited(
      _api
          .scrobble(listen.song.id, time: listen.start!)
          .catchError((Object e) => _log.warning('play of ${listen.song.title} not counted', e)),
    );
  }

  void dispose() {
    _timer?.cancel();
    _player.removeListener(_changed);
  }
}

/// A song's play on this device, from when it becomes the current song to when another takes its place
/// or it starts over.
class _Listen {
  _Listen(this.song);

  final Song song;

  /// When it first played; null until it does.
  DateTime? start;

  /// How long it played, up to [since].
  Duration played = Duration.zero;

  /// Since when it plays; null while it doesn't.
  DateTime? since;

  bool counted = false;

  void play(DateTime now) {
    start ??= now;
    since = now;
  }

  void pause(DateTime now) {
    if (since case final playing?) {
      played += now.difference(playing);
      since = null;
    }
  }
}
