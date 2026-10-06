import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../server/models.dart';
import 'albums_view.dart';
import 'spinner.dart';
import 'text_link.dart';

/// A titled row of albums, which scrolls sideways: by the arrows in its right corner, or dragged.
class AlbumRow extends StatefulWidget {
  const AlbumRow({required this.title, required this.albums, this.empty, this.onShowAll, super.key});

  final String title;
  final Future<List<Album>> albums;

  /// What the row says when there are none; null, nothing, for a page that leaves an empty row out.
  final String? empty;

  /// Shows all of them, past the row's: what its title, a link then, opens.
  final VoidCallback? onShowAll;

  /// How many albums it shows at most.
  static const maxAlbums = 30;

  static const _tileWidth = 160.0;
  static const _gap = 16.0;

  /// As tall as a tile of the album grid this wide.
  static const _height = _tileWidth / 0.75;

  @override
  State<AlbumRow> createState() => _AlbumRowState();
}

class _AlbumRowState extends State<AlbumRow> {
  final _scroll = ScrollController();

  /// The row's latest size and length, which change without scrolling it: once it is first laid out,
  /// and when the window changes.
  final _metrics = ValueNotifier<ScrollMetrics?>(null);

  @override
  void dispose() {
    _scroll.dispose();
    _metrics.dispose();
    super.dispose();
  }

  /// Scrolls a screenful of albums forward (1) or back (-1), with an album at the left edge.
  void _page(int direction) {
    final position = _scroll.position;
    const stride = AlbumRow._tileWidth + AlbumRow._gap;
    final perScreen = max(1, ((position.viewportDimension - AlbumRow._gap) / stride).floor());
    // A bit of slack, so that an album a hair off the edge still counts as at it.
    final at = position.pixels / stride;
    final album = direction > 0 ? (at + 0.01).floor() + perScreen : (at - 0.01).ceil() - perScreen;
    _scroll.animateTo(
      (album * stride).clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    Widget note(String message) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(message, style: text.bodyMedium),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: SizedBox(
            height: 48, // the arrows' height, also without them
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextLink(
                      widget.title,
                      tooltip: 'Ver todos',
                      onTap: widget.onShowAll,
                      style: text.titleLarge,
                    ),
                  ),
                ),
                _arrows(),
              ],
            ),
          ),
        ),
        FutureBuilder(
          future: widget.albums,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return note('Não consegui listar os álbuns: ${snapshot.error}');
            }

            final albums = snapshot.data;

            if (albums == null) {
              return const SizedBox(
                height: AlbumRow._height,
                child: Center(child: Spinner()),
              );
            }

            if (albums.isEmpty) {
              return switch (widget.empty) {
                null => const SizedBox.shrink(),
                final message => note(message),
              };
            }

            // Also from a server that sends more than it was asked for.
            return SizedBox(height: AlbumRow._height, child: _strip(albums.take(AlbumRow.maxAlbums).toList()));
          },
        ),
      ],
    );
  }

  /// Back and forward, each while there are albums that way; none when they all fit. Out of the
  /// focus's way: the keyboard and the remote go along the albums themselves.
  Widget _arrows() => ListenableBuilder(
    listenable: Listenable.merge([_scroll, _metrics]),
    builder: (context, _) {
      if (!_scroll.hasClients) {
        return const SizedBox.shrink();
      }

      final position = _scroll.position;

      if (!position.hasContentDimensions || position.maxScrollExtent <= position.minScrollExtent) {
        return const SizedBox.shrink();
      }

      return ExcludeFocus(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Anteriores',
              icon: const Icon(HugeIcons.strokeRoundedArrowLeft01),
              onPressed: position.extentBefore > 0 ? () => _page(-1) : null,
            ),
            IconButton(
              tooltip: 'Próximos',
              icon: const Icon(HugeIcons.strokeRoundedArrowRight01),
              onPressed: position.extentAfter > 0 ? () => _page(1) : null,
            ),
          ],
        ),
      );
    },
  );

  Widget _strip(List<Album> albums) => NotificationListener<ScrollMetricsNotification>(
    onNotification: (notification) {
      _metrics.value = notification.metrics;
      return false;
    },
    child: ScrollConfiguration(
      // No scrollbar, which desktops add by themselves: the arrows take its place. Dragged with a
      // mouse too: a vertical wheel scrolls the page, not the row.
      behavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, dragDevices: PointerDeviceKind.values.toSet()),
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AlbumRow._gap),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: AlbumRow._gap),
        itemBuilder: (context, i) => SizedBox(width: AlbumRow._tileWidth, child: AlbumTile(albums[i])),
      ),
    ),
  );
}
