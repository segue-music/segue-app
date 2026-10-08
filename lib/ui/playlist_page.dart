import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import '../services.dart';
import 'artist_link.dart';
import 'cover.dart';
import 'cover_page.dart';
import 'current_song.dart';
import 'errors.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'page_bar.dart';
import 'song_list_header.dart';
import 'spinner.dart';
import 'themed_icon.dart';

/// A playlist's page, laid out as an album's: its picture, its name, how many songs it has and how long they last, the
/// button that plays it, and its songs, each with its cover and its artists, which play the playlist from the one picked.
class PlaylistPage extends StatefulWidget {
  const PlaylistPage(this.playlist, {super.key});

  final Playlist playlist;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  Future<(Playlist, List<Song>)>? _playlist;

  /// How much of the page's color its bar has, as on an album's page: on a phone, more as the picture goes up under it;
  /// on a wide screen, how much of the bar shows, which comes in as the picture goes ([PageBarSliver.shadeAt]).
  final _shade = ValueNotifier<double>(0);

  /// How big the picture is on a wide screen, square, 16 from the top of the page: an album's cover's size.
  static const _widePicture = 220.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playlist ??= ServicesScope.of(context).api.playlist(widget.playlist.id);
  }

  @override
  void dispose() {
    _shade.dispose();
    super.dispose();
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
    return FutureBuilder(
      future: _playlist,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          // On a phone with the name, the list's until the playlist comes; under a wide screen's top bar, none.
          appBar: PageArea.holdsUnderTopBar(context)
              ? null
              : PageBar(
                  title: narrow ? data?.$1.name ?? widget.playlist.name : null,
                  shade: narrow && data != null ? _shade : null,
                ),
          // On a phone the page goes on under the bar and the system's, to the top of the screen, as it scrolls.
          extendBodyBehindAppBar: narrow && data != null,
          body: switch (data) {
            _ when snapshot.hasError => Center(child: Text(strings.couldNotOpenPlaylist('${snapshot.error}'))),
            null => const Center(child: Spinner()),
            (final playlist, final songs) => NotificationListener(
              onNotification: _followScroll,
              child: CustomScrollView(
                slivers: [
                  // On a wide screen, where the name is by the picture, and stays in sight once that has gone, with the
                  // button that plays the playlist.
                  if (!narrow) PageBarSliver(title: playlist.name, shade: _shade, leading: _playButton(songs)),
                  // Clear of the bars the page goes on under, by the room MediaQuery says they take, as a list is.
                  SliverSafeArea(
                    left: false,
                    right: false,
                    sliver: SliverList.list(
                      children: [
                        _header(playlist, songs, narrow: narrow),
                        if (songs.isEmpty)
                          Padding(padding: const EdgeInsets.all(16), child: Text(strings.playlistEmpty))
                        else if (!narrow)
                          const SongListHeader(),
                        for (var i = 0; i < songs.length; i++) _song(songs, i),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          },
          // The songs go on behind the player bar; in the page area the home's bars stay under the page instead, with
          // the room they take, which a bar of its own, even one showing nothing, would take away.
          extendBody: true,
          bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
        );
      },
    );
  }

  /// The top of the page: the playlist's picture, its name, how many songs it has and how long they last (where it has
  /// any: an empty one says so under it), and the button that plays it. On a wide screen the name is beside the picture,
  /// under the word "Playlist", the button under them; on a narrow one ([narrow]) the name is in the page's bar, over
  /// the picture, which is centered, and the songs and their length under it, with the button at the end of their line.
  Widget _header(Playlist playlist, List<Song> songs, {required bool narrow}) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final details = songs.isEmpty ? null : Text(songCountAndLength(strings, songs), style: text.bodyMedium);
    final play = _playButton(songs);
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
                  play,
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

  /// The playlist's song at [index], which plays the playlist from it.
  Widget _song(List<Song> songs, int index) {
    final song = songs[index];
    return CurrentSong(
      song,
      builder: (context, current, playing) => ListTile(
        selected: current,
        leading: Thumbnail(song.coverArt, playing: playing),
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        // The artists take no focus: for the keyboard and the remote the song stays one stop, as on an album's page.
        subtitle: song.artist == null ? null : ExcludeFocus(child: ArtistLinks.song(song)),
        trailing: SongDuration(song.duration),
        onTap: () => _play(songs, index),
      ),
    );
  }
}
