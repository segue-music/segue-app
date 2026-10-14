import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../equalizer_choice.dart';
import '../quality_choice.dart';
import '../replay_gain_choice.dart';
import '../segue/client.dart';
import '../segue/protocol.dart';
import '../server/models.dart';
import '../server/server.dart';
import '../volume_choice.dart';
import 'crossfade_engine.dart';
import 'engine.dart';

final _log = Logger('PlayerController');

/// This device's player: the queue, playback, and the commands other devices send it.
class PlayerController extends ChangeNotifier {
  /// Plays on [engine], or, while [crossfade] is more than none, on the one [crossfadeEngine] makes, which crossfades
  /// the songs ([CrossfadeEngine]): as it goes on or off, the queue goes on on the other one, from where it was.
  /// Streams each song in the quality that [quality] gives as it loads; with none, the files as they are. Levels their
  /// loudness [replayGain]'s way, the one that plays too as it changes; with none, not at all. Plays them through
  /// [equalizer], as it changes too; with none, as they are. Goes on after the queue's last song with songs like it
  /// while [autoplay] is on, and takes those that haven't played out of the queue as it goes off; with none, the music
  /// stops there. Starts at the volume [volume] kept, and keeps there the one set ([setVolume]); with none, at all of it.
  PlayerController(
    AudioEngine engine,
    this._api, {
    this._quality,
    this._replayGain,
    this._equalizer,
    this._autoplay,
    this._crossfade,
    this._crossfadeEngine,
    this._volume,
  }) : _gapless = engine,
       _engine = engine {
    // Crossfading from the start: the queue, still empty, has nothing to take along.
    if (_crossfading) {
      _engine = _crossfadeEngine!();
    }

    if (_volume != null) {
      unawaited(_engine.setVolume(_volume.value));
    }

    _follow(_engine);
    _replayGain?.addListener(_updateGain);
    _autoplay?.addListener(_autoplayTurned);
    _crossfade?.addListener(_crossfadeTurned);

    if (_equalizer != null) {
      _equalizer.addListener(_equalize);
      _equalize();
    }
  }

  /// The engine of songs one right after the other (gapless), and the one the songs play on, it or one that crossfades
  /// them.
  final AudioEngine _gapless;
  AudioEngine _engine;
  final MediaServer _api;
  final StreamQuality Function()? _quality;
  final ValueListenable<ReplayGainMode>? _replayGain;
  final ValueListenable<EqualizerSettings>? _equalizer;
  final ValueListenable<bool>? _autoplay;
  final ValueListenable<Duration>? _crossfade;
  final AudioEngine Function()? _crossfadeEngine;
  final VolumeChoice? _volume;
  late StreamSubscription<void> _subscription;
  late StreamSubscription<void> _endedSubscription;
  final _songEnded = StreamController<void>.broadcast();
  // The songs as playQueue got them, with those addToQueue added among them (their order unshuffled), and their tracks
  // for the engine; and _queue: them in the engine's play order (shuffled, or not).
  List<Song> _opened = const [];
  List<TrackSource> _tracks = const [];
  List<int> _order = const [];
  List<Song> _queue = const [];
  bool _queueChanged = false;

  // The changes to the queue (adding, moving and removing songs), one after another: each finds it as the one before
  // left it. While one is under way, the engine's changes wait for it to end ([_changeHeld]), which tells of them all:
  // until then the songs here aren't yet where the engine has them, and the current one's place, which may have moved,
  // would come with the songs as they were.
  Future<void> _edits = Future.value();
  bool _editing = false;
  bool _changeHeld = false;

  // While a queue opens in modes it was given (playQueue's repeat and shuffle): the engine's changes wait as for an
  // edit, since the queue before, shuffled anew as shuffle goes on, isn't what is to play.
  bool _opening = false;

  // The last song of the queue that autoplay asked for songs like, as it played: once for each song in a queue, until
  // it goes off. And the songs it added to the queue, by themselves rather than their ids: the same song added otherwise
  // isn't one of them.
  Song? _autoplayedAfter;
  final _autoplayed = Set<Song>.identity();

  bool _disposed = false;

  /// Receives this player's state after every change, for the hub.
  void Function(PlayerState state)? onReport;

  List<Song> get queue => _queue;
  int get index => _engine.index;
  bool get playing => _engine.playing;
  Duration get position => _engine.position;
  int get volume => _engine.volume;
  Repeat get repeat => _engine.repeat;
  bool get shuffle => _engine.shuffle;
  Song? get current => index >= 0 && index < _queue.length ? _queue[index] : null;

  /// Whether the current song failed to load: the player stopped on it, paused.
  bool get failed => _engine.failed;

  /// Fires as a song plays to its end ([AudioEngine.ended]): as the next one, or the same one again, starts, or the queue
  /// ends; crossfading, as the next one starts fading in.
  Stream<void> get songEnded => _songEnded.stream;

  /// Takes [engine]'s changes, and the songs it plays to their end, for this player's.
  void _follow(AudioEngine engine) {
    _subscription = engine.changes.listen((_) {
      if (_editing || _opening) {
        _changeHeld = true;
      } else {
        _changed();
      }
    });
    _endedSubscription = engine.ended.listen(_songEnded.add);
  }

  /// Whether the songs are to crossfade, as [_crossfade] says.
  bool get _crossfading => _crossfadeEngine != null && (_crossfade?.value ?? Duration.zero) > Duration.zero;

  /// The crossfade went on or off: the queue goes on on the other engine, once the changes to it before are done.
  void _crossfadeTurned() {
    if (_crossfading == identical(_engine, _gapless)) {
      unawaited(_edit(_changeEngine));
    }
  }

  /// Plays the queue on the engine the crossfade calls for ([_crossfading]), where it doesn't already: from where it
  /// was on the one before, playing or not as it was, in the same order, shuffled or not, as loud, repeating as it did,
  /// through the equalizer. The one before stops; the one that crossfades goes, with its decks.
  Future<void> _changeEngine() async {
    final crossfading = _crossfading;

    if (crossfading == !identical(_engine, _gapless)) {
      return;
    }

    final before = _engine;
    final engine = crossfading ? _crossfadeEngine!() : _gapless;
    final opened = _opened;
    final tracks = _tracks;
    final order = before.order;
    final current = before.index >= 0 && before.index < order.length ? order[before.index] : 0;
    final playing = before.playing;
    final (changes, ended) = (_subscription, _endedSubscription);
    // From now on, what the player is asked goes to it, and what it says comes from it.
    _engine = engine;
    _follow(engine);
    await changes.cancel();
    await ended.cancel();
    await before.pause();

    final position = before.position;

    await engine.setVolume(before.volume);
    await engine.setRepeat(before.repeat);
    await engine.setShuffle(before.shuffle);

    if (_equalizer != null) {
      _equalize();
    }

    // Unless another queue came meanwhile, which plays on it already.
    if (tracks.isNotEmpty && identical(_opened, opened)) {
      await engine.open(tracks, index: current, position: position, play: playing, order: order);
    }

    if (identical(before, _gapless)) {
      await before.stop();
    } else {
      await before.dispose();
    }

    _changeHeld = true; // told of once done, by the edit
  }

  PlaybackStatus get status => _queue.isEmpty
      ? PlaybackStatus.stopped
      : playing
      ? PlaybackStatus.playing
      : PlaybackStatus.paused;

  /// Plays [songs] from the one at [index], at [position], or, unless [play], only takes them there. With [repeat] and
  /// [shuffle], in those modes, and otherwise in the player's own: shuffled, in [order] where given (for each place in
  /// the play order, the index of its song in [songs]), else in one of its own. [index] is in [songs] either way.
  Future<void> playQueue(
    List<Song> songs, {
    int index = 0,
    Duration position = Duration.zero,
    bool play = true,
    Repeat? repeat,
    bool? shuffle,
    List<int>? order,
  }) async {
    _opening = repeat != null || shuffle != null;

    try {
      // The modes first: the engine takes the order it is given only with shuffle on. Then the songs, as the engine
      // gets them, so that they never show with the place in the queue before.
      if (repeat != null) {
        await _engine.setRepeat(repeat);
      }

      if (shuffle != null) {
        await _engine.setShuffle(shuffle);
      }

      _queue = _opened = List.unmodifiable(songs);
      _autoplayedAfter = null; // the same songs again, as an album played again, go on again
      _autoplayed.clear();
      _tracks = [for (final song in songs) _track(song)];
      _order = const []; // so that the engine's order, shuffled or not, is taken up
      _queueChanged = true;
      await _engine.open(_tracks, index: index, position: position, play: play, order: order);
    } finally {
      _opening = false;
    }

    _changed();
  }

  /// Adds [songs] to the queue, the current song playing on: right after it if [next], otherwise after the last one,
  /// where they stay as shuffle goes off (SPEC.md, section 5). To an empty queue, they are the queue, paused at the
  /// first.
  Future<void> addToQueue(List<Song> songs, {required bool next}) => _edit(() => _add(songs, next: next));

  /// Moves the song at [from] in [queue] to [to], the place it then has, the current song playing on. Shuffled, that is
  /// a move in the play order alone, which shuffle going off forgets (SPEC.md, section 5).
  Future<void> moveInQueue(int from, int to) => _edit(() => _move(from, to));

  /// Takes the song at [index] out of [queue]; not the current one, which plays on (SPEC.md, section 5).
  Future<void> removeFromQueue(int index) => _edit(() => _remove(index));

  /// Makes [change] to the queue once the changes before it are done.
  Future<void> _edit(Future<void> Function() change) {
    final done = _edits.then((_) async {
      _editing = true;

      try {
        await change();
      } finally {
        _editing = false;

        // One that ended without telling of the queue, as one that had nothing to change.
        if (_changeHeld) {
          _changed();
        }
      }
    });
    _edits = done.then<void>((_) {}, onError: (Object _) {});

    return done;
  }

  Future<void> _add(List<Song> songs, {required bool next}) async {
    if (songs.isEmpty) {
      return;
    }

    if (_queue.isEmpty) {
      return playQueue(songs, play: false);
    }

    final opened = _opened;
    final tracks = [for (final song in songs) _track(song)];
    final at = await _engine.add(tracks, next: next);

    // Another queue came meanwhile.
    if (at < 0 || !identical(_opened, opened)) {
      return;
    }

    _opened = List.unmodifiable([..._opened.take(at), ...songs, ..._opened.skip(at)]);
    _tracks = [..._tracks.take(at), ...tracks, ..._tracks.skip(at)];
    _order = const [];
    _queueChanged = true;
    _changed();
  }

  Future<void> _move(int from, int to) async {
    if (!_inQueue(from) || !_inQueue(to)) {
      throw const CommandFailed('no such track');
    }

    if (from == to) {
      return;
    }

    final opened = _opened;
    final unshuffled = await _engine.move(from, to);

    // Another queue came meanwhile.
    if (!identical(_opened, opened)) {
      return;
    }

    if (unshuffled != null) {
      final song = _opened[unshuffled.from];
      final track = _tracks[unshuffled.from];
      _opened = List.unmodifiable(
        [..._opened]
          ..removeAt(unshuffled.from)
          ..insert(unshuffled.to, song),
      );
      _tracks = [..._tracks]
        ..removeAt(unshuffled.from)
        ..insert(unshuffled.to, track);
    }

    _order = const [];
    _queueChanged = true;
    _changed();
  }

  Future<void> _remove(int index) async {
    if (!_inQueue(index)) {
      throw const CommandFailed('no such track');
    }

    if (index == this.index) {
      throw const CommandFailed('current track');
    }

    if (await _takeOut(index)) {
      _changed();
    }
  }

  /// Takes the song at [index] in [queue] out of the engine's tracks and the songs here, which [queue] follows at the
  /// next [_changed]: whether it did, which it doesn't where another queue came meanwhile.
  Future<bool> _takeOut(int index) async {
    final opened = _opened;
    final at = await _engine.remove(index);

    // Another queue came meanwhile.
    if (at < 0 || !identical(_opened, opened)) {
      return false;
    }

    _opened = List.unmodifiable([..._opened]..removeAt(at));
    _tracks = [..._tracks]..removeAt(at);
    _order = const [];
    _queueChanged = true;

    return true;
  }

  bool _inQueue(int index) => index >= 0 && index < _queue.length;

  /// The engine's track of [song]: its stream, and its gain, by its place in the queue as it loads.
  TrackSource _track(Song song) {
    late final TrackSource track;
    track = TrackSource.resolved(
      () => _stream(song.id),
      addressFrom: (from) => _streamFrom(song.id, from),
      gain: () => _gain(song, _tracks.indexOf(track)),
      duration: song.duration,
    );

    return track;
  }

  /// How loud [song], at [index] of the songs in their order unshuffled (-1: no longer in the queue), plays, as it
  /// loads: by the gain the media server gives for it, or else by its file's tags; its album's or its own, as the way
  /// picked says; [replayGainPreamp] louder.
  TrackGain _gain(Song song, int index) {
    final mode = _replayGain?.value ?? ReplayGainMode.off;

    if (mode == ReplayGainMode.off) {
      return TrackGain.none;
    }

    final album = switch (mode) {
      ReplayGainMode.album => true,
      ReplayGainMode.automatic => !shuffle && index >= 0 && _amongItsAlbum(_opened, index),
      _ => false,
    };
    final replayGain = song.replayGain;

    return replayGain == null
        ? TrackGain.tagged(album: album, preamp: replayGainPreamp)
        : TrackGain(replayGain.decibels(album: album, preamp: replayGainPreamp));
  }

  /// Whether the song at [index] of [songs] plays among its album's: the song before or after it is of the same album,
  /// by its id, or by its name where the songs have no album ids, as those another device sent.
  static bool _amongItsAlbum(List<Song> songs, int index) {
    final song = songs[index];

    bool sameAlbum(Song other) => song.albumId != null && other.albumId != null
        ? song.albumId == other.albumId
        : (song.album ?? '').isNotEmpty && song.album == other.album;

    return (index > 0 && sameAlbum(songs[index - 1])) || (index + 1 < songs.length && sameAlbum(songs[index + 1]));
  }

  /// The way the songs are levelled changed: the song that plays changes with it.
  void _updateGain() => unawaited(_engine.updateGain());

  /// The equalizer changed: the songs play through it as it is now, the one that plays too.
  void _equalize() => unawaited(_engine.setEqualizer(_equalizer!.value.bandGains));

  /// Where the song whose id is [songId] streams from ([TrackSource.resolved]), in the quality picked as it loads.
  Uri _stream(String songId) => _api.streamUrl(songId, maxBitRate: _quality?.call().maxBitRate);

  /// Where the song whose id is [songId] streams from, from [from] on ([TrackSource.resolved]), in the quality picked as
  /// it loads: transcoded, since the files as they are can seek.
  Future<Uri?> _streamFrom(String songId, Duration from) async {
    final maxBitRate = _quality?.call().maxBitRate;

    return maxBitRate == null ? null : _api.transcodedStreamUrl(songId, maxBitRate: maxBitRate, from: from);
  }

  Future<void> play() => _engine.play();

  Future<void> pause() => _engine.pause();

  Future<void> toggle() => playing ? _engine.pause() : _engine.play();

  /// The next track; after the last one, the first, unless repeat is off (SPEC.md, section 5).
  Future<void> next() => _jump(index + 1 >= _queue.length && repeat != Repeat.off ? 0 : index + 1);

  /// Back to the start of the track; in its first seconds, to the previous one (SPEC.md, section 5).
  Future<void> previous() async {
    if (index == 0 || position > previousGrace) {
      return seek(Duration.zero);
    }

    await _jump(index - 1);
  }

  /// The track at [index] of [queue] from its start, playing; the current one starts over.
  ///
  /// Like [next] and [previous], going to another track turns repeating one track into repeating the
  /// queue.
  Future<void> jump(int index) async {
    await _jump(index);
    _changed(); // starting the current track over doesn't show in the engine's changes
  }

  /// Up to where "previous" goes to the previous track rather than to the start of this one.
  static const previousGrace = Duration(seconds: 3);

  Future<void> seek(Duration position) async {
    await _engine.seek(position);
    _changed(); // a seek doesn't show in the engine's changes
  }

  /// Plays at [volume], from 0 to 100, from the next launch on too, unless not to [keep] it: a fade's, on its way.
  Future<void> setVolume(int volume, {bool keep = true}) async {
    final clamped = volume.clamp(0, 100);

    if (keep) {
      unawaited(_volume?.pick(clamped));
    }

    await _engine.setVolume(clamped);
  }

  Future<void> setRepeat(Repeat mode) async {
    await _engine.setRepeat(mode);
    _changed();
  }

  Future<void> setShuffle(bool on) async {
    await _engine.setShuffle(on);
    _changed();
  }

  Future<void> stop() async {
    await _engine.stop();
    _queue = _opened = const [];
    _autoplayed.clear();
    _tracks = const [];
    _order = const [];
    _queueChanged = true;
    _changed();
  }

  /// Carries out a command from another device.
  Future<void> obey(Command command) async {
    switch (command.action) {
      case CommandAction.play:
        await _engine.play();
      case CommandAction.pause:
        await _engine.pause();
      case CommandAction.toggle:
        await toggle();
      case CommandAction.stop:
        await stop();
      case CommandAction.next:
        await next();
      case CommandAction.previous:
        await previous();
      case CommandAction.jump:
        await jump(command.index!);
      case CommandAction.seek:
        await seek(Duration(milliseconds: command.positionMs!));
      case CommandAction.setVolume:
        await setVolume(command.volume!);
      case CommandAction.setRepeat:
        await setRepeat(command.repeat!);
      case CommandAction.setShuffle:
        await setShuffle(command.shuffle!);
      case CommandAction.setQueue:
        await _setQueue(command);
      case CommandAction.addToQueue:
        // As for setQueue, the items the hub couldn't express in this device's API are skipped.
        final playable = [
          for (final item in command.queue!)
            if (item.id != null) _songOf(item),
        ];

        if (playable.isEmpty) {
          throw const CommandFailed('nothing playable');
        }

        await addToQueue(playable, next: command.next!);
      case CommandAction.moveInQueue:
        await moveInQueue(command.index!, command.to!);
      case CommandAction.removeFromQueue:
        await removeFromQueue(command.index!);
    }
  }

  /// The song of a queue [item] that came from elsewhere (another device, the last playback the hub kept), by the id
  /// the media server has for it now ([MediaServer.currentId]): one from before the server gave its items new ones
  /// then goes in the reports as the server and the other devices have it.
  Song _songOf(QueueItem item) =>
      Song.fromQueueItem(QueueItem.fromJson({...item.toJson(), 'id': _api.currentId(item.id!)}));

  /// Plays the queue of a setQueue, from its current item, in the modes it brings where it brings them (SPEC.md, section
  /// 5). Items the hub couldn't express in this device's API can't be played here: they are skipped, the same track
  /// staying current (skipped itself, the next one). Shuffled, the items come in their play order, which they play in,
  /// with each one's place unshuffled ([Command.order]), which shuffle going off takes them back to; without one, the
  /// order they came in.
  Future<void> _setQueue(Command command) async {
    final items = command.queue!;
    final shuffle = command.shuffle;
    final given = command.order;
    // Each item's place unshuffled: as it came, unless shuffled with its places.
    final places = shuffle == true && given != null && given.length == items.length
        ? given
        : [for (var i = 0; i < items.length; i++) i];
    final unshuffled = List<QueueItem?>.filled(items.length, null);

    for (final (i, item) in items.indexed) {
      unshuffled[places[i]] = item;
    }

    // The playable ones, unshuffled, and the place each of those has among them.
    final kept = <int, int>{};
    final songs = <Song>[];

    for (final (place, item) in unshuffled.indexed) {
      if (item?.id != null) {
        kept[place] = songs.length;
        songs.add(_songOf(item!));
      }
    }

    if (songs.isEmpty) {
      throw const CommandFailed('nothing playable');
    }

    final order = [
      for (final (i, item) in items.indexed)
        if (item.id != null) kept[places[i]]!,
    ];
    final skippedBefore = items.take(command.index!).where((item) => item.id == null).length;
    final current = order[(command.index! - skippedBefore).clamp(0, order.length - 1)];

    await playQueue(
      songs,
      index: current,
      position: Duration(milliseconds: command.positionMs!),
      play: command.play!,
      repeat: command.repeat,
      shuffle: shuffle,
      order: shuffle == true ? order : null,
    );
  }

  /// This player's state for the hub. The queue goes only when it changed, or when [full]; shuffled, with each song's
  /// place unshuffled (SPEC.md, section 4).
  PlayerState report({bool full = false}) {
    final queue = full || _queueChanged;

    return PlayerState(
      status: status,
      positionMs: position.inMilliseconds,
      queue: queue ? [for (final song in _queue) song.toQueueItem()] : null,
      index: index,
      volume: volume,
      repeat: repeat,
      shuffle: shuffle,
      order: queue && shuffle && _order.length == _queue.length ? _order : null,
    );
  }

  Future<void> _jump(int to) async {
    if (to < 0 || to >= _queue.length) {
      throw const CommandFailed('no such track');
    }

    // Another track ends the repeat of the one it leaves, and the queue goes on repeating.
    if (to != index && repeat == Repeat.one) {
      await _engine.setRepeat(Repeat.all);
    }

    await _engine.jump(to);
  }

  void _changed() {
    _changeHeld = false;
    _followOrder();
    notifyListeners();

    final state = report();
    _queueChanged = false;
    onReport?.call(state);
    _autoplayAtEnd();
  }

  /// Autoplay turned on, the queue goes on from its last song, should it play; off, the songs autoplay added that
  /// haven't played go out of the queue, and turned on again on the same song, it asks for songs like it again.
  void _autoplayTurned() {
    if (_autoplay!.value) {
      _autoplayAtEnd();
      return;
    }

    _autoplayedAfter = null;
    unawaited(_edit(_removeAutoplayed));
  }

  /// Takes out of the queue the songs autoplay added after the current one, which play on, with one report.
  Future<void> _removeAutoplayed() async {
    final queue = _queue;
    var removed = false;

    // From the last, so that the places of those before stay as they were. Up to the current song, which may have moved
    // on to one of them meanwhile.
    for (var i = queue.length - 1; i > index; i--) {
      if (!_autoplayed.contains(queue[i])) {
        continue;
      }

      if (!await _takeOut(i)) {
        return; // another queue, which has nothing of autoplay's
      }

      removed = true;
    }

    if (removed) {
      _changed();
    }
  }

  /// How many songs autoplay adds at a time: few, so that songs added to the queue after them don't go far behind.
  static const autoplaySize = 10;

  /// The queue's last song playing, repeat off, with autoplay on: the queue goes on with songs like it, which the media
  /// server is asked for once for the song, as it starts, so that they are there as it ends, and play right after it.
  void _autoplayAtEnd() {
    final song = current;

    if (!(_autoplay?.value ?? false) ||
        song == null ||
        !playing ||
        repeat != Repeat.off ||
        index != _queue.length - 1 ||
        identical(song, _autoplayedAfter)) {
      return;
    }

    _autoplayedAfter = song;
    unawaited(_continueAfter(song));
  }

  /// Adds songs like [song] ([MediaServer.similarSongs]) after it, at the end of the queue, but for those the queue
  /// already has: [autoplaySize] at most. None where [song] is no longer last (another queue, or songs added after it),
  /// repeat or autoplay went on or off meanwhile, or the media server can't say: the music then stops after it.
  Future<void> _continueAfter(Song song) async {
    final List<Song> similar;

    try {
      similar = await _api.similarSongs(song);
    } on Object catch (e) {
      _log.warning('no songs like ${song.id}', e);
      return;
    }

    await _edit(() async {
      if (_disposed || !identical(_queue.lastOrNull, song) || repeat != Repeat.off || !(_autoplay?.value ?? false)) {
        return;
      }

      final queued = {for (final other in _opened) other.id};
      final added = [
        for (final other in similar)
          if (queued.add(other.id)) other,
      ];
      final songs = added.take(autoplaySize).toList();

      _autoplayed.addAll(songs);
      await _add(songs, next: false);
    });
  }

  /// Puts [_queue] in the engine's play order, which a shuffle changes.
  void _followOrder() {
    final order = _engine.order;

    if (listEquals(order, _order) || order.length != _opened.length) {
      return;
    }

    _order = List.unmodifiable(order);
    _queue = List.unmodifiable([for (final i in order) _opened[i]]);
    _queueChanged = true;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _replayGain?.removeListener(_updateGain);
    _equalizer?.removeListener(_equalize);
    _autoplay?.removeListener(_autoplayTurned);
    _crossfade?.removeListener(_crossfadeTurned);
    // Once the changes to the queue under way are done, the engine changing among them.
    await _edits;
    await _subscription.cancel();
    await _endedSubscription.cancel();
    await _songEnded.close();

    if (!identical(_engine, _gapless)) {
      await _engine.dispose();
    }

    await _gapless.dispose();
    super.dispose();
  }
}
