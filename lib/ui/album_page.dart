import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../server/models.dart';
import '../services.dart';
import 'artist_link.dart';
import 'cover_page.dart';
import 'current_song.dart';
import 'errors.dart';
import 'now_playing_bar.dart';
import 'spinner.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage(this.album, {super.key});

  final Album album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Future<(Album, List<Song>)>? _album;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _album ??= ServicesScope.of(context).api.album(widget.album.id);
  }

  Future<void> _play(List<Song> songs, int index) async {
    final result = await ServicesScope.of(context).connect.playSongs(songs, index);

    if (!result.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(result.error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: FutureBuilder(
        future: _album,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Não consegui abrir o álbum: ${snapshot.error}'));
          }

          final data = snapshot.data;

          if (data == null) {
            return const Center(child: Spinner());
          }

          final (album, songs) = data;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox.square(dimension: 140, child: CoverButton(album.coverArt)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(album.name, style: text.titleLarge),
                          AlbumByline(album, style: text.bodyMedium),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: songs.isEmpty ? null : () => _play(songs, 0),
                            icon: const Icon(HugeIcons.strokeRoundedPlay),
                            label: const Text('Tocar'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final (i, song) in songs.indexed)
                CurrentSong(
                  song,
                  builder: (context, current, playing) => ListTile(
                    selected: current,
                    leading: SizedBox(
                      width: 24,
                      child: playing ? const Icon(CurrentSong.icon) : Text('${i + 1}', textAlign: TextAlign.end),
                    ),
                    title: Text(song.title),
                    // The artist takes no focus: for the keyboard and the remote the song stays one stop, as an
                    // album in the grid is.
                    subtitle: song.artist == null ? null : ExcludeFocus(child: ArtistLink.song(song)),
                    trailing: Text(formatDuration(song.duration)),
                    onTap: () => _play(songs, i),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: const NowPlayingBar(),
    );
  }
}
