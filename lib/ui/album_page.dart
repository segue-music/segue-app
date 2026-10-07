import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../releases/musicbrainz.dart';
import '../server/models.dart';
import '../server/server.dart';
import '../services.dart';
import 'artist_link.dart';
import 'cover.dart';
import 'cover_page.dart';
import 'current_song.dart';
import 'errors.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'page_header.dart';
import 'song_list_header.dart';
import 'spinner.dart';
import 'themed_icon.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage(this.album, {super.key});

  final Album album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Future<(Album, List<Song>)>? _album;

  /// The cover id of the picture of the album's artist.
  Future<String?>? _artistPicture;

  /// The album's release date and record labels, with what MusicBrainz adds to the media server's.
  Future<AlbumRelease>? _release;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServicesScope.of(context);
    final album = _album ??= services.api.album(widget.album.id);
    _artistPicture ??= _pictureOfArtist(services.api, widget.album.artistId, album);
    _release ??= _releaseOf(album, musicBrainz: services.musicBrainz);
  }

  /// [album]'s release date and record labels: the media server's, with what [musicBrainz] adds (null: nothing).
  /// None when the server fails to give the album, which the page says.
  static Future<AlbumRelease> _releaseOf(Future<(Album, List<Song>)> album, {MusicBrainz? musicBrainz}) async {
    try {
      final (found, _) = await album;

      if (musicBrainz == null) {
        return (date: found.releaseDate, labels: found.recordLabels);
      }

      return await musicBrainz.complete(found);
    } on Object {
      return (date: null, labels: const <String>[]);
    }
  }

  /// The cover id of the picture of the album's artist, [artistId] or, when the page opened without it, the one
  /// [album] names: none when it names none, or the server fails, and the picture stays a placeholder.
  static Future<String?> _pictureOfArtist(MediaServer api, String? artistId, Future<(Album, List<Song>)> album) async {
    try {
      final id = artistId ?? (await album).$1.artistId;

      if (id == null) {
        return null;
      }

      final (artist, _) = await api.artist(id);
      return artist.coverArt;
    } on Object {
      return null;
    }
  }

  Future<void> _play(List<Song> songs, int index) async {
    final result = await ServicesScope.of(context).connect.playSongs(songs, index);

    if (!result.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(result.error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    // On a phone, or a window as narrow (as the home counts it), the album's name is under its cover, and the songs
    // have no header naming their columns.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return FutureBuilder(
      future: _album,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          // No title: the album's name is by its cover, which is beside the back arrow.
          appBar: PageHeader.bar(context, shown: data != null),
          body: switch (data) {
            _ when snapshot.hasError => Center(child: Text('Não consegui abrir o álbum: ${snapshot.error}')),
            null => const Center(child: Spinner()),
            (final album, final songs) => ListView(
              children: [
                _header(album, songs, narrow: narrow),
                if (!narrow) const SongListHeader(numbered: true),
                for (var i = 0; i < songs.length; i++)
                  if (i == songs.length - 1)
                    _LastSong(_song(songs, i), album: album, release: _release!)
                  else
                    _song(songs, i),
              ],
            ),
          },
          // The songs go on behind the player bar, slightly see-through on a phone; the list, with no padding of its
          // own, takes the room MediaQuery says the bar takes at its end. In the page area the home's bars stay under
          // the page instead, with the room they take, which a bar of its own, even one showing nothing, would take
          // away.
          extendBody: true,
          bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
        );
      },
    );
  }

  /// The top of the page: the album's cover, its name and byline, and the button that plays it. On a wide screen the
  /// name is beside the cover, the button under them; on a narrow one ([narrow]) the cover is bigger, centered, and the
  /// name under it, from the page's margin as the songs are, with the button at the end of its line.
  Widget _header(Album album, List<Song> songs, {required bool narrow}) {
    final text = Theme.of(context).textTheme;
    final name = Text(album.name, style: text.titleLarge);
    final byline = _Byline(album, songs, artistPicture: _artistPicture!, style: text.bodyMedium);
    // Just the icon, its name in the tooltip, as the play button on the albums' covers.
    final play = IconButton.filled(
      tooltip: 'Tocar o álbum',
      onPressed: songs.isEmpty ? null : () => _play(songs, 0),
      icon: const ThemedIcon(HugeIcons.strokeRoundedPlay),
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            centered: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              // As wide as the room the header leaves it, less a margin, up to a phone's widest; asked of the server
              // as the player's is, which a phone's pixels need.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: AspectRatio(aspectRatio: 1, child: CoverButton(album.coverArt, size: 800)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [name, byline]),
                ),
                const SizedBox(width: 16),
                play,
              ],
            ),
          ),
        ],
      );
    }

    // How big the cover is, square.
    const size = 140.0;
    return PageHeader(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(dimension: size, child: CoverButton(album.coverArt)),
            const SizedBox(width: 16),
            // Centered on the cover, which stays at the top where a long name and its byline beside it are taller.
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: size),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name, byline, const SizedBox(height: 12), play],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The album's song at [index] in its list, which plays the album from it.
  Widget _song(List<Song> songs, int index) {
    final song = songs[index];
    return CurrentSong(
      song,
      builder: (context, current, playing) => ListTile(
        selected: current,
        leading: SizedBox(
          width: SongListHeader.numberWidth,
          child: playing ? const ThemedIcon(CurrentSong.icon) : SongNumber(index + 1),
        ),
        title: Text(song.title),
        // The artist takes no focus: for the keyboard and the remote the song stays one stop, as an album in the grid
        // is.
        subtitle: song.artist == null ? null : ExcludeFocus(child: ArtistLink.song(song)),
        trailing: SongDuration(song.duration),
        onTap: () => _play(songs, index),
      ),
    );
  }
}

/// Under the album's name: its artist, with their picture, a link to their page; its year; how many songs it has and
/// how long they last. One paragraph, which a narrow screen wraps.
class _Byline extends StatelessWidget {
  const _Byline(this.album, this.songs, {required this.artistPicture, this.style});

  final Album album;
  final List<Song> songs;

  /// The cover id of the artist's picture.
  final Future<String?> artistPicture;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final details = [if (album.year case final year?) '$year', if (songs.isNotEmpty) _songsLength(songs)].join(' · ');
    return Text.rich(
      TextSpan(
        children: [
          if (album.artist != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: ArtistLink.album(
                album,
                style: style,
                picture: album.artistId == null ? null : _ArtistPicture(artistPicture),
              ),
            ),
            if (details.isNotEmpty) const TextSpan(text: ' · '),
          ],
          TextSpan(text: details),
        ],
      ),
      style: style,
    );
  }
}

/// How many songs there are, and how long they last together, where each says: "9 faixas, 37 min".
String _songsLength(List<Song> songs) {
  final count = songs.length == 1 ? '1 faixa' : '${songs.length} faixas';

  if (songs.any((song) => song.duration == null)) {
    return count;
  }

  final length = songs.fold(Duration.zero, (sum, song) => sum + song.duration!);
  final (hours, minutes) = (length.inHours, length.inMinutes % 60);
  final time = switch ((hours, minutes)) {
    (0, 0) => '${length.inSeconds} s',
    (0, _) => '$minutes min',
    (_, 0) => '$hours h',
    _ => '$hours h $minutes min',
  };
  return '$count, $time';
}

/// The picture of the album's artist, small and round, before their name: a person until it comes, and where the
/// server has none.
class _ArtistPicture extends StatelessWidget {
  const _ArtistPicture(this.coverArt);

  /// Its cover id.
  final Future<String?> coverArt;

  /// How big it is, square.
  static const size = 24.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipOval(
      child: IconTheme.merge(
        data: const IconThemeData(size: 16),
        child: FutureBuilder(
          future: coverArt,
          builder: (context, snapshot) => Cover(snapshot.data, size: 96, icon: HugeIcons.strokeRoundedUser),
        ),
      ),
    ),
  );
}

/// The album's last song, with what is known of its release under it, ending the list: its date, and the labels that
/// put it out. The media server's first, then with what MusicBrainz adds, as it comes. The keyboard and the remote
/// stop at the songs only, so as the focus comes to the last one the list scrolls on to show these too.
class _LastSong extends StatelessWidget {
  const _LastSong(this.song, {required this.album, required this.release});

  final Widget song;
  final Album album;
  final Future<AlbumRelease> release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return FutureBuilder(
      future: release,
      initialData: (date: album.releaseDate, labels: album.recordLabels),
      builder: (context, snapshot) {
        final (:date, :labels) = snapshot.requireData;
        final lines = [if (date != null) _formatDate(date), if (labels.isNotEmpty) labels.join(', ')];
        // The same widgets around the song, with or without the lines under it: rebuilt, it would lose the focus.
        return Focus(
          canRequestFocus: false,
          onFocusChange: (focused) {
            if (focused) {
              Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              song,
              if (lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final line in lines) Text(line, style: style)],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

const _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// [date] in Portuguese, as precisely as it is known: "8 de abril de 1975", "abril de 1975", "1975".
String _formatDate(ReleaseDate date) {
  final ReleaseDate(:year, :month, :day) = date;

  if (month == null || month > 12) {
    return '$year';
  }

  final monthAndYear = '${_months[month - 1]} de $year';
  return switch (day) {
    null => monthAndYear,
    1 => '1º de $monthAndYear',
    _ => '$day de $monthAndYear',
  };
}
