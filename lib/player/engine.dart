import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';

import '../segue/protocol.dart';

final _log = Logger('MediaKitEngine');

/// Where a track's stream is, for [AudioEngine.open], and how loud it plays: the engine asks for them as the track
/// loads.
class TrackSource {
  /// At [url], whenever it loads, with [gain]; [duration] long.
  TrackSource(Uri url, {TrackGain gain = TrackGain.none, this.duration})
    : address = (() => url),
      addressFrom = _nowhere,
      gain = (() => gain);

  /// At the address that [address] gives as the track loads, so that what it asks the media server for (its quality)
  /// can change from one track to the next; asked as the track is opened too, for the stream the engine may open ahead.
  /// To seek in a stream that can't (one the media server transcodes as it goes), from that point on, in whole seconds,
  /// at the one [addressFrom] gives, where null says the stream can't start there. With the gain that [gain] gives as
  /// it loads, and again as [AudioEngine.updateGain] asks for it. [duration] long.
  TrackSource.resolved(this.address, {this.addressFrom = _nowhere, this.gain = _asItIs, this.duration});

  final Uri Function() address;
  final Future<Uri?> Function(Duration from) addressFrom;
  final TrackGain Function() gain;

  /// How long the track is, as the media server says; null where it doesn't.
  final Duration? duration;

  static Future<Uri?> _nowhere(Duration from) async => null;

  static TrackGain _asItIs() => TrackGain.none;
}

/// How loud a track plays, so that the tracks play about as loud as one another (ReplayGain).
@immutable
class TrackGain {
  /// [decibels] louder, or, below zero, quieter.
  const TrackGain(this.decibels) : tagged = false, album = false, preamp = 0;

  /// As the file's own ReplayGain tags say, [preamp] dB louder: its album's gain ([album]), or its own, the other where
  /// it has only that one, lowered where the tags' peak says it would clip; none where it has no tags.
  const TrackGain.tagged({required this.album, this.preamp = 0}) : decibels = 0, tagged = true;

  /// The track as it is.
  static const none = TrackGain(0);

  final double decibels;

  /// Whether it is the file's tags that say, rather than [decibels].
  final bool tagged;

  /// Whether the tags' gain is the album's.
  final bool album;

  /// How much louder than its tags' gain the track plays, in dB, where they say it.
  final double preamp;

  @override
  bool operator ==(Object other) =>
      other is TrackGain &&
      other.decibels == decibels &&
      other.tagged == tagged &&
      other.album == album &&
      other.preamp == preamp;

  @override
  int get hashCode => Object.hash(decibels, tagged, album, preamp);

  @override
  String toString() => tagged ? 'TrackGain.tagged(album: $album, preamp: $preamp)' : 'TrackGain($decibels)';
}

/// What [PlayerController] needs from an audio backend. [MediaKitEngine] is the real one; the tests
/// use a fake.
abstract class AudioEngine {
  /// Fires when [playing], [index], [volume], [order], [repeat] or [shuffle] change, and when the
  /// track starts over by itself (repeating it). Position ticks don't count.
  Stream<void> get changes;

  /// Fires as a track plays to its end: as the next one starts by itself, as it starts over, repeating it, or, the last
  /// with repeat off, as the engine stops on it. Not as it's left for another ([jump], [open]), nor as it fails.
  Stream<void> get ended;

  bool get playing;
  int get index;
  Duration get position;

  /// 0 to 100.
  int get volume;

  /// The play order: for each position, the index of the track in the order the tracks have unshuffled: what [open]
  /// got, with what [add] added among them. Shuffled while [shuffle] is on; [index] is a position in it.
  List<int> get order;

  Repeat get repeat;
  bool get shuffle;

  /// Whether the current track failed to load (the media server couldn't give it, say): the engine
  /// stopped on it, paused where it was, rather than moving on to the next. [play] tries it again;
  /// [jump] and [open] go on to others.
  bool get failed;

  /// Plays [tracks] from the one at [index], at [position], or, unless [play], only takes them there.
  ///
  /// Opened paused, the current track loads all the same, so that [play] starts it at once. Should it
  /// fail then, the engine stops on it without telling ([failed] stays false), since nothing asked it
  /// to play: [play] tries it again, and tells if it fails again.
  ///
  /// With shuffle on, they play in [order] (as [AudioEngine.order] says one), where given: shuffled already, as by
  /// another engine; otherwise the engine shuffles them.
  Future<void> open(
    List<TrackSource> tracks, {
    required int index,
    required Duration position,
    required bool play,
    List<int>? order,
  });

  /// Adds [tracks] to those open got, the current one playing on: right after it if [next], in the play order and in
  /// the order unshuffled alike, otherwise after the last one in both. Where they went in the order unshuffled: the
  /// index of the first; -1 where none were open to add them to (a stop, or another open, came first).
  Future<int> add(List<TrackSource> tracks, {required bool next});

  /// Moves the track at [from] in the play order ([order]) to [to], the place it then has, the current one playing on,
  /// wherever that takes it. Shuffled, that changes the play order alone, which shuffle going off forgets; otherwise the
  /// order unshuffled changes with it. Where the track was and went in the order unshuffled where that changed; null
  /// where it didn't (shuffled), or where there was no such track (a stop, or another open, came first).
  Future<({int from, int to})?> move(int from, int to);

  /// Takes the track at [index] in the play order ([order]) out, of the order unshuffled too; not the current one,
  /// which plays on. Where it was in the order unshuffled; -1 where there was no such track to take out (the current
  /// one, a stop, or another open first).
  Future<int> remove(int index);

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

  /// On, shuffles the tracks, the current one still playing; off, back to their order unshuffled ([order]).
  /// It stays on for the tracks opened next.
  Future<void> setShuffle(bool on);

  Future<void> dispose();
}

/// An engine that [CrossfadeEngine] plays the tracks on, one at a time, each on the deck whose turn it is.
abstract interface class Deck implements AudioEngine {
  /// How long the current track is, where its stream says (a file, or a stream that can seek, whose length is known):
  /// zero where it doesn't, as a stream the media server transcodes as it goes says nothing of its length.
  Duration get duration;

  /// Plays at [level] of [volume]: from 0, nothing heard, to 1, as loud as [volume] says, as a sound's amplitude goes.
  /// [volume] stays as it is, and nothing is told of it.
  Future<void> setLevel(double level);
}

/// Plays through media_kit (libmpv), on every platform.
///
/// mpv's playlist has a name for each track ([_name]): its stream's address as the track was opened, with the name in
/// its query, or, for a file, the name alone (`segue://track/<open>.<track>`). As mpv is about to load one, its on_load
/// hook asks the track where its stream is ([TrackSource.address]) and points mpv there (stream-open-filename), and how
/// loud it plays ([TrackSource.gain]). So the stream can change between two loads of a track, and a stream that can't
/// seek, one the media server transcodes as it goes, seeks by loading its track again, from the point sought
/// ([_startOver]).
///
/// mpv opens the next track's stream as the one before plays (prefetch-playlist), so that it plays right after, with
/// no gap, however late the media server answers. It opens the track's name, before the on_load hook, so a stream that
/// is still the one the name says is opened ahead; one that changed (another quality) is opened as the track loads.
///
/// On iOS mpv's audio output stays closed until the engine first plays ([_withAudio]): there it (audiounit) takes the
/// audio session as it opens, which stops another app's music, and it opens as a track loads, paused too, as the last
/// playback does when the app opens.
class MediaKitEngine implements Deck {
  /// [silent] sends the audio nowhere: for tests on a machine without sound. [audioFile] writes it to that file
  /// instead, as raw samples (16 bits, in the tracks' channels and sample rate), as fast as mpv decodes them: for tests
  /// that listen to it. [holdAudio] keeps the audio output closed until the engine first plays, as on iOS.
  MediaKitEngine({
    @visibleForTesting bool silent = false,
    @visibleForTesting String? audioFile,
    @visibleForTesting bool? holdAudio,
  }) : _output = audioFile != null ? 'pcm' : (silent ? 'null' : ''),
       _audioHeld = holdAudio ?? Platform.isIOS {
    final native = _player.platform as NativePlayer;
    _ready = Future.wait([
      native.setProperty('prefetch-playlist', 'yes'),
      // media_kit turns the cache on disk on, in a folder libmpv, with no config of its own, hasn't: each stream failed
      // to make its file ("Failed to create file cache"), and kept its cache in memory, as it now does from the start.
      native.setProperty('cache-on-disk', 'no'),
      if (audioFile != null) _writeAudioTo(native, audioFile),
      if (_audioHeld || _output.isNotEmpty) native.setProperty('ao', _audioHeld ? 'null' : _output),
    ]);
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

        final moved = !listEquals(inOrder, _inOrder);

        // Stopped on a track that failed, where mpv had moved on before it stopped, or tracks moving ([_rearrange]),
        // which media_kit tells of with the index from before: the current one stays current, wherever they put it.
        if (_failed || (_rearranging && moved)) {
          if (moved) {
            _index = max(0, inOrder.indexOf(_at(_inOrder, _index) ?? ''));
            _inOrder = inOrder;

            // Moving, once they are all where they go.
            if (!_rearranging) {
              _changes.add(null);
            }
          }

          return;
        }

        // Another track, by itself: from its start, the one before having ended. A shuffle keeps the same one current.
        final next = _at(inOrder, playlist.index) != _at(_inOrder, _index);

        if (next) {
          _moved(Duration.zero);
          _seekOnLoad = null;
        }

        _inOrder = inOrder;
        _index = playlist.index;
        _changes.add(null);

        if (next) {
          _ended.add(null);
        }
      }),
      stream.playlistMode.listen((_) => _changes.add(null)),
      stream.completed.listen((completed) {
        _changes.add(null);

        // The last track ended, repeat off: mpv stays on it, at its end (keep-open, as media_kit has it). media_kit
        // tells of the end of the others too, which the next track starting tells of.
        if (completed && repeat == Repeat.off && _index == _inOrder.length - 1) {
          _ended.add(null);
        }
      }),
      stream.position.listen((inStream) {
        final reported = inStream + _offset;

        if (_moving) {
          if ((reported - position).abs() < const Duration(seconds: 1)) {
            _movedTo = null;
          }
        } else if (reported < _lastPosition - const Duration(milliseconds: 500)) {
          _changes.add(null); // went back by itself: the track started over, repeating it

          // It ended, then, where it repeats by itself: the next track that starts, otherwise, tells of it, and the
          // position going back to its start may come first.
          if (repeat == Repeat.one || _inOrder.length == 1) {
            _ended.add(null);
          }

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
    await native.setProperty('ao-pcm-file', file);
    await native.setProperty('ao-pcm-waveheader', 'no');
    // Each track after the one before, should mpv open the file again for one.
    await native.setProperty('ao-pcm-append', 'yes');
    await native.setProperty('audio-format', 's16');
  }

  // At the info level, for each track's "Playing:" in the log.
  final _player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.info));
  final _changes = StreamController<void>.broadcast();
  final _ended = StreamController<void>.broadcast();
  late final List<StreamSubscription<Object?>> _subscriptions;
  late final Future<void> _ready;
  bool _disposed = false;

  // mpv's audio output as it is to be ('pcm', 'null', or '' for mpv's own), and whether it is still held closed, and
  // opening for the first play.
  final String _output;
  bool _audioHeld;
  Future<void>? _audioOpening;

  // Counts the pauses: one while the audio output opens leaves the play that opened it undone.
  int _pauses = 0;

  // The current track, from the playlist events and our own calls. media_kit's
  // state.playlist.index can't be trusted: on every open it drops to 0 for a moment, unannounced,
  // and comes back silently (its playlist stream skips a repeat of what it already announced).
  int _index = 0;

  // The tracks as open got them, with those added among them (the order unshuffled), and their names in mpv's
  // playlist, in that order and in play order (shuffled, or not). Each open names them anew, so that what mpv says late
  // of the tracks before isn't taken for these; and counts the tracks it named, for the names of those added.
  List<TrackSource> _tracks = const [];
  int _opens = 0;
  int _named = 0;
  List<String> _opened = const [];
  List<String> _inOrder = const [];

  // Moving tracks in mpv's playlist ([_rearrange]): media_kit tells of each move with the index from before, so until
  // done the current track is known by its name. And the changes that move them (adding tracks, shuffling), one after
  // another, each finding the playlist as the one before left it.
  bool _rearranging = false;
  Future<void> _rearrangements = Future.value();

  // Where in the track the current track's stream starts: zero, unless it was loaded again to start later.
  Duration _offset = Duration.zero;

  // The stream [_startOver] got for the track it loads again, which the on_load hook points mpv at.
  ({String track, Uri address})? _restart;

  // Counts the seeks: one that waits for a stream to start later leaves it to a seek after it.
  int _seeks = 0;

  // media_kit turns shuffle off with every open; this is the mode, which stays.
  bool _shuffle = false;

  // The volume, and the level of it that plays ([setLevel]), which mpv's volume makes of them.
  int _volume = 100;
  double _level = 1;

  Duration _lastPosition = Duration.zero;

  // The track mpv last started to load, by its log: what a failure that follows in the log is about.
  // mpv's events can't tell: they can announce the next track before the log says this one failed. And how many loads
  // the log has told of.
  String? _loading;
  int _loadsLogged = 0;

  // The stream the on_load hook pointed mpv at for the track it loads ([_loading]): a stream that fails to open, other
  // than it or the track's name, is another track's, one mpv opened ahead as the one before played, which it tries
  // again as it loads it.
  String? _loadingStream;

  // Whether mpv opens the next track ahead (prefetch-playlist), as it does from the start ([_openAheadAfter]).
  bool _prefetch = true;

  // Whether the track mpv last started to load ([_loading]) has loaded, as its duration announces, and whether mpv
  // knows how long it is, as it does of a stream it can seek in; and each load, for a load waiting for its track, by
  // the track and the count of loads the log had told of then.
  bool _loaded = false;
  bool _lengthKnown = false;
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

  /// Whether [tracks] are of those open got, and add added: all of them, in any order, or, as [add] gives mpv its tracks
  /// one by one, some.
  bool _ours(List<String> tracks) => tracks.isNotEmpty && tracks.every(_opened.toSet().contains);

  // Where playback went with a seek, a jump or a new track, until media_kit's position gets there:
  // its state.position keeps the old place for a moment, and the player's report to the hub,
  // right after, would send that to the other devices. Past [_trustMoveFor], media_kit's is back.
  Duration? _movedTo;
  DateTime _movedAt = DateTime.now();
  static const _trustMoveFor = Duration(seconds: 2);

  void _moved(Duration to) {
    _movedTo = to;
    _movedAt = DateTime.now();
    // Not back by itself, should it be before where it was: what the position says next is from here.
    _lastPosition = to;
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
  Stream<void> get ended => _ended.stream;

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
  int get volume => _volume;

  @override
  Duration get duration =>
      _lengthKnown && _currentLoaded && !_waiting && !_failed ? _player.state.duration + _offset : Duration.zero;

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
  Future<void> setShuffle(bool on) => _inTurn(() async {
    await _ready;

    // As it is: media_kit's own check doesn't stop it, as an open in an order given leaves it thinking shuffle off.
    if (on == _shuffle) {
      return;
    }

    _shuffle = on;

    if (_opened.isNotEmpty) {
      await _player.setShuffle(on);

      // mpv puts back in their order only the tracks it shuffled, and those added since anywhere.
      if (!on) {
        await _rearrange(_opened);
      }
    }

    _changes.add(null);
  });

  /// Runs [change] once the changes that move tracks before it are done ([_rearrangements]).
  Future<T> _inTurn<T>(Future<T> Function() change) {
    final done = _rearrangements.then((_) => change());
    _rearrangements = done.then<void>((_) {}, onError: (Object _) {});

    return done;
  }

  /// In an [order] given, mpv's playlist is in that order, which shuffle going off takes back to the tracks' own, as it
  /// does tracks added shuffled ([_rearrange]).
  @override
  Future<void> open(
    List<TrackSource> tracks, {
    required int index,
    required Duration position,
    required bool play,
    List<int>? order,
  }) async {
    await _ready;
    final shuffled = _shuffle && order != null && order.length == tracks.length;
    _failed = false;
    _quiet = !play;
    _tracks = tracks;
    _opens++;
    _named = tracks.length;
    _opened = _inOrder = [for (final (i, track) in tracks.indexed) _name('$_opens.$i', _addressOf(track))];

    if (shuffled) {
      _inOrder = [for (final i in order) _opened[i]];
    }

    _index = shuffled ? order.indexOf(index) : index;
    _offset = Duration.zero;
    _restart = null;
    final playlist = Playlist([for (final track in _inOrder) Media(track)], index: _index);

    await _playFrom(position, () => _player.open(playlist, play: false), play: play);

    if (_shuffle && !shuffled) {
      await _player.setShuffle(true);
    }
  }

  /// mpv appends each track at the end of its playlist, from where, to play next, they move one by one to right after
  /// the current track, which plays on.
  @override
  Future<int> add(List<TrackSource> tracks, {required bool next}) {
    final opens = _opens;

    return _inTurn(() => _add(tracks, next: next, opens: opens));
  }

  /// [add], once the changes before it are done, unless another open, the [opens]th, came first.
  Future<int> _add(List<TrackSource> tracks, {required bool next, required int opens}) async {
    await _ready;
    final current = _at(_inOrder, _index);

    if (opens != _opens || current == null) {
      return -1;
    }

    final at = next ? _opened.indexOf(current) + 1 : _opened.length;
    final place = next ? _index + 1 : _inOrder.length;
    final names = [for (final track in tracks) _name('$_opens.${_named++}', _addressOf(track))];
    _tracks = [..._tracks.take(at), ...tracks, ..._tracks.skip(at)];
    _opened = [..._opened.take(at), ...names, ..._opened.skip(at)];
    await _rearrange(
      [..._inOrder.take(place), ...names, ..._inOrder.skip(place)],
      append: () async {
        for (final name in names) {
          // Another open, or a stop, took the playlist.
          if (opens != _opens || _opened.isEmpty) {
            return;
          }

          await _player.add(Media(name));
        }
      },
    );

    return at;
  }

  @override
  Future<({int from, int to})?> move(int from, int to) {
    final opens = _opens;

    return _inTurn(() => _move(from, to, opens: opens));
  }

  /// [move], once the changes before it are done, unless another open, the [opens]th, came first.
  Future<({int from, int to})?> _move(int from, int to, {required int opens}) async {
    await _ready;
    final track = _at(_inOrder, from);

    if (opens != _opens || track == null || to < 0 || to >= _inOrder.length) {
      return null;
    }

    ({int from, int to})? unshuffled;

    // Unshuffled, the tracks are in the play order.
    if (!_shuffle) {
      final at = _opened.indexOf(track);
      final source = _tracks[at];
      _opened = [..._opened]
        ..removeAt(at)
        ..insert(to, track);
      _tracks = [..._tracks]
        ..removeAt(at)
        ..insert(to, source);
      unshuffled = (from: at, to: to);
    }

    await _rearrange(
      [..._inOrder]
        ..removeAt(from)
        ..insert(to, track),
    );

    return unshuffled;
  }

  @override
  Future<int> remove(int index) {
    final opens = _opens;

    return _inTurn(() => _remove(index, opens: opens));
  }

  /// [remove], once the changes before it are done, unless another open, the [opens]th, came first. As in
  /// [_rearrange], the engine knows the current track by its name until mpv has said where it went, which, where a
  /// track before it goes, comes after.
  Future<int> _remove(int index, {required int opens}) async {
    await _ready;
    final track = _at(_inOrder, index);

    if (opens != _opens || track == null || index == _index) {
      return -1;
    }

    // Out of those it has first, so that what mpv says of the playlist with it isn't taken for the tracks now.
    final at = _opened.indexOf(track);
    _opened = [..._opened]..removeAt(at);
    _tracks = [..._tracks]..removeAt(at);
    _rearranging = true;

    try {
      final playing = int.tryParse(await (_player.platform as NativePlayer).getProperty('playlist-playing-pos')) ?? -1;
      final from = _player.state.playlist.medias.indexWhere((media) => media.uri == track);

      if (from >= 0) {
        final told = from < playing
            ? _player.stream.playlist
                  .firstWhere((playlist) => playlist.index == playing - 1)
                  .then<void>((_) {}, onError: (Object _) {})
            : null;

        await _player.remove(from);
        await told?.timeout(const Duration(seconds: 1), onTimeout: () {});
      }
    } finally {
      _rearranging = false;
    }

    _changes.add(null);

    return at;
  }

  /// Moves the tracks in mpv's playlist, once [append] has added its own at its end, into the play order [target], the
  /// current track playing on. media_kit tells of each move with the index from before: until done the engine knows the
  /// current track by its name, and tells of the change once. mpv tells of the current track's new place, where a move
  /// takes another track over it, only after the move: the next move waits for it, so that it comes with the playlist
  /// it is about, rather than with a later one, where it would name another track. That one may come too, where the
  /// current track has ended meanwhile, which the engine follows.
  Future<void> _rearrange(List<String> target, {Future<void> Function()? append}) async {
    final opens = _opens;
    _rearranging = true;

    try {
      await append?.call();

      final playing = int.tryParse(await (_player.platform as NativePlayer).getProperty('playlist-playing-pos')) ?? -1;
      final inOrder = [for (final media in _player.state.playlist.medias) media.uri];
      final current = _at(inOrder, playing);

      for (var i = 0; i < target.length && opens == _opens && _opened.isNotEmpty; i++) {
        final from = inOrder.indexOf(target[i], i);

        // In its place, or not in mpv's playlist.
        if (from <= i) {
          continue;
        }

        final before = current == null ? -1 : inOrder.indexOf(current);

        inOrder.insert(i, inOrder.removeAt(from));

        final after = current == null ? -1 : inOrder.indexOf(current);
        final told = before == after
            ? null
            : _player.stream.playlist
                  .firstWhere((playlist) => playlist.index == after)
                  .then<void>((_) {}, onError: (Object _) {});

        await _player.move(from, i);
        await told?.timeout(const Duration(seconds: 1), onTimeout: () {});
      }
    } finally {
      _rearranging = false;
    }

    _changes.add(null);
  }

  /// The name in mpv's playlist of the track [id] (`<open>.<track>`), whose stream is at [address] as it is opened: its
  /// stream's ([_streamName]), or else the id alone.
  static String _name(String id, Uri? address) => _streamName(id, address) ?? Media('segue://track/$id').uri;

  /// The name of the track [id] where its stream, at [address], is the media server's: the address itself, with [id]
  /// last in its query, which the media server ignores, so that mpv, opening the track ahead (prefetch-playlist), opens
  /// its stream. None for a file, which opens at once, or a track without a stream.
  static String? _streamName(String id, Uri? address) =>
      address != null && (address.isScheme('http') || address.isScheme('https'))
      ? Media(address.replace(query: [if (address.hasQuery) address.query, 'segueTrack=$id'].join('&')).toString()).uri
      : null;

  /// The id of the track whose name ([_name]) is [track]: what comes after its last `/` or `=`.
  static String _idOf(String track) => track.substring(track.lastIndexOf(RegExp('[/=]')) + 1);

  /// Where [track]'s stream is, from its start; none where it can't say.
  static Uri? _addressOf(TrackSource track) {
    try {
      return track.address();
    } on Object catch (e) {
      _log.warning('no stream', e);
      return null;
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
      address = _addressOf(source); // none: mpv then opens the track's name, its stream as it was opened, if it has one
    }

    // The track's name where its stream is still the one it names, which mpv may have opened already.
    final stream = address == null || _streamName(_idOf(track), address) == track ? track : '$address';
    _loadingStream = stream;
    await native.setProperty('stream-open-filename', stream);
    await _openAheadAfter(track);

    if (!_disposed) {
      await _playWith(source.gain());
    }
  }

  /// Has mpv open ahead the track after [track] in the play order, as [track] plays (prefetch-playlist), where its name
  /// is its stream as it is now: not a file, which opens at once, nor a stream the track no longer gives (another
  /// quality, since it was named), which mpv would open for nothing. Such a track, where it now has a stream to open
  /// ahead, is named anew ([_rename]) after it.
  Future<void> _openAheadAfter(String track) async {
    final at = _inOrder.indexOf(track);
    final next = at < 0 ? null : _at(_inOrder, at + 1) ?? (repeat == Repeat.all ? _at(_inOrder, 0) : null);
    final i = next == null ? -1 : _opened.indexOf(next);
    final name = i < 0 ? null : _streamName(_idOf(next!), _addressOf(_tracks[i]));

    await _setPrefetch(name != null && name == next);

    if (name != null && name != next) {
      unawaited(_rename(next!, name));
    }
  }

  /// Has mpv open the next track ahead, or not ([_prefetch]).
  Future<void> _setPrefetch(bool on) async {
    if (on != _prefetch && !_disposed) {
      _prefetch = on;
      await (_player.platform as NativePlayer).setProperty('prefetch-playlist', on ? 'yes' : 'no');
    }
  }

  /// Names [track] [name] in its place, then has mpv open it ahead: mpv appends it, moves it after [track], and takes
  /// [track] out. Only a track after the one mpv plays, which the playlist events, until it is done, aren't about
  /// ([_ours]), and whose place in the play order and the order unshuffled stays.
  Future<void> _rename(String track, String name) {
    final opens = _opens;

    return _inTurn(() async {
      final native = _player.platform as NativePlayer;
      final playing = int.tryParse(await native.getProperty('playlist-playing-pos')) ?? -1;
      final from = _player.state.playlist.medias.indexWhere((media) => media.uri == track);
      final i = _opened.indexOf(track);
      final at = _inOrder.indexOf(track);

      if (opens != _opens || from <= playing || i < 0 || at < 0) {
        return;
      }

      _opened = [..._opened]..[i] = name;
      _inOrder = [..._inOrder]..[at] = name;
      _rearranging = true;

      try {
        await _player.add(Media(name));

        final last = _player.state.playlist.medias.length - 1;

        if (last > from + 1) {
          await _player.move(last, from + 1);
        }

        await _player.remove(from);
      } finally {
        _rearranging = false;
      }

      await _setPrefetch(true);
    });
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

    // Stopped, or another load or a jump came, as it loaded: what it would have waited for is no longer its.
    if (loads != _loads) {
      loaded?.ignore();
      return;
    }

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
      await _withAudio(_player.play);
    }
  }

  /// Plays through [play], once mpv's audio output is open: where it was held, it opens first, and then plays unless a
  /// pause or another load came meanwhile. mpv opening it on a track that has loaded seeks to where it is, which the
  /// position hardly notices.
  Future<void> _withAudio(Future<void> Function() play) async {
    if (_audioHeld) {
      final loads = _loads;
      final pauses = _pauses;

      await (_audioOpening ??= _openAudio());

      if (loads != _loads || pauses != _pauses) {
        return;
      }
    }

    await play();
  }

  Future<void> _openAudio() async {
    await (_player.platform as NativePlayer).setProperty('ao', _output);
    _audioHeld = false;
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

    return _withAudio(_player.play);
  }

  @override
  Future<void> pause() {
    _playOnLoad = false;
    _pauses++;

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
      return _withAudio(() => _player.jump(index)); // which plays too
    }

    // mpv ignores a jump to the track it is on. Once the queue has ended, media_kit's jump is the one
    // that works, since its play would go back to the first track. A stream that starts later, or can't seek, loads
    // again from the start.
    await _seek(Duration.zero, play: true);
    await _withAudio(_player.play);
  }

  /// mpv's warnings and errors, by their prefix and text, that say nothing wrong, every time what they tell of happens:
  /// not for the app's log.
  static const _unremarkable = {
    // As it reads the queue from the file media_kit writes it to (`loadlist`), each time it opens one.
    ('playlist', 'Reading plaintext playlist.'),
    // FFmpeg's, of an MP3 with no frame that says its length (Xing's or VBRI's), which some encoders leave out: the
    // length it works out from the bitrate is right for a constant one.
    ('ffmpeg/demuxer', 'mp3: Estimating duration from bitrate, this may be inaccurate'),
    // FFmpeg's, of an MP3 with its cover in its tags, which it takes for a video stream it can't tell the size of, and
    // its advice that follows: the audio plays all the same.
    ('ffmpeg/demuxer', 'mp3: Could not find codec parameters for stream 1 (Video: mjpeg, none): unspecified size'),
    (
      'ffmpeg/demuxer',
      "Consider increasing the value for the 'analyzeduration' (500000) and 'probesize' (5000000) options",
    ),
    // media_kit's, as each player starts: where libmpv was built without Lua (Android's, iOS's), so without the
    // on-screen controller it turns off, and where it is older than the subtitles' option it sets (Android's, mpv 0.35).
    ('media_kit', 'error: property not found _setProperty(osc, 1)'),
    ('media_kit', 'error: property not found _setProperty(subs-fallback, 1)'),
  };

  /// Follows mpv's loads, and their failures: a stream that fails to open is the loading track's where it is the track's
  /// name or the stream the on_load hook gave it; another is one mpv opened ahead. Its warnings and errors go to the
  /// app's log, but those [_unremarkable], and not its info, which every track's address would bury them in.
  void _logged(PlayerLog log) {
    final remarkable = !_unremarkable.contains((log.prefix, log.text));

    switch (log.level) {
      case 'warn' when remarkable:
        _log.warning('mpv ${log.prefix}: ${log.text}');
      case 'error' || 'fatal' when remarkable:
        _log.severe('mpv ${log.prefix}: ${log.text}');
    }

    if (log.prefix == 'cplayer' && log.text.startsWith('Playing: ')) {
      final track = _loading = log.text.substring('Playing: '.length);
      _loadingStream = null;
      _loaded = _lengthKnown = false;
      unawaited(_watchLoad(track, ++_loadsLogged));
    } else if (log.level == 'error' &&
        (log.text == 'Failed to open $_loading.' ||
            log.text == 'Failed to open $_loadingStream.' ||
            log.text == 'Failed to recognize file format.')) {
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
        await _learnLength(logged);
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Learns whether mpv knows how long the track that loaded, as the [logged]th, is: a file, or a stream it can seek
  /// in, whose length it read. One the media server transcodes as it goes, of no length told, it can't seek in, and its
  /// duration is as long as what came of it so far.
  Future<void> _learnLength(int logged) async {
    final String seekable;

    try {
      seekable = await (_player.platform as NativePlayer).getProperty('seekable');
    } on Object {
      return; // disposed meanwhile
    }

    if (logged == _loadsLogged) {
      _lengthKnown = seekable == 'yes';
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
      address = from == Duration.zero ? _tracks[i].address() : await _tracks[i].addressFrom(from);
    } on Object catch (e) {
      _log.warning('no stream for $track from $from', e);
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
  Future<void> setVolume(int volume) async {
    _volume = volume;
    await _playAtVolume();

    if (!_disposed) {
      _changes.add(null);
    }
  }

  @override
  Future<void> setLevel(double level) async {
    _level = level.clamp(0, 1);
    await _playAtVolume();
  }

  /// Gives mpv the volume, at the level set. mpv makes its volume a gain by its cube (audio_update_volume, in its
  /// player/audio.c), so the level, a gain, goes in it by its cube root.
  Future<void> _playAtVolume() async {
    if (!_disposed) {
      await _player.setVolume(_volume * pow(_level, 1 / 3).toDouble());
    }
  }

  @override
  Future<void> updateGain() async {
    await _ready;
    final track = _at(_inOrder, _index);
    final i = track == null ? -1 : _opened.indexOf(track);

    if (i >= 0 && !_disposed) {
      await _playWith(_tracks[i].gain());
    }
  }

  /// Plays the current track, and the next until another gain, with [gain]. mpv's ReplayGain reads a file's tags, adds
  /// its preamp to their gain, and lowers it where their peak says it would clip; with it off, or for a file without
  /// them, it plays every track with its fallback gain (player/audio.c, compute_replaygain), which then gives
  /// [TrackGain.decibels]. It reckons the gain again as each track's audio starts, and right away as these change.
  Future<void> _playWith(TrackGain gain) async {
    final native = _player.platform as NativePlayer;

    await native.setProperty('replaygain-preamp', '${gain.preamp}');
    await native.setProperty('replaygain', gain.tagged ? (gain.album ? 'album' : 'track') : 'no');
    // mpv takes fallbacks from -200 dB to 60 dB.
    await native.setProperty('replaygain-fallback', '${gain.decibels.clamp(-200, 60)}');
  }

  /// The equalizer is mpv's audio filters (af): none while it is off, and on, the bands in one lavfi graph, each one of
  /// FFmpeg's equalizer. Of FFmpeg's filters, media_kit's libmpv for Android has only that one (iOS's has no volume
  /// either), so what comes before the bands is mpv's or an equalizer too. First the audio goes to 48 kHz, in floats, by
  /// mpv's format filter, before which mpv puts its own resampler: FFmpeg's equalizer leaves out a band past half a
  /// track's sample rate, but one at half of it (16 kHz, in a track of 32 kHz) silences the track. Then it goes down by
  /// as much as the bands raise the frequency they raise most, by an equalizer whose band, of a Q of 0.0001, takes in
  /// every frequency but those within a hertz or two of none and of half the sample rate: it makes them all quieter by
  /// its gain. A graph for each band would do on Linux, but on Android (mpv 0.35, FFmpeg 6.0) a second lavfi filter
  /// after mpv's resampler fails every frame ("could not pass frame to filter"). Given the graph again with a band
  /// moved, mpv makes only it anew, keeping the format filter (mp_output_chain_update_filters, in its
  /// filters/f_output_chain.c), and the audio output goes on; turning the equalizer on or off changes what mpv sends to
  /// the output, which starts again: the sound stops for a moment.
  @override
  Future<void> setEqualizer(Map<int, double> gains) async {
    await _ready;

    if (_disposed) {
      return;
    }

    final graph = [
      'equalizer=f=${_equalizerRate ~/ 4}:t=q:w=0.0001:g=${(-_loudestBoost(gains)).toStringAsFixed(2)}',
      for (final MapEntry(key: frequency, value: gain) in gains.entries)
        'equalizer=f=$frequency:t=o:w=1:g=${gain.toStringAsFixed(2)}',
    ];

    await (_player.platform as NativePlayer).setProperty(
      'af',
      gains.isEmpty ? '' : 'format=format=floatp:srate=$_equalizerRate,lavfi=[${graph.join(',')}]',
    );
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
    await _ended.close();
    await _loadsDone.close();
    await _player.dispose();
  }
}
