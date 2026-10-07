import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import '../server/server.dart';
import '../services.dart';
import 'album_page.dart';
import 'album_play_button.dart';
import 'artist_link.dart';
import 'cover.dart';
import 'focus_ring.dart';
import 'order_chips.dart';
import 'spinner.dart';

/// How the app names an order of albums, and what a list in it says when it has none.
extension AlbumOrderText on AlbumOrder {
  String label(AppLocalizations strings) => switch (this) {
    AlbumOrder.name => strings.orderName,
    AlbumOrder.released => strings.orderReleased,
    AlbumOrder.mostPlayed => strings.mostPlayed,
    AlbumOrder.latest => strings.orderLatest,
  };

  String emptyMessage(AppLocalizations strings) =>
      this == AlbumOrder.mostPlayed ? strings.mostPlayedAlbumsEmpty : strings.libraryEmpty;
}

/// The library's albums in [order], or a genre's by name, a page at a time: the next as the grid nears
/// its end. Above the library's, chips pick the order.
class AlbumsView extends StatefulWidget {
  const AlbumsView({this.genre, this.header, this.order = AlbumOrder.name, this.onOrder, super.key});

  /// The genre whose albums it lists; null, the library's.
  final Genre? genre;

  /// Above the albums, scrolling with them.
  final Widget? header;

  /// The order of the library's albums.
  final AlbumOrder order;

  /// Picks another order, from the chips; null, no chips.
  final ValueChanged<AlbumOrder>? onOrder;

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  static const _pageSize = 200;

  /// The orders the chips pick from.
  static const _orders = [AlbumOrder.name, AlbumOrder.released, AlbumOrder.mostPlayed, AlbumOrder.latest];

  /// How far from the end of the grid the next page is asked for.
  static const _ahead = 800.0;

  final _albums = <Album>[];
  bool _started = false;
  bool _loading = false;

  /// The server has no more.
  bool _done = false;

  /// Why the latest page didn't come. Only "Tentar de novo" asks for it again.
  Object? _error;

  /// Counts the starts over, so that a page asked for before one is dropped.
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_started) {
      _started = true;
      scheduleMicrotask(_load); // out of the build
    }
  }

  /// Another order lists them again, from the start.
  @override
  void didUpdateWidget(AlbumsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.order != oldWidget.order) {
      _albums.clear();
      _done = false;
      _error = null;
      scheduleMicrotask(() => _load(over: true)); // out of the build
    }
  }

  /// Asks for the next page; [over], for the first again, which replaces the albums when it comes.
  Future<void> _load({bool over = false}) async {
    if (!mounted || (!over && (_loading || _done || _error != null))) {
      return;
    }

    final generation = over ? ++_generation : _generation;
    final api = ServicesScope.of(context).api;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final offset = over ? 0 : _albums.length;
      final page = await switch (widget.genre) {
        null => api.albums(order: widget.order, size: _pageSize, offset: offset),
        final genre => api.genreAlbums(genre.id, size: _pageSize, offset: offset),
      };

      if (!mounted || generation != _generation) {
        return;
      }

      setState(() {
        if (over) {
          _albums.clear();
        }

        _albums.addAll(page);
        _done = page.length < _pageSize;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }

      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _retry() {
    _error = null; // which keeps _load from asking by itself
    _load();
  }

  /// Asks for the next page when the grid nears its end: as it scrolls, and when it changes size.
  bool _scrolled(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final metrics) || ScrollMetricsNotification(:final metrics) => metrics,
      _ => null,
    };

    if (metrics != null && metrics.extentAfter < _ahead && !_loading && !_done && _error == null) {
      scheduleMicrotask(_load); // notifications can come during layout
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final onOrder = widget.onOrder;

    if (onOrder == null) {
      return _albumsGrid();
    }

    final strings = AppLocalizations.of(context);
    // The chips stay at the top, also while another order's albums come. Their line takes the whole width, the chips
    // starting at its left, lined up with the albums.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderChips(widget.order, orders: _orders, label: (order) => order.label(strings), onOrder: onOrder),
        Expanded(child: _albumsGrid()),
      ],
    );
  }

  Widget _albumsGrid() {
    final error = _error;
    final strings = AppLocalizations.of(context);

    if (_albums.isEmpty) {
      if (error != null) {
        return Center(child: _Retry(strings.couldNotListAlbums('$error'), onRetry: _retry));
      }

      if (!_done) {
        return const Center(child: Spinner());
      }
    }

    return NotificationListener<Notification>(
      onNotification: _scrolled,
      child: RefreshIndicator(
        onRefresh: () => _load(over: true),
        child: AlbumGrid(
          _albums,
          header: widget.header,
          footer: error != null
              ? _Retry(strings.couldNotListMoreAlbums('$error'), onRetry: _retry)
              : _loading
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(child: Spinner()),
                )
              : _albums.isEmpty && widget.genre == null
              ? Center(child: Text(widget.order.emptyMessage(strings)))
              : null,
        ),
      ),
    );
  }
}

/// What went wrong, and a button to try again.
class _Retry extends StatelessWidget {
  const _Retry(this.message, {required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: Text(AppLocalizations.of(context).tryAgain)),
      ],
    ),
  );
}

/// A section of an [AlbumGrid]: albums, under a title or none.
typedef AlbumSection = ({String? title, List<Album> albums});

/// Albums as a grid of covers, between an optional [header] and [footer]. Each opens its page.
class AlbumGrid extends StatelessWidget {
  /// [albums] in one grid, with no title.
  const AlbumGrid(List<Album> albums, {this.header, this.footer, this.subtitle, super.key})
    : _albums = albums,
      _sections = null;

  /// The albums of [sections], a grid for each, under its title.
  const AlbumGrid.sections(List<AlbumSection> sections, {this.header, this.footer, this.subtitle, super.key})
    : _albums = null,
      _sections = sections;

  final List<Album>? _albums;
  final List<AlbumSection>? _sections;

  /// Its albums, in sections: one with no title, from the default constructor.
  List<AlbumSection> get sections => _sections ?? [(title: null, albums: _albums!)];

  final Widget? header;
  final Widget? footer;

  /// The line under each name; the artist, by default.
  final String Function(Album album)? subtitle;

  /// How far a row's lines are from what comes under them: the next row's covers, or the next section's title. About as
  /// far as a list's last song is from a title under it, as the most played songs on an artist's page are from their
  /// albums.
  static const _below = 36.0;

  @override
  Widget build(BuildContext context) {
    final lines = AlbumTile.linesHeight(context);
    return CustomScrollView(
      slivers: [
        if (header != null) SliverToBoxAdapter(child: header),
        for (final (i, (:title, :albums)) in sections.indexed) ...[
          if (title != null)
            SliverToBoxAdapter(
              child: Padding(
                // Under another section, _below from its lines, which its grid and its tiles leave 16 under.
                padding: EdgeInsets.fromLTRB(16, i == 0 ? 24 : _below - 16, 16, 0),
                child: Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
          // Covers of up to 180 pixels, 16 from the edges and from one another, of which the tiles' room inside
          // (AlbumTile.padding) is part.
          SliverPadding(
            padding: const EdgeInsets.all(16 - AlbumTile.padding),
            sliver: SliverGrid.builder(
              gridDelegate: _AlbumGridDelegate(
                lines: lines,
                maxCrossAxisExtent: 180 + 2 * AlbumTile.padding,
                mainAxisSpacing: _below - 2 * AlbumTile.padding,
                crossAxisSpacing: 16 - 2 * AlbumTile.padding,
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) => AlbumTile(albums[i], subtitle: subtitle?.call(albums[i])),
            ),
          ),
        ],
        if (footer != null) SliverToBoxAdapter(child: footer),
        // Clear of the bars a phone's home has over it.
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}

/// An [AlbumGrid]'s tiles: as wide as [SliverGridDelegateWithMaxCrossAxisExtent] makes them, and as tall as what they
/// hold, with no room left under their lines. A tile's cover is as wide as it, less the room inside on either side,
/// which it has above and below too: the tile is as much taller than wide as its [lines] take.
class _AlbumGridDelegate extends SliverGridDelegateWithMaxCrossAxisExtent {
  const _AlbumGridDelegate({
    required this.lines,
    required super.maxCrossAxisExtent,
    super.mainAxisSpacing,
    super.crossAxisSpacing,
  });

  /// [AlbumTile.linesHeight].
  final double lines;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final layout = super.getLayout(constraints) as SliverGridRegularTileLayout;
    final height = layout.childCrossAxisExtent + lines;
    return SliverGridRegularTileLayout(
      crossAxisCount: layout.crossAxisCount,
      mainAxisStride: height + mainAxisSpacing,
      crossAxisStride: layout.crossAxisStride,
      childMainAxisExtent: height,
      childCrossAxisExtent: layout.childCrossAxisExtent,
      reverseCrossAxis: layout.reverseCrossAxis,
    );
  }

  @override
  bool shouldRelayout(_AlbumGridDelegate oldDelegate) =>
      super.shouldRelayout(oldDelegate) || oldDelegate.lines != lines;
}

/// An album's cover, with its name and a line under it. It opens the album's page, but for its
/// artist, under the name, who opens theirs, and the button over the cover, which plays it.
class AlbumTile extends StatefulWidget {
  const AlbumTile(this.album, {this.subtitle, super.key});

  final Album album;

  /// The line under the name; the artist, by default.
  final String? subtitle;

  /// The room inside, around the cover and the lines under it, where the tint (the pointer's, the focus's) shows. The
  /// grid and the rows take it from the room around the albums, so that the covers line up with what is over them.
  static const padding = 8.0;

  /// The room between the cover and the name.
  static const _spaceAboveName = 6.0;

  /// What a tile holds under its cover, at the size its text shows: the room above its name, its name and the line
  /// under it, one line each.
  static double linesHeight(BuildContext context) {
    final text = Theme.of(context).textTheme;

    double lineHeight(TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: ' ', style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return _spaceAboveName + lineHeight(text.titleSmall) + lineHeight(text.bodySmall);
  }

  @override
  State<AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<AlbumTile> {
  /// The pointer is over the album: its play button shows.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final text = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FocusRing(
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlbumPage(album))),
          child: Padding(
            padding: const EdgeInsets.all(AlbumTile.padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Cover(album.coverArt)),
                      ),
                      Positioned.fill(child: AlbumPlayButton(album, hovered: _hovered)),
                    ],
                  ),
                ),
                const SizedBox(height: AlbumTile._spaceAboveName),
                Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                if (widget.subtitle case final line?)
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall)
                else
                  // The artist takes no focus: for the keyboard and the remote the album stays one stop, as
                  // the song in the player bar is. The album's page links them too.
                  ExcludeFocus(child: ArtistLink.album(album, style: text.bodySmall)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
