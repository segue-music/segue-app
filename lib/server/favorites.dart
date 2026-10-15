import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'models.dart';
import 'server.dart';

final _log = Logger('Favorites');

/// The user's favorites: as the media server last gave them ([load]), with the changes made here since ([set]), which
/// show at once and go to the server one after another, in the order they come. Once none is left to make, they load
/// again, as the server has them then. Tells its listeners of each change, and of each load.
class Favorites extends ChangeNotifier {
  Favorites(this._api);

  final MediaServer _api;

  /// As the server last gave them; null until they come.
  FavoriteItems? _loaded;

  /// The ids of [_loaded], of each kind.
  Map<FavoriteKind, Set<String>> _ids = const {};

  /// The changes made here that a load hasn't brought yet: whether each item is a favorite now.
  final _changes = <(FavoriteKind, String), bool>{};

  /// The last change asked for, done once it is, also where it failed.
  Future<void> _last = Future.value();

  /// How many changes have been asked for and aren't done.
  int _pending = 0;

  /// Counts the loads: one that another one has come after is dropped.
  int _loads = 0;

  bool _disposed = false;

  /// Whether they have come from the server.
  bool get loaded => _loaded != null;

  /// Whether the [kind] whose id is [id] is one of the user's favorites, as far as the app knows: not before they have
  /// come.
  bool contains(FavoriteKind kind, String id) => _changes[(kind, id)] ?? (_ids[kind]?.contains(id) ?? false);

  /// The favorite songs, as the server last gave them, but those no longer favorites since.
  List<Song> get songs => [
    for (final song in _loaded?.songs ?? const <Song>[])
      if (contains(FavoriteKind.song, song.id)) song,
  ];

  /// The favorite albums, as [songs] are.
  List<Album> get albums => [
    for (final album in _loaded?.albums ?? const <Album>[])
      if (contains(FavoriteKind.album, album.id)) album,
  ];

  /// The favorite artists, as [songs] are.
  List<Artist> get artists => [
    for (final artist in _loaded?.artists ?? const <Artist>[])
      if (contains(FavoriteKind.artist, artist.id)) artist,
  ];

  /// Asks the server for them. Where that fails, they stay as they were, and the failure is the caller's. While changes
  /// are under way, what comes is dropped: the load once they are done brings them.
  Future<void> load() async {
    final load = ++_loads;
    final items = await _api.favorites();

    if (_disposed || load != _loads || _pending > 0) {
      return;
    }

    _loaded = items;
    _ids = {
      FavoriteKind.artist: {for (final artist in items.artists) artist.id},
      FavoriteKind.album: {for (final album in items.albums) album.id},
      FavoriteKind.song: {for (final song in items.songs) song.id},
    };
    _changes.clear();
    notifyListeners();
  }

  /// Makes the [kind] whose id is [id] one of the user's favorites, or, unless [favorite], no longer one: here at once,
  /// and on the server once the changes before it are made. Where the server doesn't make it, it is undone here, and the
  /// failure is the caller's.
  Future<void> set(FavoriteKind kind, String id, {required bool favorite}) {
    final key = (kind, id);
    _changes[key] = favorite;
    notifyListeners();
    _pending++;
    final done = _last.then((_) => _api.setFavorite(kind, id, favorite: favorite));
    _last = done
        .then<void>(
          (_) {},
          onError: (Object _) {
            // As the server has it, unless changed again since.
            if (_changes[key] == favorite && !_disposed) {
              _changes.remove(key);
              notifyListeners();
            }
          },
        )
        .whenComplete(() {
          _pending--;

          if (_pending == 0 && !_disposed) {
            unawaited(load().catchError((Object e) => _log.warning('favorites not loaded again', e)));
          }
        });

    return done;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
