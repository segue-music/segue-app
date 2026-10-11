import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import 'text_link.dart';
import 'themed_icon.dart';

/// A titled row of tiles (albums, artists), which scrolls sideways: dragged, or, on a computer and a TV, by the arrows in
/// its right corner.
class TileRow extends StatefulWidget {
  const TileRow({
    required this.title,
    required this.tileSize,
    required this.previousLabel,
    required this.nextLabel,
    this.tiles,
    this.instead = const SizedBox.shrink(),
    this.onShowAll,
    super.key,
  });

  final String title;

  /// Its tiles; null while it has none to show, and shows [instead].
  final List<Widget>? tiles;

  /// What it shows under its title without tiles: that they are coming, that there are none, or why.
  final Widget instead;

  /// How big each tile is, with the room inside it ([tilePadding]).
  final Size tileSize;

  /// What the arrows scroll back to and forward to, in their tooltips.
  final String previousLabel;
  final String nextLabel;

  /// Shows all of them, past the row's: what its title, a link then, opens.
  final VoidCallback? onShowAll;

  /// The room inside a tile, around what it shows, where its tint (the pointer's, the focus's) shows: an album's
  /// (`AlbumTile.padding`), as an artist's.
  static const tilePadding = 8.0;

  /// Tiles 16 from the edges (lined up with the title) and from one another, of which their room inside is part.
  static const _edge = 16 - tilePadding;
  static const _gap = 16 - 2 * tilePadding;

  @override
  State<TileRow> createState() => _TileRowState();
}

class _TileRowState extends State<TileRow> {
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

  /// Scrolls a screenful of tiles forward (1) or back (-1), with a tile at the left edge.
  void _page(int direction) {
    final position = _scroll.position;
    final stride = widget.tileSize.width + TileRow._gap;
    final perScreen = max(1, ((position.viewportDimension - 2 * TileRow._edge + TileRow._gap) / stride).floor());
    // A bit of slack, so that a tile a hair off the edge still counts as at it.
    final at = position.pixels / stride;
    final tile = direction > 0 ? (at + 0.01).floor() + perScreen : (at - 0.01).ceil() - perScreen;
    _scroll.animateTo(
      (tile * stride).clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final tiles = widget.tiles;
    // By the platform, not by whether a mouse is connected: on a computer the system says the mouse is
    // gone whenever the pointer leaves the window. A TV has no touch screen.
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
    };
    final television = MediaQuery.navigationModeOf(context) == NavigationMode.directional;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
          child: SizedBox(
            height: 48, // the same with the arrows or without them
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextLink(
                      widget.title,
                      tooltip: strings.showAll,
                      onTap: widget.onShowAll,
                      style: text.titleLarge,
                    ),
                  ),
                ),
                if (!touch || television) _arrows(),
              ],
            ),
          ),
        ),
        if (tiles == null) widget.instead else SizedBox(height: widget.tileSize.height, child: _strip(tiles)),
      ],
    );
  }

  /// Back and forward, each while there are tiles that way; none when they all fit, nor on a touch screen, where a
  /// finger drags the row. Out of the focus's way: the keyboard and the remote go along the tiles themselves. Close
  /// together, as the top bar's: smaller buttons than the rest, without the room Material leaves around them on a TV,
  /// as on a touch screen.
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

      final arrows = IconButton.styleFrom(
        padding: const EdgeInsets.all(4),
        minimumSize: const Size.square(32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

      return ExcludeFocus(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: widget.previousLabel,
              style: arrows,
              icon: const ThemedIcon(HugeIcons.strokeRoundedArrowLeft01),
              onPressed: position.extentBefore > 0 ? () => _page(-1) : null,
            ),
            IconButton(
              tooltip: widget.nextLabel,
              style: arrows,
              icon: const ThemedIcon(HugeIcons.strokeRoundedArrowRight01),
              onPressed: position.extentAfter > 0 ? () => _page(1) : null,
            ),
          ],
        ),
      );
    },
  );

  Widget _strip(List<Widget> tiles) => NotificationListener<ScrollMetricsNotification>(
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
        padding: const EdgeInsets.symmetric(horizontal: TileRow._edge),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: TileRow._gap),
        itemBuilder: (context, i) => SizedBox(width: widget.tileSize.width, child: tiles[i]),
      ),
    ),
  );
}
