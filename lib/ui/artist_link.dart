import 'package:flutter/material.dart';

import '../server/models.dart';
import 'artist_page.dart';
import 'text_link.dart';

/// An artist's name, a link to their page (when the server gave their id).
class ArtistLink extends StatelessWidget {
  /// An album's artist.
  ArtistLink.album(Album album, {this.style, super.key}) : name = album.artist ?? '', artistId = album.artistId;

  /// A song's artist: the first, when it has several, though the link shows them all.
  ArtistLink.song(Song song, {this.style, super.key}) : name = song.artist ?? '', artistId = song.artistId;

  final String name;
  final String? artistId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final artistId = this.artistId;
    return TextLink(
      name,
      tooltip: 'Abrir o artista',
      onTap: artistId == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArtistPage(Artist(id: artistId, name: name)),
              ),
            ),
      style: style,
    );
  }
}

/// An album's artist, a link to their page, and its year after them: "Aerosmith · 1975".
class AlbumByline extends StatelessWidget {
  const AlbumByline(this.album, {this.style, super.key});

  final Album album;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (album.artist != null) Flexible(child: ArtistLink.album(album, style: style)),
      if (album.year case final year?) Text(album.artist == null ? '$year' : ' · $year', style: style),
    ],
  );
}
