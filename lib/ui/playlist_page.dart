import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import '../server/playlist_editor.dart';
import '../services.dart';
import 'artist_link.dart';
import 'cover.dart';
import 'cover_page.dart';
import 'current_song.dart';
import 'errors.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'page_bar.dart';
import 'playlist_menu.dart';
import 'song_list_header.dart';
import 'song_menu.dart';
import 'spinner.dart';
import 'themed_icon.dart';

/// A playlist's page, laid out as an album's: its picture, its name, how many songs it has and how long they last, the
/// button that plays it, and its songs, each with its cover and its artists, which play the playlist from the one picked.
/// One the user can change has a menu that renames and deletes it, each song's menu takes the song out, and the songs
/// move by dragging them: on a touch screen, once held a moment, as the list scrolls otherwise.
class PlaylistPage extends StatefulWidget {
  const PlaylistPage(this.playlist, {super.key});

  final Playlist playlist;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

/// A song's place in the playlist: a song can be in it more than once, and each place moves on its own.
class _Entry {
  _Entry(this.song);

  final Song song;
}

class _PlaylistPageState extends State<PlaylistPage> {
  /// The playlist and its songs as the page shows them: as the server last gave them, with the changes made here since.
  /// Null until they come.
  Playlist? _playlist;
  List<_Entry>? _entries;

  /// Why the playlist didn't come, where none has.
  Object? _error;

  /// Counts the loads, and the changes made here: a load that another one, or a change, has come after is dropped.
  int _version = 0;

  PlaylistEditor? _editor;

  /// How much of the page's color its bar has, as on an album's page: on a phone, more as the picture goes up under it;
  /// on a wide screen, how much of the bar shows, which comes in as the picture goes ([PageBarSliver.shadeAt]).
  final _shade = ValueNotifier<double>(0);

  /// How big the picture is on a wide screen, square, 16 from the top of the page: an album's cover's size.
  static const _widePicture = 220.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_editor == null) {
      // Changes made elsewhere too, as adding a song from an album's page: the playlist as the server has it then.
      _editor = ServicesScope.of(context).playlistEditor..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _editor?.removeListener(_load);
    _shade.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_version;

    try {
      final (playlist, songs) = await ServicesScope.of(context).api.playlist(widget.playlist.id);

      if (mounted && version == _version) {
        setState(() {
          _playlist = playlist;
          _entries = [for (final song in songs) _Entry(song)];
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted && version == _version) {
        setState(() => _error = error);
      }
    }
  }

  /// Makes [change] on the page at once, and [edit] on the server, saying why where that fails; either way the page then
  /// shows the playlist as the server has it.
  void _edit(VoidCallback change, Future<void> Function(PlaylistEditor editor) edit) {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppLocalizations.of(context);
    // A load under way would show the playlist as it was.
    _version++;
    setState(change);
    edit(_editor!).catchError((Object error) {
      messenger.showSnackBar(SnackBar(content: Text(strings.couldNotChangePlaylist('$error'))));
    });
  }

  void _remove(int index) =>
      _edit(() => _entries!.removeAt(index), (editor) => editor.remove(widget.playlist.id, [index]));

  /// Moves the song at [from] to [to], the place it then has.
  void _move(int from, int to) {
    if (to != from) {
      _edit(
        () => _entries!.insert(to, _entries!.removeAt(from)),
        (editor) => editor.move(widget.playlist.id, from: from, to: to),
      );
    }
  }

  /// Follows the page as it scrolls, and as it's laid out anew, for its bar's color ([_shade]), letting the
  /// notification go on.
  bool _followScroll(Notification notification) {
    final offset = switch (notification) {
      ScrollNotification(depth: 0, :final metrics) ||
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics.pixels,
      _ => null,
    };
    final width = MediaQuery.sizeOf(context).width;

    if (offset == null) {
      return false;
    }

    if (width < 600) {
      // The picture is as wide as the page less its margins, up to 280, under a gap of 8 (_header).
      final picture = min(width - 2 * 16, 280);
      _shade.value = (offset / (8 + picture / 2)).clamp(0, 1);
    } else {
      _shade.value = PageBarSliver.shadeAt(offset, pictureBottom: 16 + _widePicture);
    }

    return false;
  }

  Future<void> _play(List<Song> songs, int index) async {
    final result = await ServicesScope.of(context).connect.playSongs(songs, index);

    if (!result.ok && mounted) {
      final message = describeError(AppLocalizations.of(context), result.error);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // On a phone, or a window as narrow (as the home counts it), the name is in the page's bar, over the picture, and
    // the songs have no header naming their columns.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final strings = AppLocalizations.of(context);
    final (playlist, entries, error) = (_playlist, _entries, _error);
    final shown = playlist != null && entries != null;
    return Scaffold(
      // On a phone with the name, the list's until the playlist comes; under a wide screen's top bar, none.
      appBar: PageArea.holdsUnderTopBar(context)
          ? null
          : PageBar(
              title: narrow ? playlist?.name ?? widget.playlist.name : null,
              shade: narrow && shown ? _shade : null,
            ),
      // On a phone the page goes on under the bar and the system's, to the top of the screen, as it scrolls.
      extendBodyBehindAppBar: narrow && shown,
      body: switch ((playlist, entries)) {
        (final playlist?, final entries?) => NotificationListener(
          onNotification: _followScroll,
          child: _songs(playlist, entries, narrow: narrow),
        ),
        _ when error != null => Center(child: Text(strings.couldNotOpenPlaylist('$error'))),
        _ => const Center(child: Spinner()),
      },
      // The songs go on behind the player bar; in the page area the home's bars stay under the page instead, with the
      // room they take, which a bar of its own, even one showing nothing, would take away.
      extendBody: true,
      bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
    );
  }

  /// The page under its bar: the top, and the songs, which move where the user can change the playlist.
  Widget _songs(Playlist playlist, List<_Entry> entries, {required bool narrow}) {
    final strings = AppLocalizations.of(context);
    final songs = [for (final entry in entries) entry.song];
    final theme = Theme.of(context);
    final touch = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
    };

    Widget song(BuildContext context, int index) {
      final entry = entries[index];
      final tile = _song(songs, index, editable: playlist.editable, narrow: narrow);

      if (!playlist.editable) {
        return KeyedSubtree(key: ObjectKey(entry), child: tile);
      }

      // On a touch screen a drag scrolls the list, and moves a song once held a moment; with a mouse, at once.
      return touch
          ? ReorderableDelayedDragStartListener(key: ObjectKey(entry), index: index, child: tile)
          : ReorderableDragStartListener(key: ObjectKey(entry), index: index, child: tile);
    }

    return CustomScrollView(
      slivers: [
        // On a wide screen, where the name is by the picture, and stays in sight once that has gone, with the button that
        // plays the playlist.
        if (!narrow) PageBarSliver(title: playlist.name, shade: _shade, leading: _playButton(songs)),
        // Clear of the bars the page goes on under, by the room MediaQuery says they take, as a list is.
        SliverSafeArea(
          left: false,
          right: false,
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: _header(playlist, songs, narrow: narrow)),
              if (songs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.all(16), child: Text(strings.playlistEmpty)),
                )
              else if (!narrow)
                const SliverToBoxAdapter(child: SongListHeader(menus: true)),
              SliverReorderableList(
                itemCount: entries.length,
                itemBuilder: song,
                onReorderItem: _move,
                // The song moving, lifted over the others, on the page's color: in the overlay, over the page.
                proxyDecorator: (child, index, animation) => Material(
                  elevation: 4,
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The top of the page: the playlist's picture, its name, how many songs it has and how long they last (where it has
  /// any: an empty one says so under it), the button that plays it, and, where the user can change it, its menu. On a
  /// wide screen the name is beside the picture, under the word "Playlist", the buttons under them; on a narrow one
  /// ([narrow]) the name is in the page's bar, over the picture, which is centered, and the songs and their length under
  /// it, with the buttons at the end of their line, the play button last.
  Widget _header(Playlist playlist, List<Song> songs, {required bool narrow}) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final details = songs.isEmpty ? null : Text(songCountAndLength(strings, songs), style: text.bodyMedium);
    final play = _playButton(songs);
    final menu = playlist.editable ? _menu(playlist) : null;
    // Asked of the server as an album's cover is.
    final picture = CoverButton(playlist.coverArt, size: 800, icon: HugeIcons.strokeRoundedPlaylist01);

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: AspectRatio(aspectRatio: 1, child: picture),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: details ?? const SizedBox.shrink()),
                const SizedBox(width: 16),
                if (menu != null) ...[menu, const SizedBox(width: 8)],
                play,
              ],
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: _widePicture, child: picture),
          const SizedBox(width: 16),
          // Centered on the picture, which stays at the top where a long name is taller.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _widePicture),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.playlist, style: text.labelLarge),
                  Text(playlist.name, style: text.titleLarge),
                  ?details,
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      play,
                      if (menu != null) ...[const SizedBox(width: 8), menu],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The button that plays the playlist from its first song: just the icon, its name in the tooltip, as an album's.
  Widget _playButton(List<Song> songs) => IconButton.filled(
    tooltip: AppLocalizations.of(context).playPlaylist,
    onPressed: songs.isEmpty ? null : () => _play(songs, 0),
    icon: const ThemedIcon(HugeIcons.strokeRoundedPlay),
  );

  /// The playlist's menu, which renames it, and deletes it, closing its page.
  Widget _menu(Playlist playlist) {
    final strings = AppLocalizations.of(context);
    return PopupMenuButton<PlaylistAction>(
      tooltip: strings.moreOptions,
      icon: const ThemedIcon(HugeIcons.strokeRoundedMoreVertical),
      onSelected: (action) async {
        final navigator = Navigator.of(context);

        if (await runPlaylistAction(context, playlist, action) && action == PlaylistAction.delete) {
          navigator.maybePop();
        }
      },
      itemBuilder: (context) => playlistMenuItems(strings),
    );
  }

  /// The playlist's song at [index], which plays the playlist from it; its menu takes it out of an [editable] one. On a
  /// [narrow] screen, its artists are plain text.
  Widget _song(List<Song> songs, int index, {required bool editable, required bool narrow}) {
    final song = songs[index];
    return CurrentSong(
      song,
      builder: (context, current, playing) => SongMenu(
        song,
        onRemove: editable ? () => _remove(index) : null,
        builder: (context, menu) => ListTile(
          selected: current,
          leading: Thumbnail(song.coverArt, playing: playing),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          // On a phone plain text, and elsewhere links that take no focus, as on an album's page.
          subtitle: song.artist == null
              ? null
              : narrow
              ? Text(artistNames(song), maxLines: 1, overflow: TextOverflow.ellipsis)
              : ExcludeFocus(child: ArtistLinks.song(song)),
          trailing: SongTrailing(song.duration, menu),
          onTap: () => _play(songs, index),
        ),
      ),
    );
  }
}
