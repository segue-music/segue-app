import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../../server/models.dart';
import '../album/album_row.dart';
import '../album/albums_view.dart';
import '../widgets/cover.dart';
import '../widgets/focus_ring.dart';
import '../widgets/mix_button.dart';
import '../widgets/spinner.dart';
import '../widgets/themed_icon.dart';
import '../widgets/tile_row.dart';

/// The home's row of mixes, each a tile that plays it at once, as tall as a row of albums. Not there, nor its title,
/// while they come, where there are none, or where the server can't say: unlike the albums', a row of suggestions.
class MixRow extends StatelessWidget {
  const MixRow(this.mixes, {super.key});

  final SuggestedMixes mixes;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: mixes.mixes,
    initialData: mixes.keptMixes,
    builder: (context, snapshot) {
      final strings = AppLocalizations.of(context);
      final suggested = snapshot.data;

      if (snapshot.hasError || suggested == null || suggested.isEmpty) {
        return const SizedBox.shrink();
      }

      return TileRow(
        title: strings.mixes,
        tileSize: AlbumRow.tileSize(context),
        previousLabel: strings.previousMixes,
        nextLabel: strings.nextMixes,
        tiles: [for (final mix in suggested) _MixTile(mix, mixes: mixes)],
      );
    },
  );
}

/// A mix, as a streaming service shows one: the picture of one of the artists of its first songs, which it plays first,
/// with its name over it, and under it those artists. It plays the mix as it's picked, a spinner in its play icon's
/// place until the songs have come.
class _MixTile extends StatefulWidget {
  const _MixTile(this.mix, {required this.mixes});

  final RandomMix mix;

  /// The mixes it is one of, which have its first songs and the picture of one of their artists.
  final SuggestedMixes mixes;

  @override
  State<_MixTile> createState() => _MixTileState();
}

class _MixTileState extends State<_MixTile> {
  /// The mix's songs are on their way.
  bool _loading = false;

  /// How many of the first songs' artists it names, before "and more".
  static const _artistsNamed = 3;

  Future<void> _play() async {
    if (_loading) {
      return;
    }

    setState(() => _loading = true);
    final first = await widget.mixes.firstSongs(widget.mix).catchError((_) => const <Song>[]);

    if (mounted) {
      await playMix(context, widget.mix, first: first);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);

    return FocusRing(
      grows: true,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: _play,
        child: Padding(
          padding: const EdgeInsets.all(AlbumTile.padding),
          child: FutureBuilder(
            future: widget.mixes.firstSongs(widget.mix),
            initialData: widget.mixes.keptFirstSongs(widget.mix),
            builder: (context, snapshot) {
              final songs = snapshot.data ?? const <Song>[];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _picture(),
                          // A shade at the bottom, for the name over any picture.
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.4, 1],
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 8,
                            child: Text(
                              mixName(strings, widget.mix),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ),
                          Positioned(top: 8, right: 8, child: _PlayBadge(loading: _loading)),
                        ],
                      ),
                    ),
                  ),
                  // As far below as an album's name is below its cover.
                  const SizedBox(height: 6),
                  Text(_artists(strings, songs), maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The picture of the first of its first songs' artists who has one ([SuggestedMixes.picture]), over the mix's own
  /// ([_MixArt]), which shows while they are looked through, and stays where none has one.
  Widget _picture() => Stack(
    fit: StackFit.expand,
    children: [
      _MixArt(widget.mix),
      FutureBuilder(
        future: widget.mixes.picture(widget.mix),
        initialData: widget.mixes.keptPicture(widget.mix),
        builder: (context, snapshot) => switch (snapshot.data) {
          (:final artist, :final picture) => Cover(artist.coverArt, url: picture, icon: HugeIcons.strokeRoundedUser),
          null => const SizedBox.shrink(),
        },
      ),
    ],
  );

  /// The artists of [songs], each once, in the order they play: the first few, and that there are more.
  static String _artists(AppLocalizations strings, List<Song> songs) {
    final artists = {
      for (final song in songs)
        if (song.artist case final artist? when artist.isNotEmpty) artist,
    };
    final named = artists.take(_artistsNamed).join(', ');

    return artists.length > _artistsNamed ? strings.mixArtists(named) : named;
  }
}

/// A mix's own picture, where none of its artists has one: its kind's icon, big, on a gradient of the theme's colors, the
/// mixes of genres from its first container's color to its third's, and those of decades the other way. Containers',
/// under which the play badge, in the first color itself, stands out.
class _MixArt extends StatelessWidget {
  const _MixArt(this.mix);

  final RandomMix mix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, gradient) = switch (mix) {
      LibraryMix() => (HugeIcons.strokeRoundedShuffle, [colors.secondaryContainer, colors.primaryContainer]),
      GenreMix() => (HugeIcons.strokeRoundedTag01, [colors.primaryContainer, colors.tertiaryContainer]),
      DecadeMix() => (HugeIcons.strokeRoundedCalendar03, [colors.tertiaryContainer, colors.primaryContainer]),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
      ),
      // Over the middle, clear of the name at the bottom.
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: const Alignment(0, -0.3),
          child: ThemedIcon(
            icon,
            size: constraints.maxWidth * 0.36,
            color: colors.onPrimaryContainer.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// That a mix plays as it's picked, rather than opening a page as an album does: a play icon in a circle, in the
/// corner of its picture; a spinner while its songs come.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
      child: SizedBox.square(
        dimension: 32,
        child: Center(
          child: loading
              ? Spinner(size: 16, strokeWidth: 2, color: colors.onPrimary)
              : ThemedIcon(HugeIcons.strokeRoundedPlay, size: 18, color: colors.onPrimary),
        ),
      ),
    );
  }
}
