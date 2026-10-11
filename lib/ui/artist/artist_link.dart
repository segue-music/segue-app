import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../widgets/text_link.dart';
import 'artist_page.dart';

/// An artist's name, a link to their page (when the server gave their id).
class ArtistLink extends StatelessWidget {
  /// An album's artist, with [picture] before their name.
  ArtistLink.album(Album album, {this.style, this.picture, super.key})
    : name = album.artist ?? '',
      artistId = album.artistId;

  final String name;
  final String? artistId;
  final TextStyle? style;

  /// Their picture, before their name, in the link.
  final Widget? picture;

  @override
  Widget build(BuildContext context) {
    final artistId = this.artistId;
    return TextLink(
      name,
      tooltip: AppLocalizations.of(context).openArtist,
      onTap: artistId == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArtistPage(Artist(id: artistId, name: name)),
              ),
            ),
      style: style,
      leading: picture,
    );
  }
}

/// What goes between a song's artists, as between an album's artist, year and songs.
const _between = ' · ';

/// A song's artists, as [ArtistLinks.song] writes them, in plain text: "Run-DMC · Aerosmith".
String artistNames(Song song) =>
    song.artists.isEmpty ? song.artist ?? '' : song.artists.map((artist) => artist.name).join(_between);

/// A song's artists, each a link to their page, apart as an album's artist, year and songs are: "Run-DMC · Aerosmith",
/// whatever the media server puts between them in the song's artist ("Run-DMC; Aerosmith", "Santana feat. Rob
/// Thomas"). What goes between them belongs to what holds them, as the rest of a [TextLink]'s line does. In one line:
/// where they don't fit, the one the room runs out in ends in an ellipsis, as one text would, and those after it are
/// left out.
class ArtistLinks extends StatelessWidget {
  /// A song's artists, whose pages open over the current one.
  ArtistLinks.song(Song song, {this.style, super.key})
    : text = song.artist ?? '',
      artists = song.artists,
      onOpen = null,
      onTapUnknown = null,
      textAlign = null;

  const ArtistLinks(
    this.text,
    this.artists, {
    required this.onOpen,
    this.onTapUnknown,
    this.style,
    this.textAlign,
    super.key,
  });

  /// The song's artist, as the media server writes it, which shows where [artists] is empty.
  final String text;

  final List<Artist> artists;

  /// What a link does: opens the page of its artist. Null opens it over the current one.
  final void Function(Artist artist)? onOpen;

  /// What a tap on the whole of it does where [artists] is empty, as while who they are isn't known yet; null leaves
  /// it plain text.
  final VoidCallback? onTapUnknown;

  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final open =
        onOpen ?? (artist) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist)));
    final pieces = <(String, Artist?)>[
      if (artists.isEmpty) (text, null),
      for (final (i, artist) in artists.indexed) ...[if (i > 0) (_between, null), (artist.name, artist)],
    ];

    // Every piece a TextLink, also what has nowhere to go: from one song to the next, a link keeps its place, and with
    // it the focus. Each starts where the one before it ends: the line is aligned as a whole, since one centered on its
    // own would leave out the space at its end, putting the dot of " · " off its middle.
    Widget link((String, Artist?) piece) => TextLink(
      piece.$1,
      tooltip: strings.openArtist,
      onTap: switch (piece.$2) {
        final artist? => () => open(artist),
        null => artists.isEmpty ? onTapUnknown : null,
      },
      style: style,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // As a Text takes it, to find out how wide each piece is.
        final textStyle = DefaultTextStyle.of(context).style
            .merge(style)
            .merge(MediaQuery.boldTextOf(context) ? const TextStyle(fontWeight: FontWeight.bold) : null);
        final shown = <Widget>[];
        var width = 0.0;

        for (final piece in pieces) {
          width += _widthOf(piece.$1, textStyle, MediaQuery.textScalerOf(context), Directionality.of(context));

          if (width > constraints.maxWidth) {
            shown.add(Flexible(child: link(piece)));
            break;
          }

          shown.add(link(piece));
        }

        return Align(
          alignment: textAlign == TextAlign.center ? Alignment.center : AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: Row(mainAxisSize: MainAxisSize.min, children: shown),
        );
      },
    );
  }
}

/// How wide [text] is in one line, in [style] at [scaler]'s size.
double _widthOf(String text, TextStyle style, TextScaler scaler, TextDirection direction) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
    maxLines: 1,
  )..layout();

  try {
    return painter.width;
  } finally {
    painter.dispose();
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
