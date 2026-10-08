import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import 'cover.dart';
import 'player_controls.dart';
import 'song_menu.dart';
import 'themed_icon.dart';

/// The text of a list of songs' first and last columns, a song's number and its duration: at the size of the artist's
/// line beside them, which a list tile's own, the theme's smallest, is well under, in the color the tile gives them
/// (the current song's, when it is).
TextStyle? _columnStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(color: DefaultTextStyle.of(context).style.color);

/// A song's number in its list, in the first column: on its album, under the header's "#", or its place among an
/// artist's most played.
class SongNumber extends StatelessWidget {
  const SongNumber(this.number, {super.key});

  final int number;

  @override
  Widget build(BuildContext context) => Text('$number', textAlign: TextAlign.end, style: _columnStyle(context));
}

/// A song's duration, in the last column of a list of songs, under the header's clock.
class SongDuration extends StatelessWidget {
  const SongDuration(this.duration, {super.key});

  final Duration? duration;

  @override
  Widget build(BuildContext context) => Text(formatDuration(duration), style: _columnStyle(context));
}

/// The header of a list of songs, naming its columns over them: their numbers ("#") or covers (unnamed), their
/// title, and their duration, as a clock. A list tile as they are, so that its columns line up with theirs; disabled,
/// so that neither the pointer, the keyboard nor a remote stops at it.
class SongListHeader extends StatelessWidget {
  const SongListHeader({this.numbered = false, this.menus = false, super.key});

  /// Whether the songs are numbered, as an album's are, rather than shown with their covers, as the queue's.
  final bool numbered;

  /// Whether each song has its menu's button after its duration ([SongMenu]), which the header leaves room for.
  final bool menus;

  /// How wide a numbered song's number is.
  static const numberWidth = 24.0;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: muted);
    final strings = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          enabled: false,
          minTileHeight: 36,
          leading: SizedBox(
            width: numbered ? numberWidth : Thumbnail.size,
            child: numbered ? Text('#', style: style, textAlign: TextAlign.end) : null,
          ),
          title: Text(strings.songTitle, style: style),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: strings.songDuration,
                child: ThemedIcon(HugeIcons.strokeRoundedClock01, size: 18, color: muted),
              ),
              if (menus) const SizedBox(width: SongTrailing.gap + SongMenu.width),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// How many songs there are, and how long they last together, where each says: "9 faixas, 37 min".
String songCountAndLength(AppLocalizations strings, List<Song> songs) => switch (songsLength(strings, songs)) {
  final length? => strings.tracksAndLength(strings.trackCount(songs.length), length),
  null => strings.trackCount(songs.length),
};

/// How long [songs] last together: "37 min", "1 h 14 min"; null where one doesn't say.
String? songsLength(AppLocalizations strings, List<Song> songs) {
  if (songs.any((song) => song.duration == null)) {
    return null;
  }

  final length = songs.fold(Duration.zero, (sum, song) => sum + song.duration!);
  final (hours, minutes) = (length.inHours, length.inMinutes % 60);
  return switch ((hours, minutes)) {
    (0, 0) => strings.lengthSeconds(length.inSeconds),
    (0, _) => strings.lengthMinutes(minutes),
    (_, 0) => strings.lengthHours(hours),
    _ => strings.lengthHoursMinutes(hours, minutes),
  };
}
