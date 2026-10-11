import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../downloads/downloads.dart';
import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../server/playlist_editor.dart';
import '../../services.dart';
import '../widgets/cover.dart';
import '../widgets/menu_shortcuts.dart';
import '../widgets/order_chips.dart';
import '../widgets/spinner.dart';
import 'favorite_songs_page.dart';
import 'playlist_dialogs.dart';
import 'playlist_menu.dart';
import 'playlist_page.dart';

/// The user's playlists, and those others share with them, by name, each with its picture and how many songs it has,
/// opening its page, under a button that makes a new one and the user's favorite songs ([FavoriteSongsPage]). Held, one opens its menu, which plays it next or adds it to
/// the queue, and renames and deletes one the user can change. They load again as the app changes any. Where the app
/// downloads, chips over them show them all, or the downloaded alone, as these come and go.
class PlaylistsView extends StatefulWidget {
  const PlaylistsView({super.key});

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  Future<List<Playlist>>? _playlists;
  PlaylistEditor? _editor;

  /// Whether it shows the downloaded alone.
  bool _downloaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playlists ??= _load();
    _editor ??= ServicesScope.of(context).playlistEditor..addListener(_reload);
  }

  @override
  void dispose() {
    _editor?.removeListener(_reload);
    super.dispose();
  }

  /// Loads them again, showing those there are until they come.
  Future<void> _reload() async {
    final reload = _load();
    // In braces: setState takes no callback that returns a future, as the assignment would.
    setState(() {
      _playlists = reload;
    });
    // The section says why, where it fails.
    await reload.catchError((_) => const <Playlist>[]);
  }

  Future<List<Playlist>> _load() async =>
      (await ServicesScope.of(context).api.playlists())
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Widget build(BuildContext context) {
    final downloads = ServicesScope.of(context).downloads;

    if (downloads == null) {
      return _all();
    }

    final strings = AppLocalizations.of(context);

    // As the albums' chips, at the top, their line the whole width.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderChips(
          _downloaded,
          orders: const [false, true],
          label: (downloaded) => downloaded ? strings.downloadedPlaylists : strings.allPlaylists,
          onOrder: (downloaded) => setState(() => _downloaded = downloaded),
        ),
        Expanded(child: _downloaded ? _downloadedOnes(downloads) : _all()),
      ],
    );
  }

  /// The downloaded playlists, by name, as they come and go.
  Widget _downloadedOnes(Downloads downloads) => ListenableBuilder(
    listenable: downloads,
    builder: (context, _) {
      final playlists = [for (final download in downloads.all) ?download.playlist]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (playlists.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(AppLocalizations.of(context).nothingDownloaded, textAlign: TextAlign.center),
          ),
        );
      }

      return ListView(
        // At the end, clear of the bars a phone's home has over it.
        padding: EdgeInsets.only(bottom: 8 + MediaQuery.paddingOf(context).bottom),
        children: [for (final playlist in playlists) _PlaylistTile(playlist)],
      );
    },
  );

  /// Every playlist, from the server.
  Widget _all() => FutureBuilder(
    future: _playlists,
    builder: (context, snapshot) {
      final strings = AppLocalizations.of(context);

      if (snapshot.hasError) {
        return Center(child: Text(strings.couldNotListPlaylists('${snapshot.error}')));
      }

      final playlists = snapshot.data;

      if (playlists == null) {
        return const Center(child: Spinner());
      }

      return RefreshIndicator(
        onRefresh: _reload,
        // Dragged by the mouse too, as the home is: on a computer, which drags only a finger's or a touchpad's, down from
        // the top it loads the playlists again as well.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: ListView.builder(
            // At the end, clear of the bars a phone's home has over it.
            padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom),
            // The button that makes one first, then the favorite songs; with no playlists, a line that says so under
            // them, which a drag down loads again, as it does the list.
            itemCount: 2 + (playlists.isEmpty ? 1 : playlists.length),
            itemBuilder: (context, i) {
              if (i == 0) {
                return const NewPlaylistTile();
              }

              if (i == 1) {
                return const _FavoritesTile();
              }

              if (playlists.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(strings.playlistsEmpty, textAlign: TextAlign.center),
                );
              }

              return _PlaylistTile(playlists[i - 2]);
            },
          ),
        ),
      );
    },
  );
}

/// The user's favorite songs, as a playlist in the list, with how many they are once they have come: a tap opens their
/// page.
class _FavoritesTile extends StatelessWidget {
  const _FavoritesTile();

  @override
  Widget build(BuildContext context) {
    final favorites = ServicesScope.of(context).favorites;
    final strings = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) => ListTile(
        leading: const SizedBox.square(dimension: Thumbnail.size, child: FavoritesPicture(radius: 4)),
        title: Text(strings.favoriteSongs, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: favorites.loaded ? Text(strings.trackCount(favorites.songs.length)) : null,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FavoriteSongsPage())),
      ),
    );
  }
}

/// A playlist in the list: a tap opens its page. A long press (held, with a finger or the mouse) opens its menu where it
/// was pressed, as the menu key, Shift+F10, or OK held does over it, for the keyboard and the remote; where it has
/// nothing to do (another user's playlist, empty, or one the device the app controls can't add to its queue), nothing
/// opens.
class _PlaylistTile extends StatefulWidget {
  const _PlaylistTile(this.playlist);

  final Playlist playlist;

  @override
  State<_PlaylistTile> createState() => _PlaylistTileState();
}

class _PlaylistTileState extends State<_PlaylistTile> {
  /// Where the pointer last went down on it, in the window.
  Offset? _pressedAt;

  /// Opens the menu: where the pointer is held ([at]), or else over the playlist.
  Future<void> _openMenu({Offset? at}) async {
    final items = playlistMenuItems(context, widget.playlist, hasSongs: widget.playlist.songCount != 0);

    if (items.isEmpty) {
      return;
    }

    final action = await showMenu<PlaylistAction>(
      context: context,
      position: menuPosition(context, at: at),
      items: items,
    );

    if (action != null && mounted) {
      await runPlaylistAction(context, widget.playlist, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final strings = AppLocalizations.of(context);
    final tile = ListTile(
      leading: Thumbnail(playlist.coverArt, icon: HugeIcons.strokeRoundedPlaylist01),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: playlist.songCount == null ? null : Text(strings.trackCount(playlist.songCount!)),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist))),
      onLongPress: () => _openMenu(at: _pressedAt),
    );

    return MenuShortcuts(
      onOpen: _openMenu,
      child: Listener(onPointerDown: (event) => _pressedAt = event.position, child: tile),
    );
  }
}
