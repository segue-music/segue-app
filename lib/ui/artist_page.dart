import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../server/models.dart';
import '../services.dart';
import 'albums_view.dart';
import 'artists_view.dart';
import 'cover.dart';
import 'current_song.dart';
import 'errors.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'page_header.dart';
import 'song_list_header.dart';
import 'spinner.dart';

/// An artist and their albums, newest first, under the songs of theirs the user plays most: once any
/// has played.
class ArtistPage extends StatefulWidget {
  const ArtistPage(this.artist, {super.key});

  final Artist artist;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  Future<(Artist, List<Album>)>? _artist;
  Future<List<Song>>? _mostPlayed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ServicesScope.of(context).api;
    _artist ??= api.artist(widget.artist.id);
    _mostPlayed ??= api.mostPlayedSongs(widget.artist.id, size: _MostPlayedSongs.count);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder(
      future: _artist,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          // No title: the artist's name is by their picture, which is beside the back arrow.
          appBar: PageHeader.bar(context, shown: data != null),
          body: switch (data) {
            _ when snapshot.hasError => Center(child: Text('Não consegui abrir o artista: ${snapshot.error}')),
            null => const Center(child: Spinner()),
            (final artist, final albums) => AlbumGrid(
              // Newest first.
              [...albums]..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0)),
              subtitle: (album) => album.year?.toString() ?? '',
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 16, 16, 0),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 140,
                            child: ClipOval(
                              child: Cover(
                                artist.coverArt ?? widget.artist.coverArt,
                                icon: HugeIcons.strokeRoundedUser,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(artist.name, style: text.titleLarge),
                                Text(albumCount(artist.albumCount ?? albums.length), style: text.bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _MostPlayedSongs(_mostPlayed!),
                ],
              ),
            ),
          },
          // The albums go on behind the player bar, slightly see-through on a phone; the grid ends with the room
          // MediaQuery says the bar takes. In the page area the home's bars stay under the page instead, with the room
          // they take, which a bar of its own, even one showing nothing, would take away.
          extendBody: true,
          bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
        );
      },
    );
  }
}

/// The artist's songs the user plays most, the first few ([count]), numbered, over a title for the albums under them.
/// Each plays the list from it, as an album's songs do. Nothing while they come, nor before any has played: the albums
/// alone.
class _MostPlayedSongs extends StatelessWidget {
  const _MostPlayedSongs(this.songs);

  final Future<List<Song>> songs;

  /// How many there are at most.
  static const count = 5;

  static Future<void> _play(BuildContext context, List<Song> songs, int index) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ServicesScope.of(context).connect.playSongs(songs, index);

    if (!result.ok) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(result.error))));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: songs,
    builder: (context, snapshot) {
      final text = Theme.of(context).textTheme;
      final songs = snapshot.data ?? const <Song>[];

      if (songs.isEmpty && !snapshot.hasError) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Mais tocadas', style: text.titleLarge),
          ),
          if (snapshot.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Não consegui listar as músicas: ${snapshot.error}', style: text.bodyMedium),
            ),
          for (final (i, song) in songs.indexed)
            CurrentSong(
              song,
              builder: (context, current, playing) => ListTile(
                selected: current,
                // Its place among them, then its cover.
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: SongListHeader.numberWidth, child: SongNumber(i + 1)),
                    const SizedBox(width: 16),
                    Thumbnail(song.coverArt, playing: playing),
                  ],
                ),
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: song.album == null ? null : Text(song.album!, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: SongDuration(song.duration),
                onTap: () => _play(context, songs, i),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text('Álbuns', style: text.titleLarge),
          ),
        ],
      );
    },
  );
}
