import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
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
import 'release_types.dart';
import 'segmented_choice.dart';
import 'song_list_header.dart';
import 'spinner.dart';

/// An artist and their albums, newest first, under a few songs of theirs (the ones the user plays most, or the popular
/// ones: [_ArtistSongs]): their albums, then their singles and EPs, each under a title.
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
    _mostPlayed ??= api.mostPlayedSongs(widget.artist.id, size: _ArtistSongs.count);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    // On a phone, or a window as narrow (as the home counts it), the picture is beside the back arrow, where a bigger
    // one would leave the name no room.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return FutureBuilder(
      future: _artist,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          // No title: the artist's name is by their picture, which is beside the back arrow.
          appBar: PageHeader.bar(context, shown: data != null),
          body: switch (data) {
            _ when snapshot.hasError => Center(child: Text(strings.couldNotOpenArtistError('${snapshot.error}'))),
            null => const Center(child: Spinner()),
            (final artist, final albums) => AlbumGrid.sections(
              _sections(strings, albums),
              // Its year, and its type where it isn't an album: "2020 · EP".
              subtitle: (album) => [
                if (album.year case final year?) '$year',
                if (album.releaseType case final type? when type != ReleaseType.album) releaseTypeName(strings, type),
              ].join(' · '),
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 16, 16, 0),
                      child: Row(
                        children: [
                          // On a wide screen as big as an album's cover on its page, and asked of the server as
                          // that one is.
                          SizedBox.square(
                            dimension: narrow ? 140 : 220,
                            child: ClipOval(
                              child: narrow
                                  ? Cover(artist.coverArt ?? widget.artist.coverArt, icon: HugeIcons.strokeRoundedUser)
                                  : LargeCover(
                                      artist.coverArt ?? widget.artist.coverArt,
                                      size: 800,
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
                                Text(_count(strings, albums), style: text.bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _ArtistSongs(artist, mostPlayed: _mostPlayed!),
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

  /// How many of [albums] are albums, and singles and EPs, as the sections under part them: "8 álbuns · 4 singles e
  /// EPs", "8 álbuns · 1 EP", "2 singles"; "0 álbuns" with none.
  static String _count(AppLocalizations strings, List<Album> albums) {
    final singles = albums.where((album) => album.releaseType == ReleaseType.single).length;
    final eps = albums.where((album) => album.releaseType == ReleaseType.ep).length;
    final full = albums.length - singles - eps;
    final short = switch ((singles, eps)) {
      (0, 0) => null,
      (_, 0) => strings.singleCount(singles),
      (0, _) => strings.epCount(eps),
      _ => strings.singleAndEpCount(singles + eps),
    };
    return [if (full > 0 || short == null) albumCount(strings, full), ?short].join(' · ');
  }

  /// [albums], newest first, in sections: the artist's albums (with those the server says no type of), then their
  /// singles and EPs. A section of none isn't there, nor its title, even with the songs above.
  static List<AlbumSection> _sections(AppLocalizations strings, List<Album> albums) {
    const short = {ReleaseType.single, ReleaseType.ep};
    final newest = [...albums]..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    final full = [
      for (final album in newest)
        if (!short.contains(album.releaseType)) album,
    ];
    final singles = [
      for (final album in newest)
        if (short.contains(album.releaseType)) album,
    ];
    return [
      if (full.isNotEmpty) (title: strings.albums, albums: full),
      if (singles.isNotEmpty) (title: strings.singlesAndEps, albums: singles),
    ];
  }
}

/// The lists of an artist's songs their page shows: what each says of itself, as an option to pick or the title of the
/// one alone.
enum _SongRanking {
  /// The songs the user plays most.
  mostPlayed,

  /// The songs everyone plays most.
  popular;

  String label(AppLocalizations strings) => switch (this) {
    mostPlayed => strings.mostPlayedSongs,
    popular => strings.popularSongs,
  };
}

/// The artist's songs the user plays most, or the popular ones (those everyone plays most, as the server learns them),
/// the first few ([count]), numbered, picked over them where both have songs: the user's, until the others are. Each
/// plays the list from it, as an album's songs do. A list with none isn't there, nor its option, and with neither,
/// nothing is. Nothing until the user's have come, so that the popular ones, should they come first, don't give way to
/// them as they come; the popular ones that fail aren't there either, as a server that has none to give.
class _ArtistSongs extends StatefulWidget {
  const _ArtistSongs(this.artist, {required this.mostPlayed});

  /// The artist as the server gives them, whose name is the one the popular songs are asked by: a link's may be an
  /// album's artists together ("A & B").
  final Artist artist;

  final Future<List<Song>> mostPlayed;

  /// How many there are at most.
  static const count = 5;

  @override
  State<_ArtistSongs> createState() => _ArtistSongsState();
}

class _ArtistSongsState extends State<_ArtistSongs> {
  Future<List<Song>>? _popular;

  /// The list picked; none before the user picks one.
  _SongRanking? _picked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _popular ??= ServicesScope.of(context).api.popularSongs(widget.artist, size: _ArtistSongs.count);
  }

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
    future: widget.mostPlayed,
    builder: (context, mostPlayed) => FutureBuilder(
      future: _popular,
      builder: (context, popular) {
        final text = Theme.of(context).textTheme;
        final strings = AppLocalizations.of(context);

        if (mostPlayed.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        final lists = {
          if (mostPlayed.hasError || mostPlayed.requireData.isNotEmpty) _SongRanking.mostPlayed: mostPlayed,
          if (popular.data?.isNotEmpty ?? false) _SongRanking.popular: popular,
        };

        if (lists.isEmpty) {
          return const SizedBox.shrink();
        }

        final shown = lists.containsKey(_picked) ? _picked! : lists.keys.first;
        final snapshot = lists[shown]!;
        final songs = snapshot.data ?? const <Song>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lists.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: SegmentedChoice(
                  shown,
                  options: [...lists.keys],
                  label: (list) => list.label(strings),
                  onSelected: (list) => setState(() => _picked = list),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(shown.label(strings), style: text.titleLarge),
              ),
            if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(strings.couldNotListSongs('${snapshot.error}'), style: text.bodyMedium),
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
          ],
        );
      },
    ),
  );
}
