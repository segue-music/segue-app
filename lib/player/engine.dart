import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../segue/protocol.dart';

/// Where a track's stream is, for [AudioEngine.open]: the engine asks for it as the track loads.
class TrackSource {
  /// At [url], whenever it loads.
  TrackSource(Uri url) : address = ((from) async => from == Duration.zero ? url : null);

  /// At the address that [address] gives as the track loads, so that what it asks the media server for (its quality)
  /// can change from one track to the next: the stream from its start ([Duration.zero]), or, to seek in a stream that
  /// can't (one the media server transcodes as it goes), from that point, in whole seconds, where null says the stream
  /// can't start there.
  TrackSource.resolved(this.address);

  final Future<Uri?> Function(Duration from) address;
}

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

  /// Opened paused, the current track loads all the same, so that [play] starts it at once. Should it
  /// fail then, the engine stops on it without telling ([failed] stays false), since nothing asked it
  /// to play: [play] tries it again, and tells if it fails again.
  Future<void> open(List<TrackSource> tracks, {required int index, required Duration position, required bool play});
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
///
/// mpv's playlist has a name for each track (`segue://track/<open>/<track>`), not its stream: as mpv is about to load
/// one, its on_load hook asks the track where its stream is ([TrackSource.address]) and points mpv there
/// (stream-open-filename). So the stream can change between two loads of a track, and a stream that can't seek, one the
/// media server transcodes as it goes, seeks by loading its track again, from the point sought ([_startOver]).
class MediaKitEngine implements AudioEngine {
  /// [silent] sends the audio nowhere: for tests on a machine without sound.
  MediaKitEngine({@visibleForTesting bool silent = false}) {
    final native = _player.platform as NativePlayer;
    _ready = silent ? native.setProperty('ao', 'null') : Future.value();
    native.onLoadHooks.add(_pointAtStream);
    final stream = _player.stream;
    _subscriptions = [
      stream.playing.listen((_) => _changes.add(null)),
      stream.playlist.listen((playlist) {
        final inOrder = [for (final media in playlist.medias) media.uri];

        // What mpv says of other tracks (the ones before, or none as it stops) can come late.
        if (!_ours(inOrder)) {
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
          _seekOnLoad = null;
        }

        _inOrder = inOrder;
        _index = playlist.index;
        _changes.add(null);
      }),
      stream.playlistMode.listen((_) => _changes.add(null)),
      stream.volume.listen((_) => _changes.add(null)),
      stream.completed.listen((_) => _changes.add(null)),
      stream.position.listen((inStream) {
        final reported = inStream + _offset;

        if (_moving) {
          if ((reported - position).abs() < const Duration(seconds: 1)) {
            _movedTo = null;
          }
        } else if (reported < _lastPosition - const Duration(milliseconds: 500)) {
          _changes.add(null); // went back by itself: the track started over, repeating it

          // A stream that starts later goes back to where it starts, not to the track's start.
          if (_offset > Duration.zero && !_waiting && !_failed) {
            unawaited(_seek(Duration.zero, play: _player.state.playing));
          }
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
  bool _disposed = false;

  // The current track, from the playlist events and our own calls. media_kit's
  // state.playlist.index can't be trusted: on every open it drops to 0 for a moment, unannounced,
  // and comes back silently (its playlist stream skips a repeat of what it already announced).
  int _index = 0;

  // The tracks as open got them, and their names in mpv's playlist, as open got them and in play order (shuffled, or
  // not). Each open names them anew, so that what mpv says late of the tracks before isn't taken for these.
  List<TrackSource> _tracks = const [];
  int _opens = 0;
  List<String> _opened = const [];
  List<String> _inOrder = const [];

  // Where in the track the current track's stream starts: zero, unless it was loaded again to start later.
  Duration _offset = Duration.zero;

  // The stream [_startOver] got for the track it loads again, which the on_load hook points mpv at.
  ({String track, Uri address})? _restart;

  // Counts the seeks: one that waits for a stream to start later leaves it to a seek after it.
  int _seeks = 0;

  // media_kit turns shuffle off with every open; this is the mode, which stays.
  bool _shuffle = false;

  Duration _lastPosition = Duration.zero;

  // The track mpv last started to load, by its log: what a failure that follows in the log is about.
  // mpv's events can't tell: they can announce the next track before the log says this one failed. And how many loads
  // the log has told of.
  String? _loading;
  int _loadsLogged = 0;

  // Whether the track mpv last started to load ([_loading]) has loaded, as its duration announces; and each load, for
  // a load waiting for its track, by the track and the count of loads the log had told of then.
  bool _loaded = false;
  final _loadsDone = StreamController<({String track, int logged})>.broadcast();

  // A seek while the current track loads, after a jump or moving on by itself: where it goes once loaded.
  Duration? _seekOnLoad;

  // Stopped on a track that failed to load; completed once stopped there, for a load waiting for it.
  bool _failed = false;
  Completer<void>? _failure;

  // Opened paused, until play or a jump: a failure then is no one's doing, so [failed] keeps it quiet.
  bool _quiet = false;

  // A load waiting for its track to load, before which mpv can't seek. A seek moves [_held], where
  // the load then seeks; play and pause say whether it plays then.
  bool _waiting = false;
  bool _playOnLoad = false;

  // Counts the loads and jumps: a load that another one, or a jump, took over leaves the rest to it.
  int _loads = 0;

  // The track a load or a jump last started, and where from: where a failure of it leaves playback.
  // While the track loads, or once it failed, a seek moves that place, which play goes on from.
  String? _starting;
  Duration _held = Duration.zero;

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

  /// Whether the current track has loaded, so that mpv can seek in it, and plays from where it was taken. Should mpv's
  /// log never tell of a load, as it always has, whether it has can't be known: then it has.
  bool get _currentLoaded => (_loaded && _loading == _at(_inOrder, _index)) || _loadsLogged == 0;

  /// A track has just loaded. If it is the current one, it plays from where it was taken only now, and a seek made
  /// while it loaded goes there.
  void _whenLoaded() {
    if (!_currentLoaded) {
      return;
    }

    if (_movedTo != null) {
      _movedAt = DateTime.now();
    }

    final seekOnLoad = _seekOnLoad;
    _seekOnLoad = null;

    if (seekOnLoad != null && !_waiting && !_failed) {
      unawaited(_seek(seekOnLoad, play: _player.state.playing));
    }
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  bool get playing => !_failed && _player.state.playing;

  @override
  int get index => _index;

  @override
  Duration get position {
    if (_waiting || _failed) {
      return _held;
    }

    // Until it has loaded, media_kit's position is the track before's.
    if (!_currentLoaded) {
      return _seekOnLoad ?? _movedTo ?? Duration.zero;
    }

    if (!_moving) {
      return _player.state.position + _offset;
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
  bool get failed => _failed && !_quiet;

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

    if (_opened.isNotEmpty) {
      await _player.setShuffle(on);
    }

    _changes.add(null);
  }

  @override
  Future<void> open(
    List<TrackSource> tracks, {
    required int index,
    required Duration position,
    required bool play,
  }) async {
    await _ready;
    _failed = false;
    _quiet = !play;
    _tracks = tracks;
    _opens++;
    _opened = _inOrder = [for (var i = 0; i < tracks.length; i++) Media('segue://track/$_opens/$i').uri];
    _index = index;
    _offset = Duration.zero;
    _restart = null;
    final playlist = Playlist([for (final track in _opened) Media(track)], index: index);
    await _playFrom(position, () => _player.open(playlist, play: false), play: play);

    if (_shuffle) {
      await _player.setShuffle(true);
    }
  }

  /// mpv's on_load hook: points mpv, about to load one of the tracks, at its stream. The one the track gives now, or,
  /// loading it again to start later, the one [_startOver] got. A track of another open is left as it is, which mpv
  /// fails to open, and a failure the engine ignores, as it does of a track it no longer has.
  Future<void> _pointAtStream() async {
    final native = _player.platform as NativePlayer;
    final track = await native.getProperty('path');
    final i = _opened.indexOf(track);

    if (i < 0 || _disposed) {
      return;
    }

    final restart = _restart;
    Uri? address;

    if (restart != null && restart.track == track) {
      _restart = null;
      address = restart.address;
    } else {
      _offset = Duration.zero;

      try {
        address = await _tracks[i].address(Duration.zero);
      } on Object catch (e) {
        debugPrint('no stream for $track: $e'); // which mpv then fails to open
      }
    }

    if (address != null && !_disposed) {
      await native.setProperty('stream-open-filename', '$address');
    }
  }

  /// After a failure, mpv keeps its playlist, stopped: plays its track at [index] from [position].
  /// Right after the failure, mpv may still be on the failed track (its youtube-dl hook trying it
  /// before giving up), where a write of its playlist-pos would be ignored; playlist-play-index
  /// starts it over all the same.
  Future<void> _resume(int index, Duration position) {
    _failed = false;
    _index = index;
    _offset = Duration.zero;
    _restart = null;
    return _playFrom(position, () => (_player.platform as NativePlayer).command(['playlist-play-index', '$index']));
  }

  /// Plays from [position] the track that [load] loads paused, or, unless [play], only takes it there.
  /// Seeking only works once it has loaded, which the duration announces: until then, a seek moves
  /// where it goes, and play and pause say whether it plays. If it fails instead, it stays there.
  /// [hold] waits for it to load even where it plays from where its stream starts: a track loaded again to start later,
  /// which a seek may follow right away.
  Future<void> _playFrom(Duration position, Future<void> Function() load, {bool play = true, bool hold = false}) async {
    final loads = ++_loads;
    _moved(position);
    _seekOnLoad = null;
    final track = _starting = _at(_inOrder, _index);
    _held = position;
    _playOnLoad = play;
    final failure = _failure = Completer<void>();
    // From where its stream starts, a track that plays needn't wait; one that stays paused does, for a seek first.
    _waiting = position != _offset || !play || hold;
    // Once the log has told of its load, and it has loaded; or any load, once another load or a jump took over.
    final logged = _loadsLogged;
    final loaded = _waiting
        ? _loadsDone.stream.firstWhere((load) => loads != _loads || (load.logged > logged && load.track == track))
        : null;
    await load();

    if (loaded != null) {
      await Future.any([loaded, failure.future]).timeout(const Duration(seconds: 10), onTimeout: () => null);

      if (loads != _loads) {
        return;
      }

      _waiting = false;

      if (!_failed && _held != _offset) {
        await _seek(_held, play: _playOnLoad);

        if (loads != _loads) {
          return; // loaded again, to start there
        }
      }
    }

    if (!_failed && _playOnLoad) {
      await _player.play();
    }
  }

  /// Plays; a track still loading plays once it has, and a track that failed is tried again, from
  /// where it was.
  @override
  Future<void> play() {
    _quiet = false;

    if (_waiting) {
      _playOnLoad = true;
      return Future.value();
    }

    if (_failed) {
      return _resume(_index, _held);
    }

    return _player.play();
  }

  @override
  Future<void> pause() {
    _playOnLoad = false;
    return _player.pause();
  }

  @override
  Future<void> stop() {
    _loads++;
    _failed = _quiet = _waiting = false;
    _index = 0;
    _tracks = const [];
    _opened = _inOrder = const [];
    _offset = Duration.zero;
    _restart = null;
    _seekOnLoad = null;
    _moved(Duration.zero);
    return _player.stop();
  }

  @override
  Future<void> jump(int index) async {
    _quiet = false;

    if (_failed) {
      return _resume(index, Duration.zero);
    }

    // A load still waiting for its track leaves it to the jump.
    _loads++;
    _waiting = false;
    _restart = null;
    _seekOnLoad = null;
    final again = index == _index && !_player.state.completed;
    _index = index;
    _moved(Duration.zero);
    _starting = _at(_inOrder, index);
    _held = Duration.zero;

    if (!again) {
      _offset = Duration.zero;
      return _player.jump(index); // which plays too
    }

    // mpv ignores a jump to the track it is on. Once the queue has ended, media_kit's jump is the one
    // that works, since its play would go back to the first track. A stream that starts later, or can't seek, loads
    // again from the start.
    await _seek(Duration.zero, play: true);
    await _player.play();
  }

  void _logged(PlayerLog log) {
    if (log.prefix == 'cplayer' && log.text.startsWith('Playing: ')) {
      final track = _loading = log.text.substring('Playing: '.length);
      _loaded = false;
      unawaited(_watchLoad(track, ++_loadsLogged));
    } else if (log.level == 'error' &&
        (log.text.startsWith('Failed to open ') || log.text == 'Failed to recognize file format.')) {
      unawaited(_fail(_loading));
    }
  }

  /// Waits for mpv to have loaded [track], the load the log told of as the [logged]th, which it has once it has a
  /// duration. A track the server transcodes as it goes has one too, as long as what came of it. mpv's notice of the
  /// duration can't tell: it may say nothing for a track whose duration is the track before's.
  Future<void> _watchLoad(String track, int logged) async {
    final native = _player.platform as NativePlayer;

    // For 15 s at most, or until another load.
    for (var i = 0; i < 300 && logged == _loadsLogged && !_disposed; i++) {
      final String duration;

      try {
        duration = await native.getProperty('duration');
      } on Object {
        return; // disposed meanwhile
      }

      if (logged != _loadsLogged || _disposed) {
        return;
      }

      if ((double.tryParse(duration) ?? 0) > 0) {
        _loaded = true;
        _loadsDone.add((track: track, logged: logged));
        _whenLoaded();
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Stops on [track], which mpv couldn't load: mpv itself moves on to the next, and from it to the
  /// next, through the whole queue when the media server fails them all. Paused, so that play tries it
  /// again.
  Future<void> _fail(String? track) async {
    // mpv may have gone on to the next before it stopped, and failed that one too.
    if (_failed || track == null) {
      return;
    }

    final at = _at(_inOrder, _index) == track ? _index : _inOrder.indexOf(track);

    if (at < 0) {
      return; // not one of these tracks
    }

    // Where it was to play from, unless mpv failed it moving on by itself.
    if (_starting != track) {
      _held = Duration.zero;
    }

    _failed = true;
    _index = at;
    final failure = _failure;
    _failure = null;
    await _player.pause();
    await (_player.platform as NativePlayer).command(['stop', 'keep-playlist']);
    // Only now does a load waiting for the track go on: a play right after it, trying the track again,
    // would be stopped by this stop.
    failure?.complete();
    _changes.add(null);
  }

  @override
  Future<void> seek(Duration position) => _seek(position, play: _player.state.playing);

  /// Seeks to [position], where a track loaded again to start there plays or not as [play] says.
  Future<void> _seek(Duration position, {required bool play}) async {
    // Where it goes once loaded, or tried again.
    if (_waiting || _failed) {
      _held = position;
      return;
    }

    final seeks = ++_seeks;
    _moved(position);

    // mpv can't seek in a track still loading.
    if (!_currentLoaded) {
      _seekOnLoad = position;
      return;
    }

    // Before where the stream starts, or, in a stream that can't seek (one the media server transcodes as it goes),
    // past its start, the track loads again to start there; mpv's cache still has the start.
    if (position < _offset || (position > Duration.zero && !await _seekable)) {
      if (await _startOver(position, play: play, seeks: seeks)) {
        return;
      }
    }

    if (seeks == _seeks) {
      await _player.seek(position > _offset ? position - _offset : Duration.zero);
    }
  }

  /// Whether mpv can seek in the current track's stream: a file can, as can HLS, but not a stream that the media
  /// server transcodes as it goes, unless it has the whole of it already. Until the log says the track loads, mpv's
  /// answer is the track before's, so it may: as it always could.
  Future<bool> get _seekable async =>
      _loading != _at(_inOrder, _index) || await (_player.platform as NativePlayer).getProperty('seekable') != 'no';

  /// Loads the current track again, its stream starting at [position], in whole seconds, and plays it there or not as
  /// [play] says. False where its stream can't start there. Gives up on it for the seek after [seeks], or a load.
  Future<bool> _startOver(Duration position, {required bool play, required int seeks}) async {
    final track = _at(_inOrder, _index);
    final i = track == null ? -1 : _opened.indexOf(track);

    if (i < 0) {
      return false;
    }

    final loads = _loads;
    final from = Duration(seconds: position.inSeconds);
    final Uri? address;

    try {
      address = await _tracks[i].address(from);
    } on Object catch (e) {
      debugPrint('no stream for $track from $from: $e');
      return false;
    }

    if (seeks != _seeks || loads != _loads) {
      return true; // nothing to do: the seek, or the load, after it does it
    }

    if (address == null) {
      return false;
    }

    _restart = (track: track!, address: address);
    _offset = from;
    await _playFrom(
      from,
      () => (_player.platform as NativePlayer).command(['playlist-play-index', '$_index']),
      play: play,
      hold: true,
    );
    return true;
  }

  @override
  Future<void> setVolume(int volume) => _player.setVolume(volume.toDouble());

  @override
  Future<void> dispose() async {
    _disposed = true;

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }

    await _changes.close();
    await _loadsDone.close();
    await _player.dispose();
  }
}
