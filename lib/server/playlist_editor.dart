import 'package:flutter/foundation.dart';

import 'server.dart';

/// Changes the user's playlists on the media server, one change after another, in the order they come, and tells its
/// listeners once none is left to make, whether they were made or not: what shows the playlists loads them again then,
/// as the server has them.
class PlaylistEditor extends ChangeNotifier {
  PlaylistEditor(this._api);

  final MediaServer _api;

  /// The last change asked for, done once it is, also where it failed.
  Future<void> _last = Future.value();

  /// How many changes have been asked for and aren't done.
  int _pending = 0;

  bool _disposed = false;

  /// Whether a change is under way, or waiting for one.
  bool get busy => _pending > 0;

  /// Makes a playlist named [name], with the songs whose ids are [songIds] in it.
  Future<void> create(String name, {List<String> songIds = const []}) =>
      _change(() => _api.createPlaylist(name, songIds: songIds));

  Future<void> rename(String id, String name) => _change(() => _api.renamePlaylist(id, name));

  Future<void> delete(String id) => _change(() => _api.deletePlaylist(id));

  /// Adds the songs whose ids are [songIds] at the end of the playlist whose id is [id].
  Future<void> add(String id, List<String> songIds) => _change(() => _api.addToPlaylist(id, songIds));

  /// Takes out of the playlist whose id is [id] its songs at [indexes].
  Future<void> remove(String id, List<int> indexes) => _change(() => _api.removeFromPlaylist(id, indexes));

  /// Moves the song at [from] in the playlist whose id is [id] to [to].
  Future<void> move(String id, {required int from, required int to}) =>
      _change(() => _api.moveInPlaylist(id, from: from, to: to));

  /// Makes [change] once those asked for before it are done: each counts its songs by their places as the one before
  /// left them.
  Future<void> _change(Future<void> Function() change) {
    _pending++;
    final done = _last.then((_) => change());
    _last = done.catchError((Object _) {}).whenComplete(() {
      _pending--;

      if (_pending == 0 && !_disposed) {
        notifyListeners();
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
