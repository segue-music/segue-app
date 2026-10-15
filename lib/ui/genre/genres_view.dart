import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../artist/artists_view.dart';
import '../widgets/spinner.dart';
import 'genre_page.dart';
import '../widgets/errors.dart';

/// The library's genres, by name, each with how many albums it has, under those the user listens to
/// most. Those with no albums, which a server may list for their songs alone, are left out: they would
/// open an empty page.
class GenresView extends StatefulWidget {
  const GenresView({super.key});

  @override
  State<GenresView> createState() => _GenresViewState();
}

/// Every genre, and those the user listens to most.
typedef _Genres = ({List<Genre> all, List<Genre> mostPlayed});

class _GenresViewState extends State<GenresView> {
  Future<_Genres>? _genres;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _genres ??= _load();
  }

  Future<_Genres> _load() async {
    final api = ServicesScope.of(context).api;
    // A shortcut, which the list goes without when the server fails to give it.
    final mostPlayed = api.mostPlayedGenres().catchError((_) => const <Genre>[]);
    final genres = await api.genres();

    return (
      all: [
        for (final genre in genres)
          if (genre.albumCount != 0) genre,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      mostPlayed: await mostPlayed,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _genres,
    builder: (context, snapshot) {
      final strings = AppLocalizations.of(context);

      if (snapshot.hasError) {
        return Center(child: Text(strings.couldNotListGenres(describeFailure(strings, snapshot.error))));
      }

      final genres = snapshot.data;

      if (genres == null) {
        return const Center(child: Spinner());
      }

      final (:all, :mostPlayed) = genres;
      // Before anything has played, the list alone.
      final header = mostPlayed.isEmpty ? 0 : 1;

      return RefreshIndicator(
        onRefresh: () async {
          final reload = _load();

          // In braces: setState takes no callback that returns a future, as the assignment would.
          setState(() {
            _genres = reload;
          });
          await reload;
        },
        child: ListView.builder(
          // At the end, clear of the bars a phone's home has over it.
          padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom),
          itemCount: header + all.length,
          itemBuilder: (context, i) {
            if (i < header) {
              return _MostPlayed(mostPlayed);
            }

            final genre = all[i - header];

            return ListTile(
              title: Text(genre.name),
              subtitle: genre.albumCount == null ? null : Text(albumCount(strings, genre.albumCount)),
              onTap: () => _open(context, genre),
            );
          },
        ),
      );
    },
  );
}

/// The genres the user listens to most, the most first, as buttons; then the heading of the list of
/// them all.
class _MostPlayed extends StatelessWidget {
  const _MostPlayed(this.genres);

  final List<Genre> genres;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.mostPlayed, style: text.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final genre in genres)
                FilledButton.tonal(onPressed: () => _open(context, genre), child: Text(genre.name)),
            ],
          ),
          const SizedBox(height: 24),
          Text(strings.allGenres, style: text.titleLarge),
        ],
      ),
    );
  }
}

void _open(BuildContext context, Genre genre) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GenrePage(genre)));
