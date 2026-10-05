import 'package:flutter/material.dart';

import '../server/models.dart';
import '../server/server.dart';
import '../services.dart';
import 'album_row.dart';

/// The first section: the latest released albums, the albums the user plays most and the latest added
/// to the library, each in a row that scrolls sideways.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late Future<List<Album>> _released;
  late Future<List<Album>> _mostPlayed;
  late Future<List<Album>> _latest;
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
    _released = api.albums(order: AlbumOrder.released, size: AlbumRow.maxAlbums);
    _mostPlayed = api.mostPlayedAlbums(size: AlbumRow.maxAlbums);
    _latest = api.albums(order: AlbumOrder.latest, size: AlbumRow.maxAlbums);
    _loaded = true;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {
      setState(_load);
      // Each row shows its own failure.
      await Future.wait([_released, _mostPlayed, _latest]).catchError((_) => const <List<Album>>[]);
    },
    child: ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        AlbumRow(title: 'Lançamentos', albums: _released, empty: 'A biblioteca está vazia.'),
        AlbumRow(title: 'Mais tocados', albums: _mostPlayed, empty: 'Os álbuns que você mais ouvir aparecem aqui.'),
        AlbumRow(title: 'Adicionados recentemente', albums: _latest, empty: 'A biblioteca está vazia.'),
      ],
    ),
  );
}
