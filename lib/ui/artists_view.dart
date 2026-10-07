import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../server/models.dart';
import '../services.dart';
import 'artist_page.dart';
import 'cover.dart';
import 'focus_ring.dart';
import 'spinner.dart';

/// "1 álbum", "5 álbuns"; empty when the server didn't say.
String albumCount(int? count) => switch (count) {
  null => '',
  1 => '1 álbum',
  _ => '$count álbuns',
};

/// The library's artists, by name.
class ArtistsView extends StatefulWidget {
  const ArtistsView({super.key});

  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  Future<List<Artist>>? _artists;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _artists ??= ServicesScope.of(context).api.artists();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _artists,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('Não consegui listar os artistas: ${snapshot.error}'));
      }

      final artists = snapshot.data;

      if (artists == null) {
        return const Center(child: Spinner());
      }

      return RefreshIndicator(
        onRefresh: () async {
          final reload = ServicesScope.of(context).api.artists();
          setState(() => _artists = reload);
          await reload;
        },
        // Pictures of up to 180 pixels, 16 from the edges and from one another, of which the tiles' room inside
        // (_ArtistTile.padding) is part, as the albums' are; the rows as far apart as with no room inside. At the end,
        // clear of the bars a phone's home has over them.
        child: GridView.builder(
          padding:
              const EdgeInsets.all(16 - _ArtistTile.padding) +
              EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180 + 2 * _ArtistTile.padding,
            mainAxisSpacing: 16 - 2 * _ArtistTile.padding,
            crossAxisSpacing: 16 - 2 * _ArtistTile.padding,
            childAspectRatio: 0.74,
          ),
          itemCount: artists.length,
          itemBuilder: (context, i) => _ArtistTile(artists[i]),
        ),
      );
    },
  );
}

/// An artist's picture, with their name and how many albums they have, which opens their page. While the pointer is
/// over the artist, the picture darkens a little, as an album's cover does under its play button.
class _ArtistTile extends StatefulWidget {
  const _ArtistTile(this.artist);

  final Artist artist;

  /// The room inside, around the picture and the lines under it, where the tint (the pointer's, the focus's) shows, as
  /// an album has (`AlbumTile.padding`). The grid takes it from the room around the artists.
  static const padding = 8.0;

  @override
  State<_ArtistTile> createState() => _ArtistTileState();
}

class _ArtistTileState extends State<_ArtistTile> {
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
            padding: const EdgeInsets.all(_ArtistTile.padding),
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Cover(artist.coverArt, icon: HugeIcons.strokeRoundedUser),
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
                Text(albumCount(artist.albumCount), maxLines: 1, style: text.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
