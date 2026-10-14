import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../album/album_page.dart';
import '../widgets/cover.dart';
import '../widgets/focus_ring.dart';
import '../widgets/text_link.dart';
import '../widgets/tile_row.dart';

/// The albums the user played last, at the top of the home, as small tiles in a grid, each its cover and its name: to go
/// back to one at a glance, as Spotify's home starts, rather than a row of big covers that pushes the rest down. [max] at
/// most, in two columns on a phone and four on a wider screen, each [maxTileWidth] wide at most, under the title, which opens them all ([onShowAll]). Out,
/// title and all, until they come, and before anything has played; [initialAlbums], those the home showed the time
/// before, meanwhile.
class RecentAlbums extends StatelessWidget {
  const RecentAlbums({required this.albums, this.initialAlbums, this.onShowAll, super.key});

  final Future<List<Album>> albums;
  final List<Album>? initialAlbums;
  final VoidCallback? onShowAll;

  /// How many it shows at most: two rows of four, or four of two.
  static const max = 8;

  /// How tall a tile is, its cover as tall.
  static const tileHeight = 56.0;

  /// How wide a tile gets at most: on a computer's wide screen, four wider ones would stretch a name on its card far past
  /// its cover. The grid starts at the page's margin, as the rows under it do.
  static const maxTileWidth = 280.0;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: albums,
    initialData: initialAlbums,
    builder: (context, snapshot) {
      final albums = snapshot.data ?? const <Album>[];

      if (snapshot.hasError || albums.isEmpty) {
        return const SizedBox.shrink();
      }

      final strings = AppLocalizations.of(context);
      // Lined up with the rows under them, a TV's further in.
      final start = 16 + TileRow.startOf(context);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // As a row's title is, out of the room at the screen's side (a TV's edges).
          Padding(
            padding: EdgeInsets.fromLTRB(start, 12, 12 + MediaQuery.paddingOf(context).right, 4),
            child: TextLink(
              strings.orderRecentlyPlayed,
              tooltip: strings.showAll,
              onTap: onShowAll,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(start, 4, 16 + MediaQuery.paddingOf(context).right, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 560 ? 2 : 4;
                final width = min((constraints.maxWidth - _gap * (columns - 1)) / columns, maxTileWidth);

                // As wide as its columns: the wrap would otherwise fit as many narrower tiles on a line as the screen has
                // room for.
                return SizedBox(
                  width: width * columns + _gap * (columns - 1),
                  child: Wrap(
                    spacing: _gap,
                    runSpacing: _gap,
                    children: [
                      for (final album in albums.take(max)) SizedBox(width: width, child: _RecentAlbum(album)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

/// An album as the home's last played show it: its cover, as tall as the tile, and its name beside it, on a card of the
/// theme's container color. It opens the album's page.
class _RecentAlbum extends StatelessWidget {
  const _RecentAlbum(this.album);

  final Album album;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

    return FocusRing(
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          customBorder: shape,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlbumPage(album))),
          child: SizedBox(
            height: RecentAlbums.tileHeight,
            child: Row(
              children: [
                // Asked of the server at twice its size, for a screen of 2 pixels a point.
                SizedBox.square(dimension: RecentAlbums.tileHeight, child: Cover(album.coverArt, size: 112)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    album.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
