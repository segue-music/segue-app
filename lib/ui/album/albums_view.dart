import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../downloads/downloads.dart';
import '../../l10n/app_localizations.dart';
import '../../server/favorites.dart';
import '../../server/models.dart';
import '../../server/server.dart';
import '../../services.dart';
import '../artist/artist_link.dart';
import '../widgets/cover.dart';
import '../widgets/focus_ring.dart';
import '../widgets/letter_bar.dart';
import '../widgets/order_chips.dart';
import '../widgets/scroll_focus.dart';
import '../widgets/spinner.dart';
import 'album_page.dart';
import 'album_play_button.dart';

/// How the app names an order of albums, and what a list in it says when it has none.
extension AlbumOrderText on AlbumOrder {
  String label(AppLocalizations strings) => switch (this) {
    AlbumOrder.name => strings.orderName,
    AlbumOrder.released => strings.orderReleased,
    AlbumOrder.mostPlayed => strings.mostPlayed,
    AlbumOrder.recentlyPlayed => strings.orderRecentlyPlayed,
    AlbumOrder.latest => strings.orderLatest,
  };

  String emptyMessage(AppLocalizations strings) => switch (this) {
    AlbumOrder.mostPlayed => strings.mostPlayedAlbumsEmpty,
    AlbumOrder.recentlyPlayed => strings.recentlyPlayedAlbumsEmpty,
    AlbumOrder.name || AlbumOrder.released || AlbumOrder.latest => strings.libraryEmpty,
  };
}

/// Which albums the albums tab shows: the library's, in an order, the downloaded alone, or the user's favorites alone.
enum AlbumsShown { library, downloaded, favorites }

/// The library's albums in [order], or a genre's by name, a page at a time: the next as the grid nears
/// its end; or the albums downloaded, or the user's favorite ones ([shown]). Above the library's, chips pick the order,
/// and after them "Favoritos", the favorites alone, and, where the app downloads, "Baixados", the downloaded alone. The
/// albums by name have their letters beside them ([LetterBar]).
class AlbumsView extends StatefulWidget {
  const AlbumsView({
    this.genre,
    this.header,
    this.order = AlbumOrder.name,
    this.onOrder,
    this.shown = AlbumsShown.library,
    this.onShown,
    super.key,
  });

  /// The genre whose albums it lists; null, the library's.
  final Genre? genre;

  /// Above the albums, scrolling with them.
  final Widget? header;

  /// The order of the library's albums.
  final AlbumOrder order;

  /// Picks another order, from the chips; null, no chips.
  final ValueChanged<AlbumOrder>? onOrder;

  /// Whether it shows the library's albums in [order], the albums downloaded alone, the latest downloaded first, or the
  /// user's favorite albums alone, as the media server lists them; these as they come and go.
  final AlbumsShown shown;

  /// Shows the downloaded alone, or the favorites alone, from the chips after the orders'; null, no such chips.
  final ValueChanged<AlbumsShown>? onShown;

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  static const _pageSize = 200;

  /// The pages asked for on the way to a letter, as many albums as Navidrome gives at once.
  static const _jumpPageSize = 500;

  /// The orders the chips pick from.
  static const _orders = [
    AlbumOrder.name,
    AlbumOrder.released,
    AlbumOrder.mostPlayed,
    AlbumOrder.recentlyPlayed,
    AlbumOrder.latest,
  ];

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

  /// The page on its way, which a jump to a letter waits for.
  Future<void>? _page;

  /// The grid's sliver, which a jump to a letter scrolls to the album it starts at.
  final _grid = GlobalKey();

  /// Counts the jumps to a letter, so that one picked before another, waiting for its pages, is dropped.
  int _jumps = 0;

  /// What was downloaded, which [AlbumsShown.downloaded] lists as it changes.
  Downloads? _downloads;

  /// The user's favorites, which [AlbumsShown.favorites] lists as they change.
  Favorites? _favorites;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final services = ServicesScope.of(context);
    final downloads = services.downloads;

    if (downloads != _downloads) {
      _downloads?.removeListener(_downloadsChanged);
      _downloads = downloads?..addListener(_downloadsChanged);
    }

    if (services.favorites != _favorites) {
      _favorites?.removeListener(_favoritesChanged);
      _favorites = services.favorites..addListener(_favoritesChanged);
    }

    if (!_started) {
      _started = true;
      scheduleMicrotask(_load); // out of the build
    }
  }

  @override
  void dispose() {
    _downloads?.removeListener(_downloadsChanged);
    _favorites?.removeListener(_favoritesChanged);
    super.dispose();
  }

  /// The downloaded albums, the latest downloaded first.
  List<Album> get _downloadedAlbums => [for (final download in _downloads?.all ?? const <Download>[]) ?download.album];

  /// A download came or went: listing the downloaded, the list follows it.
  void _downloadsChanged() {
    if (widget.shown == AlbumsShown.downloaded) {
      _show(_downloadedAlbums);
    }
  }

  /// The favorites changed: listing them, once they have come, the list follows them.
  void _favoritesChanged() {
    final favorites = _favorites;

    if (widget.shown == AlbumsShown.favorites && favorites != null && favorites.loaded) {
      _show(favorites.albums);
    }
  }

  /// Shows [albums], where they aren't those shown.
  void _show(List<Album> albums) {
    if (!_sameAlbums(albums, _albums)) {
      setState(() {
        _albums
          ..clear()
          ..addAll(albums);
      });
    }
  }

  static bool _sameAlbums(List<Album> a, List<Album> b) =>
      listEquals([for (final album in a) album.id], [for (final album in b) album.id]);

  /// Another order, or the downloaded alone, lists them again, from the start.
  @override
  void didUpdateWidget(AlbumsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.order != oldWidget.order || widget.shown != oldWidget.shown) {
      _albums.clear();
      _done = false;
      _error = null;
      scheduleMicrotask(() => _load(over: true)); // out of the build
    }
  }

  /// Asks for the next page, of [size] albums; [over], for the first again, which replaces the albums when it comes. With
  /// one on its way already, that one.
  Future<void> _load({bool over = false, int size = _pageSize}) {
    if (!over && _loading) {
      return _page ?? Future.value();
    }

    return _page = _loadPage(over: over, size: size);
  }

  Future<void> _loadPage({required bool over, required int size}) async {
    if (!mounted || (!over && (_done || _error != null))) {
      return;
    }

    final generation = over ? ++_generation : _generation;

    // The downloaded, all at once: they are on the device.
    if (widget.shown == AlbumsShown.downloaded) {
      setState(() {
        _albums
          ..clear()
          ..addAll(_downloadedAlbums);
        _done = true;
        _loading = false;
        _error = null;
      });
      return;
    }

    // The favorites, all at once, as the server has them now; as they were, where it can't say and they came before.
    if (widget.shown == AlbumsShown.favorites) {
      await _loadFavorites(generation);
      return;
    }

    final api = ServicesScope.of(context).api;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final offset = over ? 0 : _albums.length;
      final page = await switch (widget.genre) {
        null => api.albums(order: widget.order, size: size, offset: offset),
        final genre => api.genreAlbums(genre.id, size: size, offset: offset),
      };

      if (!mounted || generation != _generation) {
        return;
      }

      setState(() {
        if (over) {
          _albums.clear();
        }

        _albums.addAll(page);
        _done = page.length < size;
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

  /// Loads the favorites, and shows their albums, unless another start over, after the [generation]th, came first.
  Future<void> _loadFavorites(int generation) async {
    final favorites = ServicesScope.of(context).favorites;

    setState(() {
      _loading = true;
      _error = null;
    });

    Object? error;

    try {
      await favorites.load();
    } on Object catch (e) {
      error = e;
    }

    if (!mounted || generation != _generation) {
      return;
    }

    setState(() {
      if (favorites.loaded) {
        _albums
          ..clear()
          ..addAll(favorites.albums);
      } else {
        _error = error;
      }

      _done = true;
      _loading = false;
    });
  }

  void _retry() {
    _error = null; // which keeps _load from asking by itself
    _load();
  }

  /// Whether the albums are by name, which a letter jumps through: the library's in that order, or a genre's.
  bool get _byName => widget.genre != null || (widget.shown == AlbumsShown.library && widget.order == AlbumOrder.name);

  /// Scrolls to the albums listed under [letter], or, where there are none, the next letter's, once the pages up to them
  /// have come, asked for in turn; past the last letter there is, to the last album. The focus stays on the letter.
  Future<void> _jumpTo(String letter) async {
    final jump = ++_jumps;

    int? start;

    while (mounted && jump == _jumps) {
      start = letterStart([for (final album in _albums) letterOf(album.name)], letter);

      if (start != null || _done || _error != null) {
        break;
      }

      await _load(size: _jumpPageSize);
    }

    // A page that didn't come leaves the grid where it is, its end saying so.
    if (!mounted || jump != _jumps || _albums.isEmpty || (start == null && !_done)) {
      return;
    }

    final index = start ?? _albums.length - 1;

    // Once the grid has the albums that came.
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToGridChild(_grid, index));
    WidgetsBinding.instance.scheduleFrame();
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
    final onShown = widget.onShown;

    Widget chip(AlbumsShown shown, String label) => ChoiceChip(
      label: Text(label),
      selected: widget.shown == shown,
      onSelected: (_) => onShown!(shown),
      mouseCursor: WidgetStateMouseCursor.clickable,
    );

    // The chips stay at the top, also while another order's albums come. Their line takes the whole width, the chips
    // starting at its left, lined up with the albums.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderChips(
          widget.shown == AlbumsShown.library ? widget.order : null,
          orders: _orders,
          label: (order) => order.label(strings),
          onOrder: onOrder,
          more: [
            if (onShown != null) ...[
              chip(AlbumsShown.favorites, strings.favorites),
              if (_downloads != null) chip(AlbumsShown.downloaded, strings.downloadedAlbums),
            ],
          ],
        ),
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

    final grid = NotificationListener<Notification>(
      onNotification: _scrolled,
      child: RefreshIndicator(
        onRefresh: () => _load(over: true),
        child: AlbumGrid(
          _albums,
          gridKey: _grid,
          header: widget.header,
          footer: error != null
              ? _Retry(strings.couldNotListMoreAlbums('$error'), onRetry: _retry)
              : _loading
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(child: Spinner()),
                )
              : _albums.isEmpty && widget.genre == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(switch (widget.shown) {
                      AlbumsShown.library => widget.order.emptyMessage(strings),
                      AlbumsShown.downloaded => strings.nothingDownloaded,
                      AlbumsShown.favorites => strings.favoriteAlbumsEmpty,
                    }, textAlign: TextAlign.center),
                  ),
                )
              : null,
        ),
      ),
    );

    if (!_byName) {
      return grid;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: grid),
        LetterBar(onLetter: _jumpTo),
      ],
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

/// Albums as a grid of covers, under an optional [heading], between an optional [header] and [footer], under an optional
/// [bar]. Each opens its page.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid(
    this.albums, {
    this.heading,
    this.header,
    this.footer,
    this.subtitle,
    this.bar,
    this.gridKey,
    super.key,
  });

  final List<Album> albums;

  /// Over the albums, under the [header], at its left: their title, or a choice between them and others.
  final Widget? heading;

  final Widget? header;
  final Widget? footer;

  /// A sliver over the top of the rest, the first: the page's bar on a wide screen (`PageBarSliver`).
  final Widget? bar;

  /// The line under each name; the artist, by default.
  final String Function(Album album)? subtitle;

  /// The key of the grid's sliver, which a jump to a letter scrolls ([scrollToGridChild]).
  final GlobalKey? gridKey;

  /// How far a row's lines are from the next row's covers. About as far as a list's last song is from a title under
  /// it, as the most played songs on an artist's page are from their albums.
  static const _below = 36.0;

  @override
  Widget build(BuildContext context) {
    final lines = AlbumTile.linesHeight(context);
    final heading = this.heading;

    return CustomScrollView(
      slivers: [
        ?bar,
        if (header != null) SliverToBoxAdapter(child: header),
        if (heading != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Align(alignment: AlignmentDirectional.centerStart, child: heading),
            ),
          ),
        // Covers of up to 180 pixels, 16 from the edges and from one another, of which the tiles' room inside
        // (AlbumTile.padding) is part.
        SliverPadding(
          padding: const EdgeInsets.all(16 - AlbumTile.padding),
          sliver: SliverGrid.builder(
            key: gridKey,
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
        grows: true,
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
