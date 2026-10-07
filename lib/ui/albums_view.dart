import 'dart:async';

import 'package:flutter/material.dart';

import '../server/models.dart';
import '../server/server.dart';
import '../services.dart';
import 'album_page.dart';
import 'album_play_button.dart';
import 'artist_link.dart';
import 'cover.dart';
import 'focus_ring.dart';
import 'spinner.dart';

/// How the app names an order of albums, and what a list in it says when it has none.
extension AlbumOrderText on AlbumOrder {
  String get label => switch (this) {
    AlbumOrder.name => 'Nome',
    AlbumOrder.released => 'Lançamentos',
    AlbumOrder.mostPlayed => 'Mais tocados',
    AlbumOrder.latest => 'Adicionados recentemente',
  };

  String get emptyMessage =>
      this == AlbumOrder.mostPlayed ? 'Os álbuns que você mais ouvir aparecem aqui.' : 'A biblioteca está vazia.';
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

    // The chips stay at the top, also while another order's albums come. Their line takes the whole width, the chips
    // starting at its left, lined up with the albums.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OrderChips(widget.order, onOrder: onOrder),
        Expanded(child: _albumsGrid()),
      ],
    );
  }

  Widget _albumsGrid() {
    final error = _error;

    if (_albums.isEmpty) {
      if (error != null) {
        return Center(child: _Retry('Não consegui listar os álbuns: $error', onRetry: _retry));
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
              ? _Retry('Não consegui listar mais álbuns: $error', onRetry: _retry)
              : _loading
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(child: Spinner()),
                )
              : _albums.isEmpty && widget.genre == null
              ? Center(child: Text(widget.order.emptyMessage))
              : null,
        ),
      ),
    );
  }
}

/// The orders the library's albums can come in, as chips in a line that scrolls sideways when it doesn't
/// fit: the one picked, and the others to pick.
class _OrderChips extends StatelessWidget {
  const _OrderChips(this.order, {required this.onOrder});

  final AlbumOrder order;
  final ValueChanged<AlbumOrder> onOrder;

  static const _orders = [AlbumOrder.name, AlbumOrder.released, AlbumOrder.mostPlayed, AlbumOrder.latest];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    // Room under them that stays as the albums scroll, whose own room above goes away with them.
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      children: [
        for (final option in _orders)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(option.label),
              selected: option == order,
              onSelected: (_) => onOrder(option),
              mouseCursor: WidgetStateMouseCursor.clickable,
            ),
          ),
      ],
    ),
  );
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
        TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
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

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      if (header != null) SliverToBoxAdapter(child: header),
      for (final (:title, :albums) in sections) ...[
        if (title != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
        // Covers of up to 180 pixels, 16 from the edges and from one another, of which the tiles' room inside
        // (AlbumTile.padding) is part.
        SliverPadding(
          padding: const EdgeInsets.all(16 - AlbumTile.padding),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180 + 2 * AlbumTile.padding,
              mainAxisSpacing: 16 - 2 * AlbumTile.padding,
              crossAxisSpacing: 16 - 2 * AlbumTile.padding,
              childAspectRatio: 0.75,
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
                const SizedBox(height: 6),
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
