import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../app/page_area.dart';
import '../app/page_bar.dart';
import '../artist/artist_link.dart';
import '../player/now_playing_bar.dart';
import '../song/current_song.dart';
import '../song/favorite_button.dart';
import '../song/song_list_header.dart';
import '../song/song_menu.dart';
import '../widgets/cover.dart';
import '../widgets/errors.dart';
import '../widgets/spinner.dart';
import '../widgets/themed_icon.dart';

/// The picture of the user's favorite songs: a heart, filled, on the theme's color, rounded as a cover is, by [radius].
class FavoritesPicture extends StatelessWidget {
  const FavoritesPicture({this.radius = 8, super.key});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: colors.primaryContainer,
        child: LayoutBuilder(
          builder: (context, box) => Center(
            child: ThemedIcon(filledHeart, size: box.biggest.shortestSide * 0.4, color: colors.onPrimaryContainer),
          ),
        ),
      ),
    );
  }
}

/// The user's favorite songs, laid out as a playlist's page: their picture ([FavoritesPicture]), their name, how many
/// they are and how long they last, the button that plays them, and the songs, each with its cover and its artists,
/// which play them from the one picked, and whose menu takes it out of them. They load as the page opens, and follow
/// the favorites as they change.
class FavoriteSongsPage extends StatefulWidget {
  const FavoriteSongsPage({super.key});

  @override
  State<FavoriteSongsPage> createState() => _FavoriteSongsPageState();
}

class _FavoriteSongsPageState extends State<FavoriteSongsPage> {
  /// Why they didn't come, where they haven't once.
  Object? _error;

  /// Whether the page has asked for them.
  bool _asked = false;

  /// How much of the page's color its bar has, as on a playlist's page.
  final _shade = ValueNotifier<double>(0);

  /// How big the picture is on a wide screen, as a playlist's.
  static const _widePicture = 220.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_asked) {
      _asked = true;
      _load();
    }
  }

  @override
  void dispose() {
    _shade.dispose();
    super.dispose();
  }

  /// Asks for them, as the server has them now.
  Future<void> _load() async {
    try {
      await ServicesScope.of(context).favorites.load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  /// Follows the page as it scrolls, for its bar's color ([_shade]), as a playlist's page does.
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
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final strings = AppLocalizations.of(context);
    final favorites = ServicesScope.of(context).favorites;

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final error = _error;
        final shown = favorites.loaded;

        return Scaffold(
          appBar: PageArea.holdsUnderTopBar(context)
              ? null
              : PageBar(title: narrow ? strings.favoriteSongs : null, shade: narrow && shown ? _shade : null),
          extendBodyBehindAppBar: narrow && shown,
          body: switch (shown) {
            true => NotificationListener(
              onNotification: _followScroll,
              child: _songs(favorites.songs, narrow: narrow),
            ),
            false when error != null => Center(child: Text(strings.couldNotListFavorites('$error'))),
            false => const Center(child: Spinner()),
          },
          extendBody: true,
          bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
        );
      },
    );
  }

  /// The page under its bar: the top, and the songs.
  Widget _songs(List<Song> songs, {required bool narrow}) {
    final strings = AppLocalizations.of(context);

    return CustomScrollView(
      slivers: [
        if (!narrow) PageBarSliver(title: strings.favoriteSongs, shade: _shade, leading: _playButton(songs)),
        SliverSafeArea(
          left: false,
          right: false,
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: _header(songs, narrow: narrow)),
              if (songs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.all(16), child: Text(strings.favoriteSongsEmpty)),
                )
              else if (!narrow)
                const SliverToBoxAdapter(child: SongListHeader(menus: true)),
              SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, i) => _song(songs, i, narrow: narrow),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The top of the page, as a playlist's: on a wide screen the name beside the picture, the button under it; on a
  /// [narrow] one the name in the page's bar, over the picture, and how many songs they are under it, with the button
  /// at the end of their line.
  Widget _header(List<Song> songs, {required bool narrow}) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final details = songs.isEmpty ? null : Text(songCountAndLength(strings, songs), style: text.bodyMedium);
    final play = _playButton(songs);

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: const AspectRatio(aspectRatio: 1, child: FavoritesPicture()),
              ),
            ),
          ),
          SongListTopLine(details: details ?? const SizedBox.shrink(), play: play),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox.square(dimension: _widePicture, child: FavoritesPicture()),
          const SizedBox(width: 16),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _widePicture),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.playlist, style: text.labelLarge),
                  Text(strings.favoriteSongs, style: text.titleLarge),
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

  /// The button that plays them from the first: just the icon, its name in the tooltip, as a playlist's.
  Widget _playButton(List<Song> songs) => IconButton.filled(
    tooltip: AppLocalizations.of(context).playPlaylist,
    onPressed: songs.isEmpty ? null : () => _play(songs, 0),
    icon: const ThemedIcon(HugeIcons.strokeRoundedPlay),
  );

  /// The song at [index], which plays them from it; on a [narrow] screen, its artists are plain text.
  Widget _song(List<Song> songs, int index, {required bool narrow}) {
    final song = songs[index];

    return CurrentSong(
      song,
      key: ObjectKey(song),
      builder: (context, current, playing) => SongMenu(
        song,
        builder: (context, menu) => ListTile(
          contentPadding: SongTrailing.tilePadding,
          selected: current,
          leading: Thumbnail(song.coverArt, playing: playing),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: song.artist == null
              ? null
              : narrow
              ? Text(artistNames(song), maxLines: 1, overflow: TextOverflow.ellipsis)
              : ExcludeFocus(child: ArtistLinks.song(song)),
          trailing: SongTrailing(song.id, song.duration, menu),
          onTap: () => _play(songs, index),
        ),
      ),
    );
  }
}
