import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../segue/protocol.dart';

/// What [PlayerController] needs from an audio backend. [MediaKitEngine] is the real one; the tests
/// use a fake.
abstract class AudioEngine {
  /// Fires when [playing], [index], [volume], [order], [repeat] or [shuffle] change, and when the
  /// track starts over by itself (repeating it). Position ticks don't count.
  Stream<void> get changes;

  bool get playing;
  int get index;
  Duration get position;

  /// 0 to 100.
  int get volume;

  /// The play order: for each position, the index of the track in what [open] got. Shuffled while
  /// [shuffle] is on; [index] is a position in it.
  List<int> get order;

  Repeat get repeat;
  bool get shuffle;

  /// Whether the current track failed to load (the media server couldn't give it, say): the engine
  /// stopped on it, paused where it was, rather than moving on to the next. [play] tries it again;
  /// [jump] and [open] go on to others.
  bool get failed;

  /// Opened paused, the tracks load only when they play, on [play] or a [jump]: until then the media
  /// server is asked nothing, and a track it can't give fails only once asked to play.
  Future<void> open(List<Uri> tracks, {required int index, required Duration position, required bool play});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();

  /// Goes to the track at [index] (a position in [order]) from its start, and plays. The current
  /// track starts over.
  Future<void> jump(int index);

  Future<void> seek(Duration position);
  Future<void> setVolume(int volume);
  Future<void> setRepeat(Repeat mode);

  /// On, shuffles the tracks, the current one still playing; off, back to the order [open] got.
  /// It stays on for the tracks opened next.
  Future<void> setShuffle(bool on);

  Future<void> dispose();
}

/// Plays through media_kit (libmpv), on every platform.
class MediaKitEngine implements AudioEngine {
  /// [silent] sends the audio nowhere: for tests on a machine without sound.
  MediaKitEngine({@visibleForTesting bool silent = false}) {
    _ready = silent ? (_player.platform as NativePlayer).setProperty('ao', 'null') : Future.value();
    final stream = _player.stream;
    _subscriptions = [
      stream.playing.listen((_) => _changes.add(null)),
      stream.playlist.listen((playlist) {
        final inOrder = [for (final media in playlist.medias) media.uri];

        // Opened paused, mpv has none of these tracks; and what it says of others (the ones before,
        // or none as it stops) can come late.
        if (_unloaded || !_ours(inOrder)) {
          return;
        }

        // Stopped on a track that failed, where mpv had moved on before it stopped: the failed one
        // stays current, wherever a shuffle puts it.
        if (_failed) {
          if (!listEquals(inOrder, _inOrder)) {
            _index = max(0, inOrder.indexOf(_at(_inOrder, _index) ?? ''));
            _inOrder = inOrder;
            _changes.add(null);
          }

          return;
        }

        // Another track, by itself: from its start. A shuffle keeps the same one current.
        if (_at(inOrder, playlist.index) != _at(_inOrder, _index)) {
          _moved(Duration.zero);
        }

        _inOrder = inOrder;
        _index = playlist.index;
        _changes.add(null);
      }),
      stream.playlistMode.listen((_) => _changes.add(null)),
      stream.volume.listen((_) => _changes.add(null)),
      stream.completed.listen((_) => _changes.add(null)),
      stream.position.listen((reported) {
        if (_moving) {
          if ((reported - position).abs() < const Duration(seconds: 1)) {
            _movedTo = null;
          }
        } else if (reported < _lastPosition - const Duration(milliseconds: 500)) {
          _changes.add(null); // went back by itself: the track started over, repeating it
        }

        _lastPosition = reported;
      }),
      stream.log.listen(_logged),
    ];
  }

  // At the info level, for each track's "Playing:" in the log.
  final _player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.info));
  final _changes = StreamController<void>.broadcast();
  late final List<StreamSubscription<Object?>> _subscriptions;
  late final Future<void> _ready;

  // The current track, from the playlist events and our own calls. media_kit's
  // state.playlist.index can't be trusted: on every open it drops to 0 for a moment, unannounced,
  // and comes back silently (its playlist stream skips a repeat of what it already announced).
  int _index = 0;

  // The tracks as open got them, and in play order (shuffled, or not), as media_kit's URIs.
  List<String> _opened = const [];
  List<String> _inOrder = const [];

  // media_kit turns shuffle off with every open; this is the mode, which stays.
  bool _shuffle = false;

  Duration _lastPosition = Duration.zero;

  // The track mpv last started to load, by its log: what a failure that follows in the log is about.
  // mpv's events can't tell: they can announce the next track before the log says this one failed.
  String? _loading;

  // Opened paused: mpv has none of these tracks until they play.
  bool _unloaded = false;

  // Stopped on a track that failed to load; completed when it does, for a load waiting to seek.
  bool _failed = false;
  Completer<void>? _failure;

  // Where play goes on from, while the tracks are unloaded or stopped on a failure.
  Duration _held = Duration.zero;

  // The track a load or a jump last started, and where from: where its failure leaves playback.
  ({String? track, Duration position})? _starting;

  static String? _at(List<String> tracks, int index) => index >= 0 && index < tracks.length ? tracks[index] : null;

  /// Whether [tracks] are the ones open got, in any order.
  bool _ours(List<String> tracks) => listEquals([...tracks]..sort(), [..._opened]..sort());

  // Where playback went with a seek, a jump or a new track, until media_kit's position gets there:
  // its state.position keeps the old place for a moment, and the player's report to the hub,
  // right after, would send that to the other devices. Past [_trustMoveFor], media_kit's is back.
  Duration? _movedTo;
  DateTime _movedAt = DateTime.now();
  static const _trustMoveFor = Duration(seconds: 2);

  void _moved(Duration to) {
    _movedTo = to;
    _movedAt = DateTime.now();
  }

  bool get _moving => _movedTo != null && DateTime.now().difference(_movedAt) <= _trustMoveFor;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  bool get playing => !_unloaded && !_failed && _player.state.playing;

  @override
  int get index => _index;

  @override
  Duration get position {
    if (_unloaded || _failed) {
      return _held;
    }

    if (!_moving) {
      return _player.state.position;
    }

    final since = DateTime.now().difference(_movedAt);
    return playing ? _movedTo! + since : _movedTo!;
  }

  @override
  int get volume => _player.state.volume.round();

  @override
  List<int> get order {
    final unused = <String, List<int>>{};

    for (final (i, track) in _opened.indexed) {
      (unused[track] ??= []).add(i);
    }

    final order = <int>[];

    for (final track in _inOrder) {
      final positions = unused[track];

      if (positions == null || positions.isEmpty) {
        return [for (var i = 0; i < _opened.length; i++) i];
      }

      order.add(positions.removeAt(0));
    }

    return order;
  }

  @override
  Repeat get repeat => switch (_player.state.playlistMode) {
    PlaylistMode.none => Repeat.off,
    PlaylistMode.loop => Repeat.all,
    PlaylistMode.single => Repeat.one,
  };

  @override
  bool get shuffle => _shuffle;

  @override
  bool get failed => _failed;

  @override
  Future<void> setRepeat(Repeat mode) async {
    await _ready;
    await _player.setPlaylistMode(switch (mode) {
      Repeat.off => PlaylistMode.none,
      Repeat.all => PlaylistMode.loop,
      Repeat.one => PlaylistMode.single,
    });
  }

  @override
  Future<void> setShuffle(bool on) async {
    await _ready;
    _shuffle = on;

    // Unloaded, the tracks get it when they load.
    if (_opened.isNotEmpty && !_unloaded) {
      await _player.setShuffle(on);
    }

    _changes.add(null);
  }

  @override
  Future<void> open(List<Uri> tracks, {required int index, required Duration position, required bool play}) async {
    await _ready;
    _failed = false;
    _opened = _inOrder = [for (final track in tracks) Media(track.toString()).uri];
    _index = index;

    if (play) {
      return _load(position);
    }

    // What mpv had stops, and these wait.
    _unloaded = true;
    _held = position;
    await _player.stop();
    _changes.add(null);
  }

  /// Loads the tracks into mpv and plays the current one from [position].
  Future<void> _load(Duration position) async {
    _unloaded = false;
    final playlist = Playlist([for (final track in _opened) Media(track)], index: _index);
    await _playFrom(position, () => _player.open(playlist, play: false));

    if (_shuffle) {
      await _player.setShuffle(true);
    }
  }

  /// After a failure, mpv keeps its playlist, stopped: plays its track at [index] from [position].
  Future<void> _resume(int index, Duration position) {
    _failed = false;
    _index = index;
    return _playFrom(position, () => (_player.platform as NativePlayer).setProperty('playlist-pos', '$index'));
  }

  /// Plays from [position] the track that [load] loads paused: seeking only works once it has loaded,
  /// which the duration announces. If it fails instead, it stays there.
  Future<void> _playFrom(Duration position, Future<void> Function() load) async {
    _moved(position);
    _starting = (track: _at(_inOrder, _index), position: position);
    final failure = _failure = Completer<void>();
    final loaded = position == Duration.zero ? null : _player.stream.duration.firstWhere((d) => d > Duration.zero);
    await load();

    if (loaded != null) {
      await Future.any([loaded, failure.future]).timeout(const Duration(seconds: 10), onTimeout: () => null);

      if (!_failed) {
        await seek(position);
      }
    }

    if (!_failed) {
      await _player.play();
    }
  }

  /// Plays; tracks opened paused load now, and a track that failed is tried again, from where it was.
  @override
  Future<void> play() {
    if (_unloaded) {
      return _load(_held);
    }

    if (_failed) {
      return _resume(_index, _held);
    }

    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() {
    _unloaded = _failed = false;
    _index = 0;
    _opened = _inOrder = const [];
    _moved(Duration.zero);
    return _player.stop();
  }

  @override
  Future<void> jump(int index) async {
    if (_unloaded) {
      _index = index;
      return _load(Duration.zero);
    }

    if (_failed) {
      return _resume(index, Duration.zero);
    }

    final again = index == _index && !_player.state.completed;
    _index = index;
    _moved(Duration.zero);
    _starting = (track: _at(_inOrder, index), position: Duration.zero);

    if (!again) {
      return _player.jump(index); // which plays too
    }

    // mpv ignores a jump to the track it is on. Once the queue has ended, media_kit's jump is the one
    // that works, since its play would go back to the first track.
    await _player.seek(Duration.zero);
    await _player.play();
  }

  void _logged(PlayerLog log) {
    if (log.prefix == 'cplayer' && log.text.startsWith('Playing: ')) {
      _loading = log.text.substring('Playing: '.length);
    } else if (log.level == 'error' &&
        (log.text.startsWith('Failed to open ') || log.text == 'Failed to recognize file format.')) {
      unawaited(_fail(_loading));
    }
  }

  /// Stops on [track], which mpv couldn't load: mpv itself moves on to the next, and from it to the
  /// next, through the whole queue when the media server fails them all. Paused, so that play tries it
  /// again.
  Future<void> _fail(String? track) async {
    // mpv may have gone on to the next before it stopped, and failed that one too. Unloaded, mpv has
    // none of these tracks.
    if (_failed || _unloaded || track == null) {
      return;
    }

    final at = _at(_inOrder, _index) == track ? _index : _inOrder.indexOf(track);

    if (at < 0) {
      return; // not one of these tracks
    }

    // Where it was to play from, unless mpv failed it moving on by itself.
    _held = _starting?.track == track ? _starting!.position : Duration.zero;
    _failed = true;
    _index = at;
    _failure?.complete();
    _failure = null;
    await _player.pause();
    await (_player.platform as NativePlayer).command(['stop', 'keep-playlist']);
    _changes.add(null);
  }

  @override
  Future<void> seek(Duration position) async {
    // Where play goes on from.
    if (_unloaded || _failed) {
      _held = position;
      return;
    }

    _moved(position);
    await _player.seek(position);
  }

  @override
  Future<void> setVolume(int volume) => _player.setVolume(volume.toDouble());

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }

    await _changes.close();
    await _player.dispose();
  }
}
