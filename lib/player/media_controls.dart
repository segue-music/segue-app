import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Color, Locale;

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

import '../connect/connect.dart';
import '../l10n/app_localizations.dart';
import '../segue/protocol.dart';
import '../server/favorites.dart';
import '../server/models.dart';
import '../server/server.dart';
import '../ui/errors.dart';
import 'browse_tree.dart';

/// The system's media controls (MPRIS on Linux: media keys, the desktop's player widget, KDE
/// Connect...; Now Playing on iOS: the lock screen, Control Center, CarPlay, headphone buttons; the
/// media session on Android: the notification, the lock screen, headphone buttons) for
/// what the now-playing bar shows: this device's playback, or the device it follows. On Android, also what a car
/// browses through it (Android Auto): the user's music ([BrowseTree]), which plays on this device, whose sound the
/// car's is; the queue, which jumps; what is said to it; and the music to resume, which Android's media controls offer.
class MediaControls extends BaseAudioHandler with SeekHandler {
  ConnectController? _connect;
  MediaServer? _api;
  Timer? _tick;
  AppLocalizations? _strings;

  /// What the car browses, while the app has a session: none signed out, nor closed ([close]).
  BrowseTree? _tree;

  /// Completes as the app has a session ([attach]): what the car asks for before then waits for it.
  var _attached = Completer<void>();

  /// Whether the media server is in reach, which the home the car browses follows.
  ValueListenable<bool>? _reachability;

  /// That what the car shows under an item it has opened has changed, by the item's id: told so, it asks again.
  final _children = <String, BehaviorSubject<Map<String, dynamic>>>{};

  /// The stretch of the queue the car shows ([_syncQueue]): where in the queue it starts, and what it has.
  int _queueStart = 0;
  String? _queueShown;

  /// The song that played last, the music to resume ([AudioService.recentRootId]), and that one has.
  MediaItem? _recent;
  final _recentKnown = Completer<void>();

  /// The covers the system shows, by their ids, each downloaded once to the app's cache, a few at a time.
  final _covers = <String, Future<File?>>{};
  final _downloads = _Throttle(4);

  /// Until when the music the app brings back as it opens plays ([ConnectController.playRestoredBy]), for a play that
  /// came before it had a [ConnectController] to give it to; see [play].
  DateTime? _earlyPlayBy;

  /// How long a play that came before the app had any music to play holds: on Android, where a headphone's button
  /// opens the app once the system has closed it, the music may come to the foreground (its service) only in the 10
  /// seconds after the button.
  static const _earlyPlayFor = Duration(seconds: 8);

  /// How long what the car asks for waits for the app to have a session: as it starts for the car, it finds its media
  /// server and its hub, a few seconds each at most.
  static const _waitForSession = Duration(seconds: 15);

  /// How long the music to resume waits to come back, as the app starts for it.
  static const _waitForRecent = Duration(seconds: 5);

  /// How many tracks of the queue the car shows before the current one, and after it.
  static const _queueBefore = 10;
  static const _queueAfter = 100;

  /// The id of the music to resume.
  static const _recentId = 'recent';

  /// CoverProvider.kt's, in AndroidManifest.xml: the app's id, and ".covers".
  static const _coverAuthority = 'io.github.mateusguilherme.segue.covers';

  /// Where in the app's cache the covers are: CoverProvider.kt reads them there.
  static const _coverDirectory = 'segue-covers';

  /// Closes the app, as Android's recent apps let go of it ([onTaskRemoved]).
  Future<void> Function()? close;

  /// Opens the app closed by [close] again, without its screen, for a play that came to it (a headphone's button), as
  /// one opens it where Android had ended it, and for the car.
  VoidCallback? open;

  /// Starts the system's media service, on the platforms where the app sets it up: Linux (MPRIS),
  /// iOS and Android for now. Null when it can't, e.g. without a D-Bus session.
  static Future<MediaControls?> start() async {
    if (!Platform.isLinux && !Platform.isIOS && !Platform.isAndroid) {
      return null;
    }

    try {
      return await AudioService.init(
        builder: MediaControls.new,
        config: const AudioServiceConfig(
          // On Linux, the MPRIS bus name (with ".instance<pid>") and the name the desktop shows; on
          // Android, the notification's channel, as the app's notifications in the system settings list it.
          androidNotificationChannelId: 'io.github.mateusguilherme.segue',
          androidNotificationChannelName: 'Segue',
          // The ring and the note in white (tool/icons.dart), as Android takes only the alpha of the
          // notification's icon, on the pink of the app's icon (iconPink, lib/ui/theme.dart).
          androidNotificationIcon: 'drawable/ic_notification',
          notificationColor: Color(0xFFF9358E),
          androidBrowsableRootExtras: BrowseTree.rootExtras,
        ),
      );
    } on Object catch (e) {
      debugPrint('media controls unavailable: $e');
      return null;
    }
  }

  /// The app's words, in the language it shows, for what the controls say of a song on another device: "(em laptop)",
  /// and for what the car browses. Until it has them, the artist alone, and English.
  AppLocalizations? get strings => _strings;

  set strings(AppLocalizations? strings) {
    if (strings?.localeName != _strings?.localeName) {
      _strings = strings;
      _changedAll();
      _sync();
    }
  }

  AppLocalizations _words() => _strings ?? lookupAppLocalizations(const Locale('en'));

  /// Shows [connect]'s playback; null (signed out) shows nothing. [api] fetches the covers, and with them, what the car
  /// browses: the user's [favorites] among it, and its home as the media server is in reach, as [reachability] says.
  void attach(
    ConnectController? connect,
    MediaServer? api, {
    Favorites? favorites,
    ValueListenable<bool>? reachability,
  }) {
    _connect?.removeListener(_sync);
    _reachability?.removeListener(_homeChanged);
    _connect = connect;
    _api = api;
    _reachability = reachability;
    _covers.clear();
    connect?.addListener(_sync);
    reachability?.addListener(_homeChanged);
    final earlyPlayBy = _earlyPlayBy;

    if (connect != null && earlyPlayBy != null) {
      connect.playRestoredBy = earlyPlayBy;
      _earlyPlayBy = null;
    }

    if (connect != null && api != null) {
      _tree = BrowseTree(
        api,
        strings: _words,
        coverUri: _coverUri,
        favorites: favorites,
        offline: () => !(reachability?.value ?? true),
      );

      if (!_attached.isCompleted) {
        _attached.complete();

        // The car may have asked before the app had a handler, as Android starts it for the car: audio_service drops
        // that, unanswered. Told that the root changed, the car asks again. With options, though none: Android
        // refuses the notice without them.
        if (Platform.isAndroid) {
          unawaited(
            AudioServicePlatform.instance
                .notifyChildrenChanged(
                  const NotifyChildrenChangedRequest(parentMediaId: AudioService.browsableRootId, options: {}),
                )
                .catchError((Object e) => debugPrint('telling the car the root changed: $e')),
          );
        }
      }
    } else {
      _tree = null;

      if (_attached.isCompleted) {
        _attached = Completer();
      }
    }

    // What the car asked for before, or showed of the session before, again.
    _changedAll();
    _sync();
  }

  void _sync() {
    _tick?.cancel();
    final connect = _connect;
    final now = connect?.nowPlaying;
    _syncQueue(connect, now);

    if (now?.title == null) {
      mediaItem.add(null);
      playbackState.add(PlaybackState());
      return;
    }

    final strings = _strings;
    // The language too, for a song on another device: another says the device in other words.
    final id = [now!.device, now.coverArt, now.title, if (now.device != null) strings?.localeName].join('|');

    if (mediaItem.value?.id != id) {
      mediaItem.add(
        MediaItem(
          id: id,
          title: now.title!,
          artist: switch ((now.device, strings)) {
            (final device?, final strings?) => strings.artistOnDevice(now.artist ?? '', device),
            _ => now.artist,
          },
          duration: now.duration,
        ),
      );
      unawaited(_loadCover(now.coverArt, id));
      _recent = MediaItem(
        id: _recentId,
        title: now.title!,
        artist: now.artist,
        album: now.album,
        duration: now.duration,
        artUri: _coverUri(now.coverArt),
        playable: true,
      );

      if (!_recentKnown.isCompleted) {
        _recentKnown.complete();
      }
    }

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (now.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: AudioProcessingState.ready,
        playing: now.playing,
        updatePosition: now.position,
        queueIndex: connect!.queue.index - _queueStart,
      ),
    );

    // MPRIS only learns the position from these updates: refresh it while playing.
    if (now.playing) {
      _tick = Timer(const Duration(seconds: 1), _sync);
    }
  }

  /// The queue the car shows: a stretch of the queue around the current track, as a long one would go beyond what
  /// Android hands from one app to another at once. Told again only as it changes, not at each second of a song.
  void _syncQueue(ConnectController? connect, NowPlaying? now) {
    final (:tracks, :index) = connect == null || now == null ? (tracks: const <QueueItem>[], index: 0) : connect.queue;
    final start = min(max(0, index - _queueBefore), tracks.length);
    final shown = tracks.sublist(start, min(tracks.length, index + _queueAfter + 1));
    final key = [start, for (final track in shown) '${track.id}:${track.title}'].join('|');

    if (key == _queueShown) {
      return;
    }

    _queueShown = key;
    _queueStart = start;
    queue.add([
      for (final (i, track) in shown.indexed)
        MediaItem(
          id: 'queue/${start + i}',
          title: track.title ?? '',
          artist: track.artist,
          album: track.album,
          duration: track.durationMs == null ? null : Duration(milliseconds: track.durationMs!),
        ),
    ]);
  }

  /// The cover goes to the system as a file: its server URL carries the login token.
  Future<void> _loadCover(String? coverId, String itemId) async {
    final file = coverId == null ? null : await _coverFile(coverId);
    final item = mediaItem.value;

    if (file != null && item?.id == itemId) {
      mediaItem.add(item!.copyWith(artUri: file.uri));
    }
  }

  /// Where the car reads the cover whose id is [coverId] (CoverProvider.kt), which comes to the app's cache meanwhile;
  /// null without one.
  Uri? _coverUri(String? coverId) {
    if (coverId == null) {
      return null;
    }

    unawaited(_coverFile(coverId));
    return Uri(scheme: 'content', host: _coverAuthority, path: '/${_coverName(coverId)}');
  }

  /// The file of the cover whose id is [coverId], in the app's cache, downloaded there once; null where it can't be.
  Future<File?> _coverFile(String coverId) => _covers[coverId] ??= _downloadCover(coverId);

  Future<File?> _downloadCover(String coverId) async {
    final api = _api;

    if (api == null) {
      return null;
    }

    try {
      final directory = Directory('${(await getTemporaryDirectory()).path}/$_coverDirectory');
      final file = File('${directory.path}/${_coverName(coverId)}');

      if (!await file.exists()) {
        final bytes = await _downloads.run(() => api.coverArt(coverId, size: 512));
        await directory.create(recursive: true);
        // Whole under another name, then under its own, so that the car never reads half of one (CoverProvider.kt).
        final part = File('${file.path}.part');
        await part.writeAsBytes(bytes);
        await part.rename(file.path);
      }

      return file;
    } on Object catch (e) {
      debugPrint('cover for the media controls: $e'); // the controls just go without it
      _covers.remove(coverId); // tried again next time
      return null;
    }
  }

  /// The name of the cover's file: its id, with nothing but letters, digits, _ and -, as CoverProvider.kt takes it.
  static String _coverName(String coverId) => '${coverId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.jpg';

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) =>
      _children.putIfAbsent(parentMediaId, BehaviorSubject.new);

  /// Tells the car that what it has opened has changed: all of it, as the session or the language changes.
  void _changedAll() {
    for (final children in _children.values) {
      children.add(const {});
    }
  }

  /// The media server came in reach, or went out of it: the home has the downloaded albums alone, or everything.
  void _homeChanged() => _children[BrowseTree.home]?.add(const {});

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.recentRootId) {
      return _recentItems();
    }

    final tree = await _browsable();

    try {
      return await tree?.children(parentMediaId) ?? const [];
    } on Object catch (e) {
      // The car says it failed.
      debugPrint('browsing $parentMediaId: $e');
      rethrow;
    }
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
    final tree = await _browsable();
    return await tree?.search(query) ?? const [];
  }

  /// The tree to browse, once the app has a session: closed ([close]), the app opens again for the car, as for a play;
  /// starting, it comes in a moment. None signed out.
  Future<BrowseTree?> _browsable() async {
    if (_tree == null) {
      open?.call();
      await _attached.future.timeout(_waitForSession, onTimeout: () {});
    }

    return _tree;
  }

  /// The music to resume: the song that played last, which [play] plays on. As the app starts for it, it comes back in a
  /// moment; closed ([close]), the app stays closed, the song known.
  Future<List<MediaItem>> _recentItems() async {
    if (_recent == null) {
      await _recentKnown.future.timeout(_waitForRecent, onTimeout: () {});
    }

    final recent = _recent;
    return recent == null ? const [] : [recent];
  }

  /// Plays what the car picked: here, whose sound the car's is; the music to resume, wherever it was.
  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    if (mediaId == _recentId) {
      return play();
    }

    final tree = await _browsable();
    await _playHere(() async => tree?.queueOf(mediaId));
  }

  /// Plays here what was said to the car ([BrowseTree.queueForVoice]). With nothing to go on ("toca música"), the music
  /// the app has, which moves here from another device, or else some at random.
  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    final tree = await _browsable();
    final connect = _connect;

    if (tree == null || connect == null) {
      return;
    }

    if (BrowseTree.saysNothing(query, extras)) {
      if (connect.nowPlaying != null && (await connect.switchTo(null)).ok) {
        await connect.play();
        return;
      }

      await _playHere(tree.anything);
      return;
    }

    await _playHere(() => tree.queueForVoice(query, extras));
  }

  /// Plays here the songs [find] finds, from the one it says; or says what went wrong, in the car's words.
  Future<void> _playHere(Future<(List<Song>, int)?> Function() find) async {
    final strings = _words();

    try {
      final queue = await find();
      final connect = _connect;

      if (queue == null || connect == null) {
        _fail(strings.nothingFound);
        return;
      }

      final result = await connect.playHere(queue.$1, queue.$2);

      if (!result.ok) {
        _fail(describeError(strings, result.error));
      }
    } on Object catch (e) {
      _fail(describeError(strings, '$e'));
    }
  }

  /// Says in the system's controls (the car's screen) what went wrong, until the playback changes.
  void _fail(String message) => playbackState.add(
    playbackState.value.copyWith(processingState: AudioProcessingState.error, errorCode: 1, errorMessage: message),
  );

  /// Plays, or, with no music yet, as the app opens (on Android, woken up by a headphone's button), plays the music it
  /// brings back, if that is soon.
  @override
  Future<void> play() async {
    final connect = _connect;

    if (connect?.nowPlaying != null) {
      await connect!.play();
      return;
    }

    final by = clock.now().add(_earlyPlayFor);

    if (connect == null) {
      _earlyPlayBy = by;
      open?.call();
    } else {
      connect.playRestoredBy = by;
    }
  }

  @override
  Future<void> pause() => _do((connect) => connect.pause());

  /// On Android, the app swiped out of the recent apps: it closes ([close]), and the music this device plays stops, as
  /// closing its window does on a computer, rather than playing on with its notification, as the media session's
  /// foreground service would let it.
  @override
  Future<void> onTaskRemoved() async => close?.call();

  @override
  Future<void> stop() => pause();

  @override
  Future<void> skipToNext() => _do((connect) => connect.next());

  @override
  Future<void> skipToPrevious() => _do((connect) => connect.previous());

  /// Plays the track the car picked in its queue: the place of [index] in the stretch it shows ([_syncQueue]).
  @override
  Future<void> skipToQueueItem(int index) => _do((connect) => connect.jump(_queueStart + index));

  @override
  Future<void> seek(Duration position) => _do((connect) => connect.seek(position));

  Future<void> _do(Future<Result> Function(ConnectController connect) action) async {
    final connect = _connect;

    if (connect != null) {
      await action(connect);
    }
  }
}

/// Runs tasks a few at a time, the others waiting their turn, in order.
class _Throttle {
  _Throttle(this._most);

  final int _most;
  int _running = 0;
  final _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running < _most) {
      _running++;
    } else {
      // The place of a task done, handed on.
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }

    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
