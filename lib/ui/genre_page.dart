import 'package:flutter/material.dart';

import '../server/models.dart';
import 'albums_view.dart';
import 'now_playing_bar.dart';

/// A genre's albums, by name.
class GenrePage extends StatelessWidget {
  const GenrePage(this.genre, {super.key});

  final Genre genre;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(genre.name)),
    body: AlbumsView(genre: genre),
    bottomNavigationBar: const NowPlayingBar(),
  );
}
