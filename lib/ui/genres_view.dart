import 'package:flutter/material.dart';

import '../server/models.dart';
import '../services.dart';
import 'artists_view.dart';
import 'genre_page.dart';
import 'spinner.dart';

/// The library's genres, by name, each with how many albums it has. Those with none, which a server
/// may list for their songs alone, are left out: they would open an empty page.
class GenresView extends StatefulWidget {
  const GenresView({super.key});

  @override
  State<GenresView> createState() => _GenresViewState();
}

class _GenresViewState extends State<GenresView> {
  Future<List<Genre>>? _genres;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _genres ??= _load();
  }

  Future<List<Genre>> _load() async {
    final genres = await ServicesScope.of(context).api.genres();
    return [
      for (final genre in genres)
        if (genre.albumCount != 0) genre,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _genres,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('Não consegui listar os gêneros: ${snapshot.error}'));
      }

      final genres = snapshot.data;

      if (genres == null) {
        return const Center(child: Spinner());
      }

      return RefreshIndicator(
        onRefresh: () async {
          final reload = _load();
          setState(() => _genres = reload);
          await reload;
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: genres.length,
          itemBuilder: (context, i) {
            final genre = genres[i];
            return ListTile(
              title: Text(genre.name),
              subtitle: genre.albumCount == null ? null : Text(albumCount(genre.albumCount)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GenrePage(genre))),
            );
          },
        ),
      );
    },
  );
}
