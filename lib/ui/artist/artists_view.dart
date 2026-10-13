import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../server/favorites.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../widgets/cover.dart';
import '../widgets/focus_ring.dart';
import '../widgets/order_chips.dart';
import '../widgets/spinner.dart';
import 'artist_page.dart';

/// "1 álbum", "5 álbuns"; empty when the server didn't say.
String albumCount(AppLocalizations strings, int? count) => count == null ? '' : strings.albumCount(count);

/// Orders the library's artists come in, or the user's favorite ones alone: what the chip above them says of one, and
/// what a list in it says when it has none.
enum ArtistOrder {
  name,
  mostPlayed,
  favorites;

  String label(AppLocalizations strings) => switch (this) {
    name => strings.orderName,
    mostPlayed => strings.mostPlayed,
    favorites => strings.favorites,
  };

  String emptyMessage(AppLocalizations strings) => switch (this) {
    name => strings.libraryEmpty,
    mostPlayed => strings.mostPlayedArtistsEmpty,
    favorites => strings.favoriteArtistsEmpty,
  };
}

/// The library's artists, by name or the most played first, or the user's favorite ones alone, as they change, as
/// picked in chips above them ([OrderChips]), as the albums' orders are.
class ArtistsView extends StatefulWidget {
  const ArtistsView({required this.order, required this.onOrder, super.key});

  /// The order picked: the home's, which the favorites' page also picks, opening them.
  final ArtistOrder order;

  /// Picks another order, in the chips.
  final ValueChanged<ArtistOrder> onOrder;

  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  Future<List<Artist>>? _artists;

  /// The user's favorites, which [ArtistOrder.favorites] lists as they change.
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
  void didUpdateWidget(ArtistsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Another order lists them again, from the start.
    if (widget.order != oldWidget.order) {
      _artists = _load();
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

    if (widget.order == ArtistOrder.favorites && favorites.loaded) {
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

    return switch (widget.order) {
      ArtistOrder.name => api.artists(),
      ArtistOrder.mostPlayed => api.mostPlayedArtists(),
      ArtistOrder.favorites => _loadFavorites(services.favorites),
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

  /// Another order lists them again, from the start ([didUpdateWidget]); the one picked, as they are.
  void _reorder(ArtistOrder order) {
    if (order != widget.order) {
      widget.onOrder(order);
    }
  }

  // The chips stay at the top, also while another order's artists come, as the albums' do, lined up with the pictures.
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderChips(widget.order, orders: ArtistOrder.values, label: (order) => order.label(strings), onOrder: _reorder),
        Expanded(
          child: FutureBuilder(
            // Another order's starts over, with none of the last one's artists; a refresh keeps them until the new
            // come.
            key: ValueKey(widget.order),
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
                        children: [Center(child: Text(widget.order.emptyMessage(strings)))],
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

/// An artist's picture, with their name, which opens their page. No count of their albums: the media servers count only
/// those they are the album artist of, not those they sing on. While the pointer is over the artist, the picture
/// darkens a little, as an album's cover does under its play button.
class ArtistTile extends StatefulWidget {
  const ArtistTile(this.artist, {super.key});

  final Artist artist;

  /// The room inside, around the picture and the line under it, where the tint (the pointer's, the focus's) shows, as
  /// an album has (`AlbumTile.padding`). The grid takes it from the room around the artists.
  static const padding = 8.0;

  /// How wide it is for how tall, with room for the picture and the line under it.
  static const aspectRatio = 0.79;

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
        grows: true,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
