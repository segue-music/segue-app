import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../segue/protocol.dart';

/// Where a track's stream is, for [AudioEngine.open], and how loud it plays: the engine asks for them as the track
/// loads.
class TrackSource {
  /// At [url], whenever it loads, with [gain].
  TrackSource(Uri url, {TrackGain gain = TrackGain.none})
    : address = ((from) async => from == Duration.zero ? url : null),
      gain = (() => gain);

  /// At the address that [address] gives as the track loads, so that what it asks the media server for (its quality)
  /// can change from one track to the next: the stream from its start ([Duration.zero]), or, to seek in a stream that
  /// can't (one the media server transcodes as it goes), from that point, in whole seconds, where null says the stream
  /// can't start there. With the gain that [gain] gives then, and again as [AudioEngine.updateGain] asks for it.
  TrackSource.resolved(this.address, {this.gain = _asItIs});

  final Future<Uri?> Function(Duration from) address;
  final TrackGain Function() gain;

  static TrackGain _asItIs() => TrackGain.none;
}

/// How loud a track plays, so that the tracks play about as loud as one another (ReplayGain).
@immutable
class TrackGain {
  /// [decibels] louder, or, below zero, quieter.
  const TrackGain(this.decibels) : tagged = false, album = false;

  /// As the file's own ReplayGain tags say: its album's gain ([album]), or its own, the other where it has only that
  /// one, lowered where the tags' peak says it would clip; none where it has no tags.
  const TrackGain.tagged({required this.album}) : decibels = 0, tagged = true;

  /// The track as it is.
  static const none = TrackGain(0);

  final double decibels;

  /// Whether it is the file's tags that say, rather than [decibels].
  final bool tagged;

  /// Whether the tags' gain is the album's.
  final bool album;

  @override
  bool operator ==(Object other) =>
      other is TrackGain && other.decibels == decibels && other.tagged == tagged && other.album == album;

  @override
  int get hashCode => Object.hash(decibels, tagged, album);

  @override
  String toString() => tagged ? 'TrackGain.tagged(album: $album)' : 'TrackGain($decibels)';
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

  /// Asks the current track for its gain again ([TrackSource.gain]), and plays it so from now on: as the way the tracks
  /// are levelled changes. The others are asked as they load.
  Future<void> updateGain();

  /// Plays every track through an equalizer of [gains]: by each band's center frequency, in Hz, how much louder it
  /// makes the frequencies around it, an octave wide, in dB, or, below zero, quieter. Lowered as a whole by as much as
  /// the bands raise the frequency they raise most, so that they never make a track clip. None, the tracks as they are.
  /// It holds at once, for the track that plays too.
  Future<void> setEqualizer(Map<int, double> gains);

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
/// (stream-open-filename), and how loud it plays ([TrackSource.gain]). So the stream can change between two loads of a
/// track, and a stream that can't seek, one the media server transcodes as it goes, seeks by loading its track again,
/// from the point sought ([_startOver]).
class MediaKitEngine implements AudioEngine {
  /// [silent] sends the audio nowhere: for tests on a machine without sound. [audioFile] writes it to that file
  /// instead, as raw samples (16 bits, in the tracks' channels and sample rate), as fast as mpv decodes them: for tests
  /// that listen to it.
  MediaKitEngine({@visibleForTesting bool silent = false, @visibleForTesting String? audioFile}) {
    final native = _player.platform as NativePlayer;
    _ready = audioFile != null
        ? _writeAudioTo(native, audioFile)
        : silent
        ? native.setProperty('ao', 'null')
        : Future.value();
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

  /// Has mpv write the audio to [file], for the constructor's audioFile.
  static Future<void> _writeAudioTo(NativePlayer native, String file) async {
    await native.setProperty('ao', 'pcm');
    await native.setProperty('ao-pcm-file', file);
    await native.setProperty('ao-pcm-waveheader', 'no');
    // Each track after the one before, should mpv open the file again for one.
    await native.setProperty('ao-pcm-append', 'yes');
    await native.setProperty('audio-format', 's16');
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

  /// mpv's on_load hook: points mpv, about to load one of the tracks, at its stream, and plays it with its gain. The
  /// stream the track gives now, or, loading it again to start later, the one [_startOver] got. A track of another open
  /// is left as it is, which mpv fails to open, and a failure the engine ignores, as it does of a track it no longer
  /// has.
  Future<void> _pointAtStream() async {
    final native = _player.platform as NativePlayer;
    final track = await native.getProperty('path');
    final i = _opened.indexOf(track);

    if (i < 0 || _disposed) {
      return;
    }

    // As open got it: another open may come while it gives its stream.
    final source = _tracks[i];
    final restart = _restart;
    Uri? address;

    if (restart != null && restart.track == track) {
      _restart = null;
      address = restart.address;
    } else {
      _offset = Duration.zero;

      try {
        address = await source.address(Duration.zero);
      } on Object catch (e) {
        debugPrint('no stream for $track: $e'); // which mpv then fails to open
      }
    }

    if (address != null && !_disposed) {
      await native.setProperty('stream-open-filename', '$address');
    }

    if (!_disposed) {
      await _playWith(source.gain());
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
  Future<void> updateGain() async {
    await _ready;
    final track = _at(_inOrder, _index);
    final i = track == null ? -1 : _opened.indexOf(track);

    if (i >= 0 && !_disposed) {
      await _playWith(_tracks[i].gain());
    }
  }

  /// Plays the current track, and the next until another gain, with [gain]. mpv's ReplayGain reads a file's tags, and
  /// lowers the gain where their peak says it would clip; with it off, or for a file without them, it plays every track
  /// with its fallback gain (player/audio.c, compute_replaygain), which then gives [TrackGain.decibels]. It reckons
  /// the gain again as each track's audio starts, and right away as these change.
  Future<void> _playWith(TrackGain gain) async {
    final native = _player.platform as NativePlayer;
    await native.setProperty('replaygain', gain.tagged ? (gain.album ? 'album' : 'track') : 'no');
    // mpv takes fallbacks from -200 dB to 60 dB.
    await native.setProperty('replaygain-fallback', '${gain.decibels.clamp(-200, 60)}');
  }

  /// The equalizer is mpv's audio filters (af), FFmpeg's: none while it is off, and on, one for each band, so that mpv,
  /// given them again with a band moved, makes only that one anew, the others going on as they were
  /// (mp_output_chain_update_filters, in its filters/f_output_chain.c). Before them, the audio goes to 48 kHz, in
  /// floats: FFmpeg's equalizer leaves out a band past half a track's sample rate, but one at half of it (16 kHz, in a
  /// track of 32 kHz) silences the track. And it goes down there by as much as the bands raise the frequency they raise
  /// most, by aresample's rematrix_volume: iOS's libavfilter has no volume filter. Turning it on or off changes what mpv
  /// sends to the audio output, which starts again: the sound stops for a moment.
  @override
  Future<void> setEqualizer(Map<int, double> gains) async {
    await _ready;

    if (_disposed) {
      return;
    }

    final volume = pow(10, -_loudestBoost(gains) / 20);
    final filters = [
      if (gains.isNotEmpty) 'lavfi=[aresample=$_equalizerRate:osf=fltp:rematrix_volume=${volume.toStringAsFixed(6)}]',
      for (final MapEntry(key: frequency, value: gain) in gains.entries)
        'lavfi=[equalizer=f=$frequency:t=o:w=1:g=${gain.toStringAsFixed(2)}]',
    ];
    await (_player.platform as NativePlayer).setProperty('af', filters.join(','));
  }

  /// The sample rate the equalizer works at.
  static const _equalizerRate = 48000;

  /// How much louder, in dB, the bands [gains] (as [setEqualizer] has them) make the frequency they raise most, of those
  /// heard (20 Hz to 20 kHz); none where they raise none. Each band is FFmpeg's equalizer (its af_biquads.c), the Audio
  /// EQ Cookbook's peaking filter, an octave wide, and their gains, in dB, add up: the frequencies looked at are the
  /// bands' own and every 48th of an octave.
  static double _loudestBoost(Map<int, double> gains) {
    final bands = [
      for (final MapEntry(key: frequency, value: gain) in gains.entries)
        if (gain != 0) _peakingFilter(frequency, gain),
    ];
    final frequencies = [
      ...gains.keys.map((frequency) => frequency.toDouble()),
      for (var i = 0; i <= 480; i++) 20 * pow(2, i / 48).toDouble(),
    ];
    var loudest = 0.0;

    for (final frequency in frequencies) {
      loudest = max(loudest, bands.fold(0.0, (sum, band) => sum + band(frequency)));
    }

    return loudest;
  }

  /// A band of [gain] dB at [center] Hz, as FFmpeg's equalizer makes it at the equalizer's sample rate, an octave
  /// wide: how much louder it makes a frequency, in Hz, in dB.
  static double Function(double frequency) _peakingFilter(int center, double gain) {
    final a = pow(10, gain / 40);
    final w0 = 2 * pi * center / _equalizerRate;
    final alpha = sin(w0) * _sinh(log(2) / 2 * w0 / sin(w0));
    final (b0, b1, b2) = (1 + alpha * a, -2 * cos(w0), 1 - alpha * a);
    final (a0, a1, a2) = (1 + alpha / a, -2 * cos(w0), 1 - alpha / a);

    // The squared magnitude of c0 + c1 z⁻¹ + c2 z⁻² on the unit circle, at w.
    double squared(double c0, double c1, double c2, double w) =>
        c0 * c0 + c1 * c1 + c2 * c2 + 2 * (c0 * c1 + c1 * c2) * cos(w) + 2 * c0 * c2 * cos(2 * w);

    return (frequency) {
      final w = 2 * pi * frequency / _equalizerRate;
      return 10 * log(squared(b0, b1, b2, w) / squared(a0, a1, a2, w)) / ln10;
    };
  }

  static double _sinh(double x) => (exp(x) - exp(-x)) / 2;

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
