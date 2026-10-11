import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../album/album_row.dart';
import '../album/albums_view.dart';
import '../app/page_area.dart';
import '../home/mix_row.dart';
import '../player/now_playing_bar.dart';

/// A genre's albums, by name, under a button that plays a mix of its songs and a row of the albums the user plays most:
/// once any has played.
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
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
        automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
        title: Text(widget.genre.name),
      ),
      body: AlbumsView(
        genre: widget.genre,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: MixButton(GenreMix(widget.genre))),
            FutureBuilder(
              future: mostPlayed,
              builder: (context, snapshot) {
                // Nothing of the genre has played: its albums alone.
                if (snapshot.data?.isEmpty ?? false) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AlbumRow(title: strings.mostPlayed, albums: mostPlayed),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: Text(strings.albums, style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      // The albums go on behind the player bar, slightly see-through on a phone; the grid ends with the room
      // MediaQuery says the bar takes. In the page area the home's bars stay under the page instead, with the room they
      // take, which a bar of its own, even one showing nothing, would take away.
      extendBody: true,
      bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
    );
  }
}
