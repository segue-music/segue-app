import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../server/models.dart';
import '../services.dart';
import 'artist_link.dart';
import 'cover_page.dart';
import 'current_song.dart';
import 'errors.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
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
      // No title: the album's name is by its cover. In the page area, where the top bar's arrow goes back, that leaves
      // nothing for a bar of its own; elsewhere (on a phone) it has the back arrow.
      appBar: PageArea.holds(context) ? null : AppBar(),
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
                            icon: const ThemedIcon(HugeIcons.strokeRoundedPlay),
                            label: const Text('Tocar'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SongListHeader(numbered: true),
              for (var i = 0; i < songs.length; i++)
                if (i == songs.length - 1) _LastSong(_song(songs, i), album: album) else _song(songs, i),
            ],
          );
        },
      ),
      bottomNavigationBar: const NowPlayingBar(),
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

/// The album's last song, with what is known of its release under it, ending the list: its date, and the labels that
/// put it out. The keyboard and the remote stop at the songs only, so as the focus comes to the last one the list
/// scrolls on to show these too.
class _LastSong extends StatelessWidget {
  const _LastSong(this.song, {required this.album});

  final Widget song;
  final Album album;

  @override
  Widget build(BuildContext context) {
    final lines = [
      if (album.releaseDate case final date?) _formatDate(date),
      if (album.recordLabels.isNotEmpty) album.recordLabels.join(', '),
    ];

    if (lines.isEmpty) {
      return song;
    }

    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
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
