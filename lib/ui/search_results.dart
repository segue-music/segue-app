import 'package:flutter/material.dart';

import '../server/models.dart';
import '../services.dart';
import 'album_artist_link.dart';
import 'album_page.dart';
import 'album_play_button.dart';
import 'artist_page.dart';
import 'artists_view.dart';
import 'cover.dart';
import 'current_song.dart';
import 'errors.dart';
import 'now_playing_bar.dart';
import 'spinner.dart';

/// What a search found: artists and albums, which open their page, and songs, which play.
class SearchResultsList extends StatelessWidget {
  const SearchResultsList(this.results, {super.key});

  final Future<SearchResults> results;

  static Future<void> _play(BuildContext context, List<Song> songs, int index) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ServicesScope.of(context).connect.playSongs(songs, index);

    if (!result.ok) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(result.error))));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: results,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('Não consegui buscar: ${snapshot.error}'));
      }

      final results = snapshot.data;

      if (results == null) {
        return const Center(child: Spinner());
      }

      final (:artists, :albums, :songs) = results;

      if (artists.isEmpty && albums.isEmpty && songs.isEmpty) {
        return const Center(child: Text('Nada encontrado.'));
      }

      return ListView(
        children: [
          if (artists.isNotEmpty) const _Heading('Artistas'),
          for (final artist in artists)
            ListTile(
              leading: Thumbnail(artist.coverArt, round: true),
              title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(albumCount(artist.albumCount)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist))),
            ),
          if (albums.isNotEmpty) const _Heading('Álbuns'),
          for (final album in albums) _AlbumResult(album),
          if (songs.isNotEmpty) const _Heading('Músicas'),
          // As on the album page: the queue is the songs listed, from the one picked.
          for (final (i, song) in songs.indexed)
            CurrentSong(
              song,
              builder: (context, current, playing) => ListTile(
                selected: current,
                leading: Thumbnail(song.coverArt, playing: playing),
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [song.artist, song.album].nonNulls.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(formatDuration(song.duration)),
                onTap: () => _play(context, songs, i),
              ),
            ),
        ],
      );
    },
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// An album the search found, which opens its page, but for the button over its thumbnail, which
/// plays it.
class _AlbumResult extends StatefulWidget {
  const _AlbumResult(this.album);

  final Album album;

  @override
  State<_AlbumResult> createState() => _AlbumResultState();
}

class _AlbumResultState extends State<_AlbumResult> {
  /// The pointer is over the album: its play button shows.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ListTile(
        leading: Stack(
          alignment: Alignment.center,
          children: [
            Thumbnail(album.coverArt),
            AlbumPlayButton(album, hovered: _hovered, small: true),
          ],
        ),
        title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        // The artist takes no focus, as in the album grid: the album's page links them too.
        subtitle: ExcludeFocus(child: AlbumByline(album)),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlbumPage(album))),
      ),
    );
  }
}
