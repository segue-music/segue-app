import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../album/album_row.dart';
import '../album/albums_view.dart';
import '../app/page_area.dart';
import '../artist/artists_view.dart';
import '../player/now_playing_bar.dart';
import '../song/song_list_header.dart';
import '../widgets/errors.dart';
import '../widgets/spinner.dart';
import '../widgets/text_link.dart';
import '../widgets/themed_icon.dart';
import '../widgets/tile_row.dart';
import 'favorite_songs_page.dart';

/// The user's favorites, by kind: the songs, as a line of their picture ([FavoritesPicture]) as big as an album's cover,
/// how many they are and how long they last, and the button that plays them, which opens their page
/// ([FavoriteSongsPage]), as their title does; then a row of the albums and one of the artists, as the home's, whose
/// titles open all of them, in their tab. A kind with none isn't there. They load as the page opens, and follow the
/// favorites as they change.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({this.onShowAlbums, this.onShowArtists, super.key});

  /// Shows all the favorite albums, in the albums tab, and the artists, in theirs: what the rows' titles, links then,
  /// open.
  final VoidCallback? onShowAlbums;
  final VoidCallback? onShowArtists;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  /// Why they didn't come, where they haven't once.
  Object? _error;

  /// Whether the page has asked for them.
  bool _asked = false;

  /// The songs' picture, as big as an album's cover in a row ([AlbumRow.tileSize]).
  static const _picture = 160.0;

  /// Pictures of 160 pixels in the row of artists, as an album's cover is in its row, with the tiles' room inside
  /// ([ArtistTile.padding]), as on an artist's page.
  static const _artistTileSize = Size(
    160 + 2 * ArtistTile.padding,
    (160 + 2 * ArtistTile.padding) / ArtistTile.aspectRatio,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_asked) {
      _asked = true;
      _load();
    }
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

  Future<void> _play(List<Song> songs) async {
    final result = await ServicesScope.of(context).connect.playSongs(songs, 0);

    if (!result.ok && mounted) {
      final message = describeError(AppLocalizations.of(context), result.error);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final favorites = ServicesScope.of(context).favorites;

    return Scaffold(
      appBar: AppBar(
        // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
        automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
        title: Text(strings.favorites),
      ),
      body: ListenableBuilder(
        listenable: favorites,
        builder: (context, _) {
          final error = _error;
          final (songs, albums, artists) = (favorites.songs, favorites.albums, favorites.artists);

          if (!favorites.loaded) {
            return Center(child: error == null ? const Spinner() : Text(strings.couldNotListFavorites('$error')));
          }

          if (songs.isEmpty && albums.isEmpty && artists.isEmpty) {
            return Center(
              child: Padding(padding: const EdgeInsets.all(16), child: Text(strings.favoritesEmpty)),
            );
          }

          return ListView(
            children: [
              if (songs.isNotEmpty) ...[_songsTitle(), _songs(songs)],
              if (albums.isNotEmpty)
                TileRow(
                  title: strings.albums,
                  onShowAll: widget.onShowAlbums,
                  tiles: [for (final album in albums) AlbumTile(album)],
                  tileSize: AlbumRow.tileSize(context),
                  previousLabel: strings.previousAlbums,
                  nextLabel: strings.nextAlbums,
                ),
              if (artists.isNotEmpty)
                TileRow(
                  title: strings.artists,
                  onShowAll: widget.onShowArtists,
                  tiles: [for (final artist in artists) ArtistTile(artist)],
                  tileSize: _artistTileSize,
                  previousLabel: strings.previousArtists,
                  nextLabel: strings.nextArtists,
                ),
            ],
          );
        },
      ),
      // In the page area the home's bars stay under the page, with the room they take, which a bar of its own, even one
      // showing nothing, would take away.
      extendBody: true,
      bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
    );
  }

  void _openSongs() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FavoriteSongsPage()));

  /// The songs' title, a link to their page, as a row's is to all its tiles.
  Widget _songsTitle() {
    final strings = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextLink(
          strings.songs,
          tooltip: strings.showAll,
          onTap: _openSongs,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }

  /// The songs' line, which opens their page: their picture, lined up with the albums' covers under it, then how many
  /// they are and how long they last, and right after, the button that plays them.
  Widget _songs(List<Song> songs) {
    final strings = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16 - TileRow.tilePadding),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: _openSongs,
        child: Padding(
          padding: const EdgeInsets.all(TileRow.tilePadding),
          child: Row(
            children: [
              const SizedBox.square(dimension: _picture, child: FavoritesPicture()),
              const SizedBox(width: 16),
              Flexible(child: Text(songCountAndLength(strings, songs), style: Theme.of(context).textTheme.bodyLarge)),
              const SizedBox(width: 16),
              IconButton.filled(
                tooltip: strings.play,
                onPressed: () => _play(songs),
                icon: const ThemedIcon(HugeIcons.strokeRoundedPlay),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
