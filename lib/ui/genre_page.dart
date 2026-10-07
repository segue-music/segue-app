import 'package:flutter/material.dart';

import '../server/models.dart';
import '../services.dart';
import 'album_row.dart';
import 'albums_view.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';

/// A genre's albums, by name, under a row of those the user plays most: once any has played.
class GenrePage extends StatefulWidget {
  const GenrePage(this.genre, {super.key});

  final Genre genre;

  @override
  State<GenrePage> createState() => _GenrePageState();
}

class _GenrePageState extends State<GenrePage> {
  Future<List<Album>>? _mostPlayed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mostPlayed ??= ServicesScope.of(context).api.mostPlayedAlbums(size: AlbumRow.maxAlbums, genre: widget.genre.id);
  }

  @override
  Widget build(BuildContext context) {
    final mostPlayed = _mostPlayed!;
    return Scaffold(
      appBar: AppBar(
        // In the page area, the top bar's arrow goes back: no arrow of its own.
        automaticallyImplyLeading: !PageArea.holds(context),
        title: Text(widget.genre.name),
      ),
      body: AlbumsView(
        genre: widget.genre,
        header: FutureBuilder(
          future: mostPlayed,
          builder: (context, snapshot) {
            // Nothing of the genre has played: its albums alone.
            if (snapshot.data?.isEmpty ?? false) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AlbumRow(title: 'Mais tocados', albums: mostPlayed),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Text('Álbuns', style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            );
          },
        ),
      ),
      // The albums go on behind the player bar, slightly see-through on a phone; the grid ends with the room
      // MediaQuery says the bar takes.
      extendBody: true,
      bottomNavigationBar: const NowPlayingBar(),
    );
  }
}
