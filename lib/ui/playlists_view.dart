import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import '../server/playlist_editor.dart';
import '../services.dart';
import 'cover.dart';
import 'playlist_dialogs.dart';
import 'playlist_page.dart';
import 'spinner.dart';

/// The user's playlists, and those others share with them, by name, each with its picture and how many songs it has,
/// opening its page, under a button that makes a new one. They load again as the app changes any.
class PlaylistsView extends StatefulWidget {
  const PlaylistsView({super.key});

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  Future<List<Playlist>>? _playlists;
  PlaylistEditor? _editor;

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
  Widget build(BuildContext context) => FutureBuilder(
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
            // The button that makes one first; with none, a line that says so under it, which a drag down loads again,
            // as it does the list.
            itemCount: 1 + (playlists.isEmpty ? 1 : playlists.length),
            itemBuilder: (context, i) {
              if (i == 0) {
                return const NewPlaylistTile();
              }

              if (playlists.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(strings.playlistsEmpty, textAlign: TextAlign.center),
                );
              }

              final playlist = playlists[i - 1];
              return ListTile(
                leading: Thumbnail(playlist.coverArt, icon: HugeIcons.strokeRoundedPlaylist01),
                title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: playlist.songCount == null ? null : Text(strings.trackCount(playlist.songCount!)),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist))),
              );
            },
          ),
        ),
      );
    },
  );
}
