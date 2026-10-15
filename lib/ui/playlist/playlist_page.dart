import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../server/playlist_editor.dart';
import '../../services.dart';
import '../album/cover_page.dart';
import '../app/page_area.dart';
import '../app/page_bar.dart';
import '../artist/artist_link.dart';
import '../player/now_playing_bar.dart';
import '../song/current_song.dart';
import '../song/movable_song.dart';
import '../song/song_list_header.dart';
import '../song/song_menu.dart';
import '../widgets/cover.dart';
import '../widgets/download_button.dart';
import '../widgets/errors.dart';
import '../widgets/spinner.dart';
import '../widgets/themed_icon.dart';
import '../widgets/touch_screen.dart';
import 'playlist_menu.dart';

/// A playlist's page, laid out as an album's: its picture, its name, how many songs it has and how long they last, the
/// button that plays it, and its songs, each with its cover and its artists, which play the playlist from the one picked.
/// One the user can change has a menu that renames and deletes it, each song's menu takes the song out, and the songs
/// move by dragging them: on a touch screen, once held a moment, as the list scrolls otherwise; on a TV, which has no
/// drag, by the remote, from their menu ([MovableSongs]).
class PlaylistPage extends StatefulWidget {
  const PlaylistPage(this.playlist, {super.key});

  final Playlist playlist;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

/// A song's place in the playlist: a song can be in it more than once, and each place moves on its own.
class _Entry {
  _Entry(this.song);

  /// As the server last gave it.
  Song song;
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
    final services = ServicesScope.of(context);

    try {
      final (playlist, songs) = await services.api.playlist(widget.playlist.id);
      final downloads = services.downloads;

      // Downloaded, it follows the playlist as the server has it, its new songs downloading too.
      if (downloads?.ofPlaylist(playlist.id) case final download?
          when !listEquals([for (final song in download.songs) song.id], [for (final song in songs) song.id])) {
        unawaited(downloads!.addPlaylist(playlist, songs));
      }

      if (mounted && version == _version) {
        setState(() {
          _playlist = playlist;
          _entries = _entriesOf(songs);
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted && version == _version) {
        setState(() => _error = error);
      }
    }
  }

  /// The places of [songs], those the page shows already kept: each the first one left of its song, in order. So a line
  /// keeps its place in the tree, and with it the focus (a TV remote's), as the playlist loads again after a change.
  List<_Entry> _entriesOf(List<Song> songs) {
    final kept = <String, List<_Entry>>{};

    for (final entry in _entries ?? const <_Entry>[]) {
      kept.putIfAbsent(entry.song.id, () => []).add(entry);
    }

    return [
      for (final song in songs)
        switch (kept[song.id]) {
          final entries? when entries.isNotEmpty => entries.removeAt(0)..song = song,
          _ => _Entry(song),
        },
    ];
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
      messenger.showSnackBar(SnackBar(content: Text(strings.couldNotChangePlaylist(describeFailure(strings, error)))));
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

    if (offset == null) {
      return false;
    }

    if (context.phoneLayout) {
      final width = MediaQuery.sizeOf(context).width;
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
    // In a phone's layout (a tablet's too, as the home has it), the name is in the page's bar, over the picture, and
    // the songs have no header naming their columns.
    final phoneLayout = context.phoneLayout;
    final strings = AppLocalizations.of(context);
    final (playlist, entries, error) = (_playlist, _entries, _error);
    final shown = playlist != null && entries != null;

    return Scaffold(
      // On a phone with the name, the list's until the playlist comes; under a wide screen's top bar, none.
      appBar: PageArea.holdsUnderTopBar(context)
          ? null
          : PageBar(
              title: phoneLayout ? playlist?.name ?? widget.playlist.name : null,
              shade: phoneLayout && shown ? _shade : null,
            ),
      // On a phone the page goes on under the bar and the system's, to the top of the screen, as it scrolls.
      extendBodyBehindAppBar: phoneLayout && shown,
      body: switch ((playlist, entries)) {
        (final playlist?, final entries?) => NotificationListener(
          onNotification: _followScroll,
          child: _songs(playlist, entries, phoneLayout: phoneLayout),
        ),
        _ when error != null => Center(child: Text(strings.couldNotOpenPlaylist(describeFailure(strings, error)))),
        _ => const Center(child: Spinner()),
      },
      // The songs go on behind the player bar; in the page area the home's bars stay under the page instead, with the
      // room they take, which a bar of its own, even one showing nothing, would take away.
      extendBody: true,
      bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
    );
  }

  /// The page under its bar: the top, and the songs, which move where the user can change the playlist.
  Widget _songs(Playlist playlist, List<_Entry> entries, {required bool phoneLayout}) {
    final strings = AppLocalizations.of(context);
    final songs = [for (final entry in entries) entry.song];

    return CustomScrollView(
      slivers: [
        // On a wide screen, where the name is by the picture, and stays in sight once that has gone, with the button that
        // plays the playlist.
        if (!phoneLayout) PageBarSliver(title: playlist.name, shade: _shade, leading: _playButton(songs)),
        // Clear of the bars the page goes on under, by the room MediaQuery says they take, as a list is.
        SliverSafeArea(
          left: false,
          right: false,
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                // Built again as the device the app controls changes: its menu follows what that device takes.
                child: ListenableBuilder(
                  listenable: ServicesScope.of(context).connect,
                  builder: (context, _) => _header(playlist, songs, phoneLayout: phoneLayout),
                ),
              ),
              if (songs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.all(16), child: Text(strings.playlistEmpty)),
                )
              else if (!phoneLayout)
                const SliverToBoxAdapter(child: SongListHeader(menus: true)),
              MovableSongs(
                keys: [for (final entry in entries) ObjectKey(entry)],
                onMove: playlist.editable ? _move : null,
                itemBuilder: (_, index, byRemote) =>
                    _song(songs, index, editable: playlist.editable, phoneLayout: phoneLayout, byRemote: byRemote),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The top of the page: the playlist's picture, its name, how many songs it has and how long they last (where it has
  /// any: an empty one says so under it), the button that plays it, and, where it has anything in it, its menu. On a
  /// wide screen the name is beside the picture, under the word "Playlist", the buttons under them; in a phone's layout
  /// ([phoneLayout]) the name is in the page's bar, over the picture, which is centered, and the songs and their length
  /// under it, with the buttons at the end of their line, the play button last ([SongListTopLine]).
  Widget _header(Playlist playlist, List<Song> songs, {required bool phoneLayout}) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final details = songs.isEmpty ? null : Text(songCountAndLength(strings, songs), style: text.bodyMedium);
    final play = _playButton(songs);
    // None where it would have nothing: another user's playlist, with no public links (Jellyfin), while the app
    // controls a device that takes nothing added to its queue.
    final menu = playlistMenuItems(context, playlist, hasSongs: songs.isNotEmpty).isEmpty
        ? null
        : _menu(playlist, songs);
    // Asked of the server as an album's cover is.
    final picture = CoverButton(playlist.coverArt, size: 800, icon: HugeIcons.strokeRoundedPlaylist01);

    if (phoneLayout) {
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
          SongListTopLine(
            details: details ?? const SizedBox.shrink(),
            button: Row(mainAxisSize: MainAxisSize.min, children: [DownloadButton.playlist(playlist, songs), ?menu]),
            play: play,
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
                      DownloadButton.playlist(playlist, songs),
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

  /// The playlist's menu, which plays its [songs] next or adds them to the queue, renames it, and deletes it, closing its
  /// page.
  Widget _menu(Playlist playlist, List<Song> songs) {
    final strings = AppLocalizations.of(context);

    return PopupMenuButton<PlaylistAction>(
      tooltip: strings.moreOptions,
      icon: const ThemedIcon(HugeIcons.strokeRoundedMoreVertical),
      onSelected: (action) async {
        final navigator = Navigator.of(context);
        final page = ModalRoute.of(context);

        if (!await runPlaylistAction(context, playlist, action, songs: songs) || action != PlaylistAction.delete) {
          return;
        }

        // This page, wherever it is now: another opened over it meanwhile (the server taking its time) stays.
        if (page == null || !page.isActive) {
          return;
        }

        if (page.isCurrent) {
          navigator.pop();
        } else {
          navigator.removeRoute(page);
        }
      },
      itemBuilder: (context) => playlistMenuItems(context, playlist, hasSongs: songs.isNotEmpty),
    );
  }

  /// The playlist's song at [index], which plays the playlist from it; its menu takes it out of an [editable] one, and,
  /// on a TV, moves it by the remote ([byRemote]). In a phone's layout ([phoneLayout]), its artists are plain text.
  Widget _song(List<Song> songs, int index, {required bool editable, required bool phoneLayout, RemoteMove? byRemote}) {
    final song = songs[index];

    return CurrentSong(
      song,
      builder: (context, current, playing) => SongMenu(
        song,
        onMove: byRemote?.start,
        onRemove: editable ? () => _remove(index) : null,
        builder: (context, menu) {
          final line = ListTile(
            contentPadding: SongTrailing.tilePadding,
            selected: current,
            leading: Thumbnail(song.coverArt, playing: playing),
            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            // On a phone plain text, and elsewhere links that take no focus, as on an album's page.
            subtitle: song.artist == null
                ? null
                : phoneLayout
                ? Text(artistNames(song), maxLines: 1, overflow: TextOverflow.ellipsis)
                : ExcludeFocus(child: ArtistLinks.song(song)),
            trailing: SongTrailing(song.id, song.duration, menu),
            onTap: () => _play(songs, index),
          );

          return byRemote?.movable(line) ?? line;
        },
      ),
    );
  }
}
