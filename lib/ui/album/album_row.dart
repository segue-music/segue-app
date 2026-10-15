import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../widgets/errors.dart';
import '../widgets/spinner.dart';
import '../widgets/tile_row.dart';
import 'albums_view.dart';

/// A titled row of albums, which scrolls sideways: by the arrows in its right corner, or dragged.
class AlbumRow extends StatelessWidget {
  const AlbumRow({
    required this.title,
    required this.albums,
    this.initialAlbums,
    this.empty,
    this.onShowAll,
    super.key,
  });

  final String title;
  final Future<List<Album>> albums;

  /// What it shows until [albums] come, rather than a spinner: on the home, those it showed the time before.
  final List<Album>? initialAlbums;

  /// What the row says when there are none; null, nothing: the row is out, its title too, once they have come.
  final String? empty;

  /// Shows all of them, past the row's: what its title, a link then, opens.
  final VoidCallback? onShowAll;

  /// How many albums it shows at most.
  static const maxAlbums = 30;

  /// How big each tile is: covers of 160 pixels, with the tiles' room inside ([AlbumTile.padding]); as tall as its cover
  /// and the lines under it, as a tile of the album grid is, with no room left under them.
  static Size tileSize(BuildContext context) =>
      Size(160 + 2 * AlbumTile.padding, 160 + 2 * AlbumTile.padding + AlbumTile.linesHeight(context));

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: albums,
    initialData: initialAlbums,
    builder: (context, snapshot) {
      // While new albums come (the home pulled down to list them again), the ones before, where they were.
      final albums = snapshot.data;

      if (empty == null && !snapshot.hasError && (albums?.isEmpty ?? false)) {
        return const SizedBox.shrink();
      }

      final text = Theme.of(context).textTheme;
      final strings = AppLocalizations.of(context);
      final tileSize = AlbumRow.tileSize(context);

      Widget note(String message) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(message, style: text.bodyMedium),
      );

      return TileRow(
        // The new ones from the first, rather than where the ones before were scrolled to.
        key: ObjectKey(albums),
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
          _ when snapshot.hasError => note(strings.couldNotListAlbums(describeFailure(strings, snapshot.error))),
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
