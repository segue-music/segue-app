import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../album/album_page.dart';
import '../album/album_play_button.dart';
import '../artist/artist_link.dart';
import '../artist/artist_page.dart';
import '../song/current_song.dart';
import '../song/song_list_header.dart';
import '../song/song_menu.dart';
import '../widgets/cover.dart';
import '../widgets/errors.dart';
import '../widgets/spinner.dart';

/// What a search found: artists and albums, which open their page, and songs, which play.
class SearchResultsList extends StatelessWidget {
  const SearchResultsList(this.results, {super.key});

  final Future<SearchResults> results;

  static Future<void> _play(BuildContext context, List<Song> songs, int index) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppLocalizations.of(context);
    final result = await ServicesScope.of(context).connect.playSongs(songs, index);

    if (!result.ok) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(strings, result.error))));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: results,
    builder: (context, snapshot) {
      final strings = AppLocalizations.of(context);

      if (snapshot.hasError) {
        return Center(child: Text(strings.couldNotSearch('${snapshot.error}')));
      }

      final results = snapshot.data;

      if (results == null) {
        return const Center(child: Spinner());
      }

      final (:artists, :albums, :songs) = results;

      if (artists.isEmpty && albums.isEmpty && songs.isEmpty) {
        return Center(child: Text(strings.nothingFound));
      }

      return ListView(
        children: [
          if (artists.isNotEmpty) _Heading(strings.artists),
          for (final artist in artists)
            ListTile(
              leading: Thumbnail.artist(artist),
              // No count of their albums, as on their tile in the artists' grid (ArtistTile).
              title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist))),
            ),
          if (albums.isNotEmpty) _Heading(strings.albums),
          for (final album in albums) _AlbumResult(album),
          if (songs.isNotEmpty) _Heading(strings.songs),
          // As on the album page: the queue is the songs listed, from the one picked.
          for (final (i, song) in songs.indexed)
            CurrentSong(
              song,
              builder: (context, current, playing) => SongMenu(
                song,
                builder: (context, menu) => ListTile(
                  contentPadding: SongTrailing.tilePadding,
                  selected: current,
                  leading: Thumbnail(song.coverArt, playing: playing),
                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [song.artist, song.album].nonNulls.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: SongTrailing(song.id, song.duration, menu),
                  onTap: () => _play(context, songs, i),
                ),
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
            Positioned.fill(child: AlbumPlayButton(album, hovered: _hovered, small: true)),
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
