import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import 'directional_navigation.dart';
import 'focus_ring.dart';
import 'text_link.dart';
import 'themed_icon.dart';

/// A titled row of tiles (albums, artists), which scrolls sideways: dragged, by the remote going along its tiles, or,
/// on a computer, by the arrows in its right corner.
class TileRow extends StatelessWidget {
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

  /// How big each tile is, with the room inside it ([tilePadding]): a picture as wide as it, less that room, over its
  /// lines. On a TV, a bit wider, for a piece of the next one to show at the screen's side, and as much taller, as its
  /// picture grows.
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
  Widget build(BuildContext context) =>
      DirectionalNavigation.of(context) ? _TelevisionTileRow(this) : _PointerTileRow(this);
}

/// A row that a finger drags, on a touch screen, or, on a computer, that the arrows in its corner scroll, the keyboard
/// going along its tiles.
class _PointerTileRow extends StatefulWidget {
  const _PointerTileRow(this.row);

  final TileRow row;

  @override
  State<_PointerTileRow> createState() => _PointerTileRowState();
}

class _PointerTileRowState extends State<_PointerTileRow> {
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
    final stride = widget.row.tileSize.width + TileRow._gap;
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
    final row = widget.row;
    final tiles = row.tiles;
    // By the platform, not by whether a mouse is connected: on a computer the system says the mouse is
    // gone whenever the pointer leaves the window.
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
    };

    return _TitledRow(
      row: row,
      // As tall with the arrows as without them.
      titleHeight: 48,
      // None on a touch screen, where a finger drags the row.
      trailing: touch ? null : _arrows(),
      strip: tiles == null
          ? null
          : NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                _metrics.value = notification.metrics;

                return false;
              },
              child: _TileStrip(controller: _scroll, tiles: tiles, tileSize: row.tileSize),
            ),
    );
  }

  /// Back and forward, each while there are tiles that way; none when they all fit. Out of the focus's way: the
  /// keyboard goes along the tiles themselves. Close together, as the top bar's: smaller buttons than the rest.
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
              tooltip: widget.row.previousLabel,
              style: arrows,
              icon: const ThemedIcon(HugeIcons.strokeRoundedArrowLeft01),
              onPressed: position.extentBefore > 0 ? () => _page(-1) : null,
            ),
            IconButton(
              tooltip: widget.row.nextLabel,
              style: arrows,
              icon: const ThemedIcon(HugeIcons.strokeRoundedArrowRight01),
              onPressed: position.extentAfter > 0 ? () => _page(1) : null,
            ),
          ],
        ),
      );
    },
  );
}

/// On a TV, a row that the remote goes along, tile by tile. It has no arrows, which the remote would never reach: its
/// tiles are a bit bigger, rather, for a piece of one to show at the screen's side ([_peek]), saying that more follow.
/// The one with the focus grows ([FocusRing.grows]) in the first one's place ([_keepAtStart]).
class _TelevisionTileRow extends StatefulWidget {
  const _TelevisionTileRow(this.row);

  final TileRow row;

  /// How much of a tile shows past the whole ones, cut off at the screen's side: that the row goes on, which a
  /// computer's arrows say.
  static const _peek = 0.4;

  /// How much further in the row starts, its title and its tiles alike, for the tile with the focus in the first one's
  /// place to grow into (6% of one about 200 wide, 6 to each side) with its ring clear of what is beside the row (the
  /// home's rail), as far as from the screen's other edges.
  static const _grownSide = 8.0;

  @override
  State<_TelevisionTileRow> createState() => _TelevisionTileRowState();
}

class _TelevisionTileRowState extends State<_TelevisionTileRow> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = widget.row.tiles;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _tileSize(constraints.maxWidth);

        return _TitledRow(
          row: widget.row,
          start: _TelevisionTileRow._grownSide,
          strip: tiles == null
              ? null
              : _TileStrip(
                  controller: _scroll,
                  tileSize: size,
                  start: _TelevisionTileRow._grownSide,
                  // For a tile to grow with the focus without its ring cut off by the row's edges.
                  room: (size.height * (FocusRing.grownScale - 1) / 2).ceilToDouble(),
                  tiles: [
                    for (final (i, tile) in tiles.indexed)
                      Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onFocusChange: (focused) {
                          if (focused) {
                            _keepAtStart(i, size);
                          }
                        },
                        child: tile,
                      ),
                  ],
                ),
        );
      },
    );
  }

  /// How big each tile is in a row [width] wide: a bit wider than [TileRow.tileSize], as much as shows
  /// [_TelevisionTileRow._peek] of a tile at the screen's side, rather than the tiles that happen to fit, whole, with
  /// nothing to say that more follow; and as much taller, its picture growing as it, and its lines staying as they are.
  Size _tileSize(double width) {
    final size = widget.row.tileSize;
    final room = width - TileRow._edge - _TelevisionTileRow._grownSide + TileRow._gap;
    final whole = max(1, (room / (size.width + TileRow._gap) - _TelevisionTileRow._peek).floor());
    final grownWidth = room / (whole + _TelevisionTileRow._peek) - TileRow._gap;

    return Size(grownWidth, size.height + grownWidth - size.width);
  }

  /// The row scrolled to have the tile [index], which the focus has come to, in its first tile's place, as Google TV's
  /// rows keep it, the rest moving under it: the tiles after it stay in view, and the piece of one at the screen's side
  /// ([_TelevisionTileRow._peek]). At the row's ends, as far as it goes.
  void _keepAtStart(int index, Size size) {
    if (!_scroll.hasClients) {
      return;
    }

    final position = _scroll.position;
    _scroll.animateTo(
      (index * (size.width + TileRow._gap)).clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }
}

/// A row's title, a link to all its tiles, over them ([strip]), or, while it has none, over what it shows instead
/// ([TileRow.instead]).
class _TitledRow extends StatelessWidget {
  const _TitledRow({required this.row, required this.strip, this.start = 0, this.titleHeight, this.trailing});

  final TileRow row;
  final Widget? strip;

  /// How much further in than the row's edge the title starts, as its tiles do.
  final double start;

  /// How tall the title's line is; null, as tall as the title.
  final double? titleHeight;

  /// What follows the title, at the row's end.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Out of the room at the screen's side, where the system has the app keep out of it (on a TV, its edges): the
      // tiles run on to the side as they scroll, the last stopping out of it.
      Padding(
        padding: EdgeInsets.fromLTRB(16 + start, 12, 12 + MediaQuery.paddingOf(context).right, 4),
        child: SizedBox(
          height: titleHeight,
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextLink(
                    row.title,
                    tooltip: AppLocalizations.of(context).showAll,
                    onTap: row.onShowAll,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
      strip ?? row.instead,
    ],
  );
}

/// A row's tiles, side by side, which scroll sideways by [controller]: each [tileSize] big, [start] further in than the
/// row's edge, with [room] above and below them.
class _TileStrip extends StatelessWidget {
  const _TileStrip({
    required this.controller,
    required this.tiles,
    required this.tileSize,
    this.start = 0,
    this.room = 0,
  });

  final ScrollController controller;
  final List<Widget> tiles;
  final Size tileSize;
  final double start;
  final double room;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: tileSize.height + 2 * room,
    child: ScrollConfiguration(
      // No scrollbar, which desktops add by themselves: the arrows take its place. Dragged with a
      // mouse too: a vertical wheel scrolls the page, not the row.
      behavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, dragDevices: PointerDeviceKind.values.toSet()),
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(
          TileRow._edge + start,
          room,
          TileRow._edge + MediaQuery.paddingOf(context).right,
          room,
        ),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: TileRow._gap),
        itemBuilder: (context, i) => SizedBox(width: tileSize.width, child: tiles[i]),
      ),
    ),
  );
}
