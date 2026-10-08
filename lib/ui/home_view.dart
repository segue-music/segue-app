import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import '../server/server.dart';
import '../services.dart';
import 'album_row.dart';
import 'albums_view.dart';

/// The first section: the latest released albums, the albums the user plays most and the latest added
/// to the library, each in a row that scrolls sideways, whose title opens all of them.
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
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_loaded) {
      _load();
    }
  }

  void _load() {
    final api = ServicesScope.of(context).api;
    _albums = {for (final order in _rows) order: api.albums(order: order, size: AlbumRow.maxAlbums)};
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
        child: ListView(
          // At the end, clear of the bars a phone's home has over it.
          padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
          children: [
            for (final order in _rows)
              AlbumRow(
                title: order.label(strings),
                albums: _albums[order]!,
                empty: order.emptyMessage(strings),
                onShowAll: onShowAll == null ? null : () => onShowAll(order),
              ),
          ],
        ),
      ),
    );
  }
}
