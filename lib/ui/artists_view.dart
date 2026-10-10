import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/favorites.dart';
import '../server/models.dart';
import '../services.dart';
import 'artist_page.dart';
import 'cover.dart';
import 'focus_ring.dart';
import 'segmented_choice.dart';
import 'spinner.dart';
import 'themed_icon.dart';

/// "1 álbum", "5 álbuns"; empty when the server didn't say.
String albumCount(AppLocalizations strings, int? count) => count == null ? '' : strings.albumCount(count);

/// Orders the library's artists come in, or the user's favorite ones alone: what the choice above them says of one, the
/// icon it can show instead, and what a list in it says when it has none.
enum _ArtistOrder {
  name,
  mostPlayed,
  favorites;

  String label(AppLocalizations strings) => switch (this) {
    name => strings.orderName,
    mostPlayed => strings.mostPlayed,
    favorites => strings.favorites,
  };

  /// From A to Z; what the user listens to, as an artist's page has it; the heart that makes one a favorite.
  HugeIconData get icon => switch (this) {
    name => HugeIcons.strokeRoundedSortingAZ02,
    mostPlayed => HugeIcons.strokeRoundedHeadphones,
    favorites => HugeIcons.strokeRoundedFavourite,
  };

  String emptyMessage(AppLocalizations strings) => switch (this) {
    name => strings.libraryEmpty,
    mostPlayed => strings.mostPlayedArtistsEmpty,
    favorites => strings.favoriteArtistsEmpty,
  };
}

/// The library's artists, by name or the most played first, or the user's favorite ones alone, as they change, as
/// picked in a [SegmentedChoice] above them.
class ArtistsView extends StatefulWidget {
  const ArtistsView({super.key});

  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  _ArtistOrder _order = _ArtistOrder.name;
  Future<List<Artist>>? _artists;

  /// The user's favorites, which [_ArtistOrder.favorites] lists as they change.
  Favorites? _favorites;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _artists ??= _load();
    final favorites = ServicesScope.of(context).favorites;

    if (favorites != _favorites) {
      _favorites?.removeListener(_favoritesChanged);
      _favorites = favorites..addListener(_favoritesChanged);
    }
  }

  @override
  void dispose() {
    _favorites?.removeListener(_favoritesChanged);
    super.dispose();
  }

  /// The favorites changed: listing them, once they have come, the list follows them.
  void _favoritesChanged() {
    final favorites = _favorites!;

    if (_order == _ArtistOrder.favorites && favorites.loaded) {
      // In braces: setState takes no callback that returns a future, as the assignment would.
      setState(() {
        _artists = Future.value(favorites.artists);
      });
    }
  }

  /// The artists, in the order picked; the favorites as the server has them now, or as they were, where it can't say
  /// and they came before.
  Future<List<Artist>> _load() async {
    final services = ServicesScope.of(context);
    final api = services.api;
    return switch (_order) {
      _ArtistOrder.name => api.artists(),
      _ArtistOrder.mostPlayed => api.mostPlayedArtists(),
      _ArtistOrder.favorites => _loadFavorites(services.favorites),
    };
  }

  static Future<List<Artist>> _loadFavorites(Favorites favorites) async {
    try {
      await favorites.load();
    } on Object {
      if (!favorites.loaded) {
        rethrow;
      }
    }

    return favorites.artists;
  }

  /// Another order lists them again, from the start.
  void _reorder(_ArtistOrder order) => setState(() {
    _order = order;
    _artists = _load();
  });

  // The choice stays at the top, also while another order's artists come, as the albums' chips do. On a phone, or a
  // window as narrow (as the home counts it), it shows icons, their names in tooltips, as an artist's page does.
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // At the left, lined up with the pictures, with the room the albums' chips have around them.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedChoice<_ArtistOrder>(
              _order,
              options: _ArtistOrder.values,
              label: (order) => order.label(strings),
              icon: narrow ? (order) => order.icon : null,
              onSelected: _reorder,
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            // Another order's starts over, with none of the last one's artists; a refresh keeps them until the new
            // come.
            key: ValueKey(_order),
            future: _artists,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text(strings.couldNotListArtists('${snapshot.error}')));
              }

              final artists = snapshot.data;

              if (artists == null) {
                return const Center(child: Spinner());
              }

              return RefreshIndicator(
                onRefresh: () async {
                  final reload = _load();
                  setState(() => _artists = reload);
                  await reload;
                },
                child: artists.isEmpty
                    // Scrolling all the same, for the refresh to pull.
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [Center(child: Text(_order.emptyMessage(strings)))],
                      )
                    : _ArtistGrid(artists),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Artists as a grid of pictures, each of which opens their page.
class _ArtistGrid extends StatelessWidget {
  const _ArtistGrid(this.artists);

  final List<Artist> artists;

  // Pictures of up to 180 pixels, 16 from the edges and from one another, of which the tiles' room inside
  // (ArtistTile.padding) is part, as the albums' are; the rows as far apart as with no room inside. At the end, clear
  // of the bars a phone's home has over them.
  @override
  Widget build(BuildContext context) => GridView.builder(
    padding:
        const EdgeInsets.all(16 - ArtistTile.padding) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 180 + 2 * ArtistTile.padding,
      mainAxisSpacing: 16 - 2 * ArtistTile.padding,
      crossAxisSpacing: 16 - 2 * ArtistTile.padding,
      childAspectRatio: ArtistTile.aspectRatio,
    ),
    itemCount: artists.length,
    itemBuilder: (context, i) => ArtistTile(artists[i]),
  );
}

/// An artist's picture, with their name and how many albums they have, which opens their page. While the pointer is
/// over the artist, the picture darkens a little, as an album's cover does under its play button.
class ArtistTile extends StatefulWidget {
  const ArtistTile(this.artist, {super.key});

  final Artist artist;

  /// The room inside, around the picture and the lines under it, where the tint (the pointer's, the focus's) shows, as
  /// an album has (`AlbumTile.padding`). The grid takes it from the room around the artists.
  static const padding = 8.0;

  /// How wide it is for how tall, with room for the picture and the two lines under it.
  static const aspectRatio = 0.74;

  @override
  State<ArtistTile> createState() => _ArtistTileState();
}

class _ArtistTileState extends State<ArtistTile> {
  /// The pointer is over the artist: their picture darkens.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final text = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FocusRing(
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist))),
          child: Padding(
            padding: const EdgeInsets.all(ArtistTile.padding),
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ArtistPicture(artist),
                        // The album cover's shade (AlbumPlayButton), coming and going in the same fade.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: _hovered
                              ? const ColoredBox(color: Colors.black26, child: SizedBox.expand())
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                Text(albumCount(AppLocalizations.of(context), artist.albumCount), maxLines: 1, style: text.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
