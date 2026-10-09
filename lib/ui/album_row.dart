import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import 'albums_view.dart';
import 'spinner.dart';
import 'tile_row.dart';

/// A titled row of albums, which scrolls sideways: by the arrows in its right corner, or dragged.
class AlbumRow extends StatelessWidget {
  const AlbumRow({required this.title, required this.albums, this.empty, this.onShowAll, super.key});

  final String title;
  final Future<List<Album>> albums;

  /// What the row says when there are none; null, nothing, for a page that leaves an empty row out.
  final String? empty;

  /// Shows all of them, past the row's: what its title, a link then, opens.
  final VoidCallback? onShowAll;

  /// How many albums it shows at most.
  static const maxAlbums = 30;

  /// How big each tile is: covers of 160 pixels, with the tiles' room inside ([AlbumTile.padding]); as tall as a tile of
  /// the album grid this wide.
  static const tileSize = Size(160 + 2 * AlbumTile.padding, (160 + 2 * AlbumTile.padding) / 0.75);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: albums,
    builder: (context, snapshot) {
      final text = Theme.of(context).textTheme;
      final strings = AppLocalizations.of(context);

      Widget note(String message) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(message, style: text.bodyMedium),
      );

      final albums = snapshot.data;
      return TileRow(
        title: title,
        onShowAll: onShowAll,
        tileSize: tileSize,
        previousLabel: strings.previousAlbums,
        nextLabel: strings.nextAlbums,
        // Also from a server that sends more than it was asked for.
        tiles: snapshot.hasError || albums == null || albums.isEmpty
            ? null
            : [for (final album in albums.take(maxAlbums)) AlbumTile(album)],
        instead: switch (albums) {
          _ when snapshot.hasError => note(strings.couldNotListAlbums('${snapshot.error}')),
          null => SizedBox(
            height: tileSize.height,
            child: const Center(child: Spinner()),
          ),
          _ => switch (empty) {
            null => const SizedBox.shrink(),
            final message => note(message),
          },
        },
      );
    },
  );
}
