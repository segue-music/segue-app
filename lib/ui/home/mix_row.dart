import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../album/album_row.dart';
import '../album/albums_view.dart';
import '../widgets/cover.dart';
import '../widgets/errors.dart';
import '../widgets/focus_ring.dart';
import '../widgets/spinner.dart';
import '../widgets/themed_icon.dart';
import '../widgets/tile_row.dart';

/// Plays [mix], with [first] first: the songs its tile shows. Says why where it can't.
Future<void> playMix(BuildContext context, Mix mix, {List<Song> first = const []}) async {
  final services = ServicesScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);

  try {
    final songs = await mix.queue(services.api, first: first);

    if (songs.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(strings.mixEmpty)));
      return;
    }

    final result = await services.connect.playSongs(songs, 0);

    if (!result.ok) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(strings, result.error))));
    }
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(strings.couldNotPlayMix('$error'))));
  }
}

/// The home's row of mixes, each a tile that plays it at once, as tall as a row of albums. Not there, nor its title,
/// while they come, where there are none, or where the server can't say: unlike the albums', a row of suggestions.
class MixRow extends StatelessWidget {
  const MixRow(this.mixes, {super.key});

  final SuggestedMixes mixes;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: mixes.mixes,
    builder: (context, snapshot) {
      final strings = AppLocalizations.of(context);
      final suggested = snapshot.data;

      if (snapshot.hasError || suggested == null || suggested.isEmpty) {
        return const SizedBox.shrink();
      }

      return TileRow(
        title: strings.mixes,
        tileSize: AlbumRow.tileSize,
        previousLabel: strings.previousMixes,
        nextLabel: strings.nextMixes,
        tiles: [for (final mix in suggested) _MixTile(mix, mixes: mixes)],
      );
    },
  );
}

/// A mix, as a streaming service shows one: the picture of the artist of its first song, which it plays first, with
/// its name over it, and under it the artists of its first songs. It plays the mix as it's picked, a spinner in its play
/// icon's place until the songs have come.
class _MixTile extends StatefulWidget {
  const _MixTile(this.mix, {required this.mixes});

  final Mix mix;

  /// The mixes it is one of, which have its first songs and their first artist.
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
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: _play,
        child: Padding(
          padding: const EdgeInsets.all(AlbumTile.padding),
          child: FutureBuilder(
            future: widget.mixes.firstSongs(widget.mix),
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
                          _picture(songs),
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

  /// The picture of the artist of the first of [songs], or, where the server and fanart.tv have none, the cover of the
  /// song; a placeholder while the artist comes, and without songs.
  Widget _picture(List<Song> songs) {
    final placeholder = switch (widget.mix) {
      GenreMix() => HugeIcons.strokeRoundedTag01,
      DecadeMix() => HugeIcons.strokeRoundedCalendar03,
    };
    final cover = songs.firstOrNull?.coverArt;

    return FutureBuilder(
      future: widget.mixes.firstArtist(widget.mix),
      builder: (context, snapshot) => switch (snapshot) {
        AsyncSnapshot(connectionState: ConnectionState.waiting) => Cover(null, icon: placeholder),
        AsyncSnapshot(data: final artist?) => FanartPicture(
          artist,
          builder: (context, picture) => artist.coverArt == null && picture == null
              ? Cover(cover, icon: placeholder)
              : Cover(artist.coverArt, url: picture, icon: HugeIcons.strokeRoundedUser),
        ),
        _ => Cover(cover, icon: placeholder),
      },
    );
  }

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

/// A button that plays [mix], a spinner in its icon's place while its songs come.
class MixButton extends StatefulWidget {
  const MixButton(this.mix, {super.key});

  final Mix mix;

  @override
  State<MixButton> createState() => _MixButtonState();
}

class _MixButtonState extends State<MixButton> {
  /// The mix's songs are on their way.
  bool _loading = false;

  Future<void> _play() async {
    // Pressed again meanwhile, nothing: the button stays enabled, so that the focus stays on it.
    if (_loading) {
      return;
    }

    setState(() => _loading = true);
    await playMix(context, widget.mix);

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: _play,
    icon: _loading
        ? Spinner(size: 18, strokeWidth: 2, color: Theme.of(context).colorScheme.onSecondaryContainer)
        : const ThemedIcon(HugeIcons.strokeRoundedShuffle),
    label: Text(AppLocalizations.of(context).playMix),
  );
}
