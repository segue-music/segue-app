import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../../server/models.dart';
import '../../server/server.dart';
import '../../services.dart';
import '../album/album_row.dart';
import '../album/albums_view.dart';
import 'mix_row.dart';
import 'recent_albums.dart';

/// The first section, in the order the user turns to them: the albums played last, to go back to one, as small tiles
/// ([RecentAlbums]); mixes of the genres and the decades the user plays most, which play as they're picked; then the
/// latest added to the library, what is new there, the latest released and the albums the user plays most, which change
/// least, each in a row that scrolls sideways. Each title opens all of them. As the app opens, what it showed the time before, at once, while
/// they come ([Services.homeCache]). With the media server out of reach, the albums downloaded, the latest first,
/// alone.
class HomeView extends StatefulWidget {
  const HomeView({this.onShowAll, super.key});

  /// Shows all the albums in a row's order: what the row's title opens.
  final ValueChanged<AlbumOrder>? onShowAll;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  /// The rows' orders, from the top.
  static const _rows = [AlbumOrder.recentlyPlayed, AlbumOrder.latest, AlbumOrder.released, AlbumOrder.mostPlayed];

  late Map<AlbumOrder, Future<List<Album>>> _albums;

  /// What each row shows until its albums come: those it showed the time before, where they were kept.
  var _keptAlbums = const <AlbumOrder, List<Album>>{};

  /// None out of reach: a mix's songs are the server's to pick.
  SuggestedMixes? _mixes;

  bool _loaded = false;

  /// Whether the media server was out of reach as the rows loaded.
  bool _offline = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_loaded) {
      _load();
    }
  }

  /// Lists the rows' albums, and picks the mixes: as the home opens, those it showed the time before, at once, or,
  /// [again] (pulled down), new ones.
  void _load({bool again = false}) {
    final services = ServicesScope.of(context);
    _offline = !(services.reachability?.value ?? true);
    // Out of reach, the server's albums are the downloaded ones, the latest downloaded first, which aren't kept.
    final rows = _offline ? const [AlbumOrder.latest] : _rows;
    final cache = _offline ? null : services.homeCache;
    _keptAlbums = again || cache == null ? const {} : {for (final order in rows) order: ?cache.albums(order)};
    _albums = {
      for (final order in rows)
        order: switch (services.api.albums(
          order: order,
          size: order == AlbumOrder.recentlyPlayed ? RecentAlbums.max : AlbumRow.maxAlbums,
        )) {
          final listed when cache != null => cache.keepAlbums(order, listed, shown: _keptAlbums[order]),
          final listed => listed,
        },
    };
    _mixes = switch (cache) {
      _ when _offline => null,
      final cache? when !again => cache.mixes(services.api, fanartTv: services.fanartTv),
      _ => SuggestedMixes(services.api, fanartTv: services.fanartTv),
    };
    _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final onShowAll = widget.onShowAll;
    final strings = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _load(again: true));
        // Each row shows its own failure.
        await Future.wait(_albums.values).catchError((_) => const <List<Album>>[]);
      },
      // Dragged by the mouse too, as the rows are sideways: on a computer, which drags only a finger's or a touchpad's,
      // down from the top it refreshes the rows as well.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
        // Not a SingleChildScrollView, which takes the position back into range whenever it lays its rows out again: on
        // iOS the refresh starts as the home still bounces back from the pull, the mixes go meanwhile, and the bounce,
        // at its speed, went on down the home, which stayed there as the mixes came back above it.
        child: CustomScrollView(
          // Down from the top to refresh, also where the rows all fit.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              // At the end, clear of the bars a phone's home has over it.
              padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
              // Every row built, in one box, rather than a list's, which drops those far out of sight and builds them
              // anew as they come back: a row then shows, for a moment, what it shows while it loads (the mixes
              // nothing), of another height, and the rows after it jumped. As iOS's bounce past the end dropped the
              // mixes and brought them back, the home jumped back up to its first rows.
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_albums[AlbumOrder.recentlyPlayed] case final albums?)
                      RecentAlbums(
                        albums: albums,
                        initialAlbums: _keptAlbums[AlbumOrder.recentlyPlayed],
                        onShowAll: onShowAll == null ? null : () => onShowAll(AlbumOrder.recentlyPlayed),
                      ),
                    if (_mixes case final mixes?) MixRow(mixes, key: ObjectKey(mixes)),
                    for (final MapEntry(key: order, value: albums) in _albums.entries)
                      if (order != AlbumOrder.recentlyPlayed)
                        AlbumRow(
                          title: _offline ? strings.downloadedAlbums : order.label(strings),
                          albums: albums,
                          initialAlbums: _keptAlbums[order],
                          empty: _offline ? strings.nothingDownloaded : order.emptyMessage(strings),
                          onShowAll: onShowAll == null ? null : () => onShowAll(order),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
