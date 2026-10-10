import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../segue/protocol.dart';
import 'engine.dart';

/// Plays the queue with each track fading into the next (crossfade): as a track nears its end, the next one starts,
/// quiet, and gets louder as the one before gets quieter, the two playing together for the length given.
///
/// mpv plays one track at a time, so the tracks take turns on two decks ([Deck], each a [MediaKitEngine] of one track):
/// a track plays on its deck to its end, while the next one fades in on the other. The queue is the engine's own, with
/// its play order, of which the decks know nothing. A little before its turn ([openAhead]), the next track opens on the
/// other deck, paused, so that it starts at once. Its turn starts with the crossfade: from then on it is the current
/// track, the one before fading out under it. Each fades at equal power (sine and cosine), so that the two together are
/// about as loud as either alone.
///
/// Going to another track (a jump, opening another queue) and seeking end a crossfade at once: the track fading out
/// stops. A track repeating itself starts over on its deck, as with no crossfade, and one whose length is unknown plays
/// to its end, the next one starting then. There is no gapless playback, which only one player's playlist has: where
/// the tracks follow one another without a crossfade, there is a moment between them.
class CrossfadeEngine implements AudioEngine {
  /// Crossfades the tracks for as long as [length] gives as each crossfade starts. [decks] are the decks the tracks
  /// take turns on, two; [random] shuffles the tracks.
  CrossfadeEngine(this._length, {@visibleForTesting List<Deck>? decks, @visibleForTesting Random? random})
    : _decks = decks ?? [MediaKitEngine(), MediaKitEngine()],
      _random = random ?? Random() {
    for (final deck in _decks) {
      _subscriptions
        ..add(deck.changes.listen((_) => _deckChanged(deck)))
        ..add(deck.ended.listen((_) => _deckEnded(deck)));
    }
  }

  /// How often the engine looks at where the decks are, to start a crossfade, and to set their levels as it goes.
  static const tick = Duration(milliseconds: 50);

  /// How long before its turn the next track opens on the other deck, paused, so that it has loaded as it starts.
  static const openAhead = Duration(seconds: 10);

  final Duration Function() _length;
  final List<Deck> _decks;
  final Random _random;
  final _subscriptions = <StreamSubscription<void>>[];
  final _changes = StreamController<void>.broadcast();
  final _ended = StreamController<void>.broadcast();
  bool _disposed = false;

  // The tracks as open got them, with those added among them (their order unshuffled), and the play order: for each
  // place in it, the index of a track among them.
  List<TrackSource> _tracks = const [];
  List<int> _order = const [];
  int _index = 0;
  Repeat _repeat = Repeat.off;
  bool _shuffle = false;
  int _volume = 100;

  // The deck whose turn it is, which plays the current track. The other one fades out the track before it
  // ([_fadingOut]), holds the next one, opened paused, for its turn ([_ahead]), or nothing. The track each holds, and
  // the level each plays at.
  int _turn = 0;
  final _held = List<TrackSource?>.filled(2, null);
  final _levels = [1.0, 1.0];
  TrackSource? _ahead;

  // The crossfade under way: the current track fading in, the one before fading out, each over [_fade].
  bool _fadingIn = false;
  bool _fadingOut = false;
  Duration _fade = Duration.zero;

  // Counts the starts of a track on its deck: a start that another one took over leaves the rest to it. While one is
  // under way, the engine plays as it was asked to, the deck's own playing coming a moment later.
  int _starts = 0;
  bool _starting = false;

  // The queue ended, repeat off, on its last track: play starts it over, from the first.
  bool _queueEnded = false;

  Timer? _ticks;

  Deck get _current => _decks[_turn];
  Deck get _other => _decks[1 - _turn];

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<void> get ended => _ended.stream;

  @override
  bool get playing => _current.playing || (_starting && !_current.failed);

  @override
  int get index => _index;

  @override
  Duration get position => _current.position;

  @override
  int get volume => _volume;

  @override
  List<int> get order => _order;

  @override
  Repeat get repeat => _repeat;

  @override
  bool get shuffle => _shuffle;

  @override
  bool get failed => _current.failed;

  /// Tells of a change; of nothing once disposed.
  void _tellChange() {
    if (!_disposed) {
      _changes.add(null);
    }
  }

  /// Tells of a track that played to its end; of nothing once disposed.
  void _tellEnded() {
    if (!_disposed) {
      _ended.add(null);
    }
  }

  /// The track at [place] in the play order; none where there is no such place.
  TrackSource? _trackAt(int place) => place >= 0 && place < _order.length ? _tracks[_order[place]] : null;

  /// The place in the play order of the track after the current one: after the last, the first, repeating them; none
  /// after the last, nor repeating the current one, which its deck starts over by itself.
  int? get _next => _tracks.isEmpty || _repeat == Repeat.one
      ? null
      : _index + 1 < _order.length
      ? _index + 1
      : _repeat == Repeat.all
      ? 0
      : null;

  /// A deck repeats its track only where the current one repeats: the engine itself goes from one track to the next.
  Repeat get _deckRepeat => _repeat == Repeat.one ? Repeat.one : Repeat.off;

  /// How long [track], on [deck], is: as its stream says, or else as the media server does; zero where neither says.
  static Duration _lengthOf(TrackSource track, Deck deck) {
    final known = deck.duration;
    return known > Duration.zero ? known : track.duration ?? Duration.zero;
  }

  /// How long the crossfade from a track of [length] into one of [next] (where the media server says) lasts: the length
  /// picked, but half of either at most, so that a short track fades in and out whole.
  Duration _fadeBetween(Duration length, Duration? next) {
    var fade = _length();

    for (final half in [length ~/ 2, if (next != null && next > Duration.zero) next ~/ 2]) {
      if (fade > half) {
        fade = half;
      }
    }

    return fade;
  }

  @override
  Future<void> open(
    List<TrackSource> tracks, {
    required int index,
    required Duration position,
    required bool play,
    List<int>? order,
  }) async {
    _stopFade();
    _letGoOfOther();
    _queueEnded = false;
    _tracks = tracks;

    if (_shuffle && order != null && order.length == tracks.length) {
      _order = order;
      _index = order.indexOf(index);
    } else if (_shuffle) {
      _order = _shuffled(index);
      _index = 0;
    } else {
      _order = [for (var i = 0; i < tracks.length; i++) i];
      _index = index;
    }

    _tellChange();
    await _start(position: position, play: play);
  }

  /// The play order shuffled: the track at [first] first, the others after it in any order.
  List<int> _shuffled(int first) => [
    first,
    ...[
      for (var i = 0; i < _tracks.length; i++)
        if (i != first) i,
    ]..shuffle(_random),
  ];

  @override
  Future<int> add(List<TrackSource> tracks, {required bool next}) async {
    if (_tracks.isEmpty) {
      return -1;
    }

    final at = next ? _order[_index] + 1 : _tracks.length;
    final place = next ? _index + 1 : _order.length;
    final moved = [for (final track in _order) track < at ? track : track + tracks.length];
    _order = [...moved.take(place), for (var i = 0; i < tracks.length; i++) at + i, ...moved.skip(place)];
    _tracks = [..._tracks.take(at), ...tracks, ..._tracks.skip(at)];
    _tellChange();
    return at;
  }

  @override
  Future<({int from, int to})?> move(int from, int to) async {
    final track = _trackAt(from);
    final current = _trackAt(_index);

    if (track == null || current == null || to < 0 || to >= _order.length) {
      return null;
    }

    ({int from, int to})? unshuffled;

    // Unshuffled, the tracks are in the play order, and move in their order too.
    if (_shuffle) {
      _order = [..._order]
        ..removeAt(from)
        ..insert(to, _order[from]);
    } else {
      _tracks = [..._tracks]
        ..removeAt(from)
        ..insert(to, track);
      unshuffled = (from: from, to: to);
    }

    _index = _order.indexWhere((i) => identical(_tracks[i], current));
    _tellChange();
    return unshuffled;
  }

  @override
  Future<int> remove(int index) async {
    if (_trackAt(index) == null || index == _index) {
      return -1;
    }

    final at = _order[index];
    _order = [
      for (final (i, track) in _order.indexed)
        if (i != index) track < at ? track : track - 1,
    ];

    if (index < _index) {
      _index--;
    }

    _tracks = [..._tracks]..removeAt(at);
    _tellChange();
    return at;
  }

  @override
  Future<void> play() async {
    // As the queue ended, play starts it over.
    if (_queueEnded) {
      return jump(0);
    }

    await Future.wait([_current.play(), if (_fadingOut) _other.play()]);
  }

  @override
  Future<void> pause() async {
    _starting = false;
    await Future.wait([_current.pause(), if (_fadingOut) _other.pause()]);
  }

  @override
  Future<void> stop() async {
    _starts++;
    _starting = _fadingIn = _fadingOut = _queueEnded = false;
    _tracks = const [];
    _order = const [];
    _index = 0;
    _ahead = null;
    _held.fillRange(0, 2, null);
    _updateTicks();
    await Future.wait([for (final deck in _decks) deck.stop()]);
    _tellChange();
  }

  @override
  Future<void> jump(int index) async {
    final track = _trackAt(index);

    if (track == null) {
      return;
    }

    _stopFade();
    _queueEnded = false;

    // The current track starts over on its deck, which, as it ended, starts it again.
    if (index == _index && identical(_held[_turn], track)) {
      final starts = ++_starts;
      _starting = true;
      _tellChange();
      await _setLevel(_turn, 1);
      await _current.jump(0);
      _started(starts);
      return;
    }

    _index = index;

    // Opened ahead on the other deck, it starts there, and the track before stops.
    if (identical(_ahead, track)) {
      final before = _current;
      _held[_turn] = null;
      _turn = 1 - _turn;
      _ahead = null;
      unawaited(before.stop());
      _tellChange();
      return _start(play: true, opened: true);
    }

    _tellChange();
    await _start(play: true);
  }

  /// Starts the current track on the deck whose turn it is, from [position], at [level], playing or not as [play] says:
  /// the deck has it opened already, paused at its start, where [opened]; otherwise the deck opens it.
  Future<void> _start({
    Duration position = Duration.zero,
    required bool play,
    double level = 1,
    bool opened = false,
  }) async {
    final deck = _current;
    final track = _trackAt(_index);
    final starts = ++_starts;

    if (track == null) {
      _starting = false;
      return;
    }

    _starting = play;
    _updateTicks();
    await _setLevel(_turn, level);

    if (deck.repeat != _deckRepeat) {
      await deck.setRepeat(_deckRepeat);
    }

    if (starts != _starts) {
      return;
    }

    // Only now the deck's, which a jump to it starts over.
    _held[_turn] = track;

    if (opened) {
      // Asked again, as the way the tracks are levelled may have changed since it loaded.
      await deck.updateGain();

      if (_starting && starts == _starts) {
        await deck.play();
      }
    } else {
      await deck.open([track], index: 0, position: position, play: _starting);
    }

    _started(starts);
  }

  /// The [starts]th start is done, where no other took it over: the deck says from now on whether it plays.
  void _started(int starts) {
    if (starts == _starts) {
      _starting = false;
      _tellChange();
    }

    _updateTicks();
  }

  @override
  Future<void> seek(Duration position) async {
    _stopFade();
    _queueEnded = false;
    await _current.seek(position);
  }

  @override
  Future<void> setVolume(int volume) async {
    _volume = volume;
    await Future.wait([for (final deck in _decks) deck.setVolume(volume)]);
    _tellChange();
  }

  @override
  Future<void> updateGain() => _current.updateGain();

  @override
  Future<void> setEqualizer(Map<int, double> gains) =>
      Future.wait([for (final deck in _decks) deck.setEqualizer(gains)]);

  @override
  Future<void> setRepeat(Repeat mode) async {
    _repeat = mode;

    if (_current.repeat != _deckRepeat) {
      await _current.setRepeat(_deckRepeat);
    }

    _tellChange();
  }

  /// On, the current track first, the others after it in any order; off, back to their order unshuffled.
  @override
  Future<void> setShuffle(bool on) async {
    if (on != _shuffle && _tracks.isNotEmpty) {
      final current = _order[_index];
      _order = on ? _shuffled(current) : [for (var i = 0; i < _tracks.length; i++) i];
      _index = on ? 0 : current;
    }

    _shuffle = on;
    _tellChange();
  }

  /// The current deck's changes are the engine's; the other deck's, a track fading out or one opened ahead, aren't.
  void _deckChanged(Deck deck) {
    if (identical(deck, _current)) {
      _tellChange();
    }

    _updateTicks();
  }

  /// A deck's track played to its end: the one fading out, which stops; or the current one, with no crossfade, which
  /// starts over where it repeats, and otherwise goes on to the next, if any, at once.
  void _deckEnded(Deck deck) {
    if (_disposed) {
      return;
    }

    if (!identical(deck, _current)) {
      if (_fadingOut) {
        _stopFadingOut();
      }

      return;
    }

    // Not the current track's end: one that played on the deck before it, as it starts there.
    if (_starting) {
      return;
    }

    if (_repeat == Repeat.one) {
      _tellEnded();
      return;
    }

    // Still playing, it didn't end: mpv says it went back.
    if (deck.playing) {
      return;
    }

    final next = _next;

    if (next == null) {
      _queueEnded = true;
      _tellEnded();
      return;
    }

    _turnTo(next, fade: Duration.zero);
  }

  /// The turn of the track at [next] in the play order: it becomes the current one and starts, fading in over [fade]
  /// on the other deck, as the one before fades out on its own; with no fade, the one before having ended, it starts at
  /// once, where it was opened ahead or on the same deck.
  void _turnTo(int next, {required Duration fade}) {
    final track = _trackAt(next)!;
    final opened = identical(_ahead, track);
    final fading = fade > Duration.zero;

    // A track before still fading out, after a short one, stops: its deck takes this one, crossfading.
    if (_fadingOut) {
      if (fading) {
        _fadingOut = false;
      } else {
        _stopFadingOut();
      }
    }

    if (fading || opened) {
      if (!fading) {
        unawaited(_current.stop());
        _held[_turn] = null;
      }

      _turn = 1 - _turn;
    }

    _index = next;
    _ahead = null;
    _fade = fade;
    _fadingIn = _fadingOut = fading;
    _queueEnded = false;
    _tellChange();
    _tellEnded();
    unawaited(_start(play: true, level: fading ? 0 : 1, opened: opened));
  }

  /// Ends the crossfade under way at once: the track fading out stops, and the current one plays at the whole volume.
  void _stopFade() {
    if (_fadingOut) {
      _stopFadingOut();
    }

    if (_fadingIn) {
      _fadingIn = false;
      unawaited(_setLevel(_turn, 1));
    }
  }

  /// The track fading out stops, whether it played to its end or is cut short.
  void _stopFadingOut() {
    _fadingOut = false;
    _held[1 - _turn] = null;
    unawaited(_other.stop());
    _updateTicks();
  }

  /// The other deck lets go of the track opened ahead on it, which another queue doesn't have.
  void _letGoOfOther() {
    if (_held[1 - _turn] != null) {
      _held[1 - _turn] = null;
      unawaited(_other.stop());
    }

    _ahead = null;
  }

  /// Plays [deck] (0 or 1) at [level], where it isn't already, as while the decks are paused.
  Future<void> _setLevel(int deck, double level) async {
    if (_levels[deck] == level) {
      return;
    }

    _levels[deck] = level;
    await _decks[deck].setLevel(level);
  }

  /// Looks at the decks as they play, while they do or a crossfade is under way.
  void _updateTicks() {
    final needed = !_disposed && (_current.playing || _starting || _fadingIn || _fadingOut);

    if (needed) {
      _ticks ??= Timer.periodic(tick, (_) => _tick());
    } else {
      _ticks?.cancel();
      _ticks = null;
    }
  }

  void _tick() {
    if (_fadingIn || _fadingOut) {
      _stepFade();
    }

    if (_current.playing && !_starting) {
      _lookAhead();
    }

    _updateTicks();
  }

  /// Sets the decks' levels as the crossfade goes, each over its length: the current track's by how far into it it has
  /// played, rising as a sine; the one before's by how much of it is left, falling as a cosine. Should the current one
  /// start late (its stream slow to come), the one before fades out all the same, in its own time.
  void _stepFade() {
    if (_fadingIn) {
      final done = _part(_current.position, of: _fade);

      if (done >= 1) {
        _fadingIn = false;
      }

      unawaited(_setLevel(_turn, sin(done * pi / 2)));
    }

    final before = _held[1 - _turn];

    if (_fadingOut && before != null) {
      final left = _part(_lengthOf(before, _other) - _other.position, of: _fade);

      if (left <= 0) {
        _stopFadingOut();
      } else {
        unawaited(_setLevel(1 - _turn, cos((1 - left) * pi / 2)));
      }
    }
  }

  /// How much of [whole] [part] is, from 0 to 1; all of it where [whole] is none.
  static double _part(Duration part, {required Duration of}) =>
      of <= Duration.zero ? 1 : (part.inMicroseconds / of.inMicroseconds).clamp(0.0, 1.0);

  /// As the current track nears its end, opens the next one ahead on the other deck, and once it is within the
  /// crossfade's length of it, starts the crossfade. Not where its length is unknown, nor where nothing comes next.
  void _lookAhead() {
    final current = _trackAt(_index);
    final next = _next;

    if (current == null || next == null || _fadingIn) {
      return;
    }

    final length = _lengthOf(current, _current);
    final track = _trackAt(next)!;
    final fade = _fadeBetween(length, track.duration);

    if (length <= Duration.zero || fade <= Duration.zero) {
      return;
    }

    final left = length - _current.position;

    // Within it already, as after a seek near the end, over what is left of it.
    if (left <= fade) {
      _turnTo(next, fade: left > Duration.zero ? left : Duration.zero);
      return;
    }

    if (left <= fade + openAhead && !_fadingOut && !identical(_ahead, track)) {
      _openAhead(track);
    }
  }

  /// Opens [track] on the other deck, paused at its start and silent, for its turn.
  void _openAhead(TrackSource track) {
    final deck = 1 - _turn;
    _ahead = _held[deck] = track;
    unawaited(_decks[deck].open([track], index: 0, position: Duration.zero, play: false));
    unawaited(_setLevel(deck, 0));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _ticks?.cancel();

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }

    await _changes.close();
    await _ended.close();
    await Future.wait([for (final deck in _decks) deck.dispose()]);
  }
}
