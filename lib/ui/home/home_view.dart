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

/// The first section: mixes of the genres and the decades the user plays most, which play as they're picked, then the
/// latest released albums, the albums the user plays most and the latest added to the library, each in a row that
/// scrolls sideways, whose title opens all of them. With the media server out of reach, the albums downloaded, the
/// latest first, alone.
class HomeView extends StatefulWidget {
  const HomeView({this.onShowAll, super.key});

  /// Shows all the albums in a row's order: what the row's title opens.
  final ValueChanged<AlbumOrder>? onShowAll;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  /// The rows' orders, from the top.
  static const _rows = [AlbumOrder.released, AlbumOrder.mostPlayed, AlbumOrder.latest];

  late Map<AlbumOrder, Future<List<Album>>> _albums;

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

  void _load() {
    final services = ServicesScope.of(context);
    _offline = !(services.reachability?.value ?? true);
    // Out of reach, the server's albums are the downloaded ones, the latest downloaded first.
    final rows = _offline ? const [AlbumOrder.latest] : _rows;
    _albums = {for (final order in rows) order: services.api.albums(order: order, size: AlbumRow.maxAlbums)};
    _mixes = _offline ? null : SuggestedMixes(services.api);
    _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final onShowAll = widget.onShowAll;
    final strings = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        setState(_load);
        // Each row shows its own failure.
        await Future.wait(_albums.values).catchError((_) => const <List<Album>>[]);
      },
      // Dragged by the mouse too, as the rows are sideways: on a computer, which drags only a finger's or a touchpad's,
      // down from the top it refreshes the rows as well.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
        // Every row built, rather than a list's, which drops those far out of sight and builds them anew as they come
        // back: a row then shows, for a moment, what it shows while it loads (the mixes nothing), of another height,
        // and the rows after it jumped. As iOS's bounce past the end dropped the mixes and brought them back, the
        // home jumped back up to its first rows.
        child: SingleChildScrollView(
          // Down from the top to refresh, also where the rows all fit.
          physics: const AlwaysScrollableScrollPhysics(),
          // At the end, clear of the bars a phone's home has over it.
          padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_mixes case final mixes?) MixRow(mixes, key: ObjectKey(mixes)),
              for (final MapEntry(key: order, value: albums) in _albums.entries)
                AlbumRow(
                  title: _offline ? strings.downloadedAlbums : order.label(strings),
                  albums: albums,
                  empty: _offline ? strings.nothingDownloaded : order.emptyMessage(strings),
                  onShowAll: onShowAll == null ? null : () => onShowAll(order),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
