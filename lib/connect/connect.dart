import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../player/player.dart';
import '../segue/client.dart';
import '../segue/protocol.dart';
import '../server/models.dart';

/// What plays, wherever it plays: what the now-playing bar shows, and which song the lists mark.
class NowPlaying {
  const NowPlaying({
    required this.playing,
    required this.position,
    this.songId,
    this.title,
    this.artist,
    this.artists = const [],
    this.album,
    this.coverArt,
    this.duration,
    this.device,
    this.repeat = Repeat.off,
    this.shuffle = false,
    this.canRepeat = false,
    this.canShuffle = false,
    this.canJump = false,
  });

  /// Its id in the app's API (the hub gives the app other devices' songs in it), or null when the
  /// hub couldn't translate it.
  final String? songId;

  final String? title;
  final String? artist;

  /// The artists [artist] names, with their ids in the app's API; none where the song doesn't have them, as one
  /// another device plays, which the hub gives with its artist's name only.
  final List<Artist> artists;

  final String? album;
  final String? coverArt;
  final bool playing;
  final Duration position;
  final Duration? duration;

  /// The other device it plays on; null when it plays here.
  final String? device;

  final Repeat repeat;
  final bool shuffle;

  /// Whether the device it plays on takes [ConnectController.setRepeat],
  /// [ConnectController.setShuffle] and [ConnectController.jump].
  final bool canRepeat;
  final bool canShuffle;
  final bool canJump;
}

/// The Connect model: the app controls one device at a time, this one or another, and everything you
/// press (play an album, pause, skip) goes to it. Picking another device moves the music there, and
/// when any device starts playing, every app follows it.
class ConnectController extends ChangeNotifier {
  ConnectController({required this.player, this.client}) {
    player.addListener(_update);
    final hub = client;

    if (hub == null) {
      return;
    }

    hub.addListener(_update);
    hub.onCommand = (command, from) => player.obey(command);
    hub.onConnected = () => unawaited(_connected());
    player.onReport = hub.sendState;
  }

  final PlayerController player;

  /// Null when no hub was found: the app then only plays here.
  final SegueClient? client;

  String? _active;

  /// The device playing at the last update: [_here], another device's id, or null for none. A
  /// change means a device started playing, and the app follows it.
  String? _playing;
  static const _here = ''; // the hub never gives a device an empty id
  bool _restored = false;

  /// Until when the last playback plays as it comes back here, rather than paused: a play pressed as the app opened,
  /// before it had any music to play (a headphone's button that woke it up, on Android). Brought back on another
  /// device, the music stays as it is there. Null: it comes back paused.
  DateTime? playRestoredBy;

  /// The device the app controls; null is this one.
  String? get activeId => _active;

  /// The device playing now, or null for none (or this one).
  String? get playingId => _playing == _here ? null : _playing;

  Device? get activeDevice => _active == null ? null : client?.devices[_active];

  /// The user's other players that are online, by name. Offline ones can't play, so they are left
  /// out, though the hub still lists them.
  List<Device> get devices {
    final list = [...?client?.devices.values.where((d) => d.info.isPlayer && d.online)];
    list.sort((a, b) => a.info.name.compareTo(b.info.name));
    return list;
  }

  NowPlaying? get nowPlaying {
    final device = activeDevice;

    if (device == null) {
      final song = player.current;

      if (song == null) {
        return null;
      }

      return NowPlaying(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        artists: song.artists,
        album: song.album,
        coverArt: song.coverArt,
        playing: player.playing,
        position: player.position,
        duration: song.duration,
        repeat: player.repeat,
        shuffle: player.shuffle,
        canRepeat: true,
        canShuffle: true,
        canJump: true,
      );
    }

    final state = device.state;
    final item = state?.current;
    return NowPlaying(
      songId: item?.id,
      title: item?.title,
      artist: item?.artist,
      album: item?.album,
      coverArt: item?.id,
      playing: state?.status == PlaybackStatus.playing,
      position: Duration(milliseconds: client!.positionMs(device.id) ?? 0),
      duration: item?.durationMs == null ? null : Duration(milliseconds: item!.durationMs!),
      device: device.info.name,
      repeat: state?.repeat ?? Repeat.off,
      shuffle: state?.shuffle ?? false,
      canRepeat: device.info.capabilities.contains(CommandAction.setRepeat),
      canShuffle: device.info.capabilities.contains(CommandAction.setShuffle),
      canJump: device.info.capabilities.contains(CommandAction.jump),
    );
  }

  /// The queue of the device the app controls, in its play order (shuffled, or not), and the
  /// current track's place in it.
  ({List<QueueItem> tracks, int index}) get queue {
    final device = activeDevice;

    if (device == null) {
      return (tracks: [for (final song in player.queue) song.toQueueItem()], index: player.index);
    }

    return (tracks: device.state?.queue ?? const [], index: device.state?.index ?? 0);
  }

  /// The cover of the track [offset] places from the current one in [queue] (1: the next one; -1: the one before), or
  /// null where there is none: here, its song's; on another device, its id, which the media server takes for one, as in
  /// [nowPlaying].
  String? coverArtBeside(int offset) {
    final device = activeDevice;

    if (device == null) {
      final index = player.index + offset;
      return index >= 0 && index < player.queue.length ? player.queue[index].coverArt : null;
    }

    final tracks = device.state?.queue ?? const [];
    final index = (device.state?.index ?? 0) + offset;
    return index >= 0 && index < tracks.length ? tracks[index].id : null;
  }

  /// Plays [songs] from the one at [index]. If that is another song than the one repeating, it turns
  /// repeating one track into repeating the queue, as a skip does on the player.
  Future<Result> playSongs(List<Song> songs, int index) async {
    final now = nowPlaying;
    final result = await _run(
      Command.setQueue(queue: [for (final song in songs) song.toQueueItem()], index: index, positionMs: 0, play: true),
      () => player.playQueue(songs, index: index),
    );

    if (result.ok && now != null && now.repeat == Repeat.one && now.canRepeat && now.songId != songs[index].id) {
      await setRepeat(Repeat.all);
    }

    return result;
  }

  /// Plays [songs] from the one at [index] on this device, whichever the app controls: what the car asks for (Android
  /// Auto), whose sound is this device's. As it starts, the hub stops the device that played (SPEC.md, section 4), and
  /// the app follows this one.
  Future<Result> playHere(List<Song> songs, int index) async {
    try {
      await player.playQueue(songs, index: index);
      return const Result(ok: true);
    } on CommandFailed catch (e) {
      return Result(ok: false, error: e.message);
    }
  }

  /// Whether the device the app controls takes [addToQueue].
  bool get canAddToQueue =>
      _active == null || (activeDevice?.info.capabilities.contains(CommandAction.addToQueue) ?? false);

  /// Adds [songs] to the queue of the device the app controls, the current track playing on: right after it if [next],
  /// otherwise at its end.
  Future<Result> addToQueue(List<Song> songs, {required bool next}) => _run(
    Command.addToQueue(queue: [for (final song in songs) song.toQueueItem()], next: next),
    () => player.addToQueue(songs, next: next),
  );

  /// Whether the device the app controls takes [moveInQueue] and [removeFromQueue].
  bool get canEditQueue =>
      _active == null ||
      (activeDevice?.info.capabilities.toSet().containsAll([
            CommandAction.moveInQueue,
            CommandAction.removeFromQueue,
          ]) ??
          false);

  /// Moves the track at [from] in [queue] to [to], the place it then has, on the device the app controls, the current
  /// track playing on.
  Future<Result> moveInQueue(int from, int to) =>
      _run(Command.moveInQueue(index: from, to: to), () => player.moveInQueue(from, to));

  /// Takes the track at [index] out of [queue], on the device the app controls; not the current one.
  Future<Result> removeFromQueue(int index) =>
      _run(Command.removeFromQueue(index), () => player.removeFromQueue(index));

  Future<Result> play() => _run(const Command(CommandAction.play), player.play);

  Future<Result> pause() => _run(const Command(CommandAction.pause), player.pause);

  Future<Result> toggle() => _run(const Command(CommandAction.toggle), player.toggle);

  Future<Result> next() => _run(const Command(CommandAction.next), player.next);

  Future<Result> previous() => _run(const Command(CommandAction.previous), player.previous);

  /// Plays the track at [index] of [queue], from its start.
  Future<Result> jump(int index) => _run(Command.jump(index), () => player.jump(index));

  Future<Result> seek(Duration position) => _run(Command.seek(position.inMilliseconds), () => player.seek(position));

  Future<Result> setRepeat(Repeat mode) => _run(Command.setRepeat(mode), () => player.setRepeat(mode));

  Future<Result> setShuffle(bool on) => _run(Command.setShuffle(on), () => player.setShuffle(on));

  /// Makes [deviceId] (null: this device) the one the app controls, moving the music there if the
  /// current one has any.
  Future<Result> switchTo(String? deviceId) async {
    final hub = client;

    if (deviceId == _active || hub == null) {
      return const Result(ok: true);
    }

    final me = hub.device.id;
    final hasMusic = _active == null ? player.queue.isNotEmpty : (activeDevice?.state?.queue?.isNotEmpty ?? false);

    if (hasMusic) {
      final result = await hub.transfer(_active ?? me, deviceId ?? me);

      if (!result.ok) {
        return result;
      }
    }

    _active = deviceId;
    notifyListeners();
    return const Result(ok: true);
  }

  Future<Result> _run(Command command, Future<void> Function() here) async {
    final target = _active;

    if (target != null) {
      return client!.command(target, command);
    }

    try {
      await here();
      return const Result(ok: true);
    } on CommandFailed catch (e) {
      return Result(ok: false, error: e.message);
    }
  }

  Future<void> _connected() async {
    if (!_restored) {
      _restored = true;
      await _restoreLastPlayback();
      await _playRestored();
    }

    client!.sendState(player.report(full: true));
  }

  /// When the app opens and nothing plays, it shows where the music was (SPEC.md, "Last
  /// playback"): on its device, if that one is on; otherwise here, paused at the same point, so
  /// that play continues it.
  Future<void> _restoreLastPlayback() async {
    final hub = client!;
    final last = hub.lastPlayback;
    final queue = last?.state.queue;

    if (last == null || queue == null || queue.isEmpty) {
      return;
    }

    if (_whoIsPlaying() != null || player.queue.isNotEmpty) {
      return;
    }

    if (last.deviceId != hub.device.id && (hub.devices[last.deviceId]?.online ?? false)) {
      _active = last.deviceId;
      notifyListeners();
      return;
    }

    try {
      await player.obey(
        Command.setQueue(queue: queue, index: last.state.index ?? 0, positionMs: last.state.positionMs, play: false),
      );
    } on CommandFailed {
      // nothing in it can be played here
    }
  }

  Future<void> _playRestored() async {
    final by = playRestoredBy;
    playRestoredBy = null;

    if (by != null && !clock.now().isAfter(by) && _active == null && player.queue.isNotEmpty && !player.playing) {
      await player.play();
    }
  }

  void _update() {
    final playing = _whoIsPlaying();
    final started = playing != null && playing != _playing;
    // Music held paused here goes; if it was playing here, the hub stops it itself.
    final leave = started && playing != _here && _playing != _here;
    _playing = playing;

    if (started) {
      _active = playing == _here ? null : playing;
    }

    final active = activeDevice;

    if (_active != null && !(active?.online ?? false)) {
      _active = null; // gone or offline

      if (active != null) {
        unawaited(_keepHere(active));
      }
    }

    notifyListeners();

    // Last, since stopping the player comes back here.
    if (leave) {
      unawaited(_leave());
    }
  }

  /// The device the app controlled went offline (closed, say): its music stays in the bar, here,
  /// paused where it got to, instead of vanishing with it.
  Future<void> _keepHere(Device device) async {
    final state = device.state;
    final queue = state?.queue;

    if (state == null || queue == null || queue.isEmpty) {
      return;
    }

    try {
      await player.obey(
        Command.setQueue(
          queue: queue,
          index: state.index ?? 0,
          positionMs: client!.positionMs(device.id) ?? state.positionMs,
          play: false,
        ),
      );
    } on CommandFailed {
      // nothing in it can be played here
    }

    // It came back playing, or another device started, while the music loaded here.
    if (playingId != null) {
      await _leave();
    }
  }

  /// Another device started playing: the music this one holds, paused, goes, as the hub leaves a
  /// device that played (SPEC.md, section 4). Kept, it would show on the other apps' devices as
  /// paused here, often with the very music that plays there (kept here as that device closed).
  Future<void> _leave() async {
    if (player.queue.isEmpty || player.playing) {
      return;
    }

    await player.stop();
  }

  /// This device if it plays; otherwise the other device that reported playing most recently.
  String? _whoIsPlaying() {
    if (player.playing) {
      return _here;
    }

    Device? latest;

    for (final device in client?.devices.values ?? const <Device>[]) {
      final state = device.state;

      if (!device.online || state?.status != PlaybackStatus.playing) {
        continue;
      }

      if (latest == null || state!.at > latest.state!.at) {
        latest = device;
      }
    }

    return latest?.id;
  }

  @override
  void dispose() {
    player.removeListener(_update);
    client?.removeListener(_update);
    super.dispose();
  }
}
