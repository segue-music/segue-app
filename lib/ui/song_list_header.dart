import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'cover.dart';

/// The header of a list of songs, naming its columns over them: their numbers ("#") or covers (unnamed), their
/// title, and their duration, as a clock. A list tile as they are, so that its columns line up with theirs; disabled,
/// so that neither the pointer, the keyboard nor a remote stops at it.
class SongListHeader extends StatelessWidget {
  const SongListHeader({this.numbered = false, super.key});

  /// Whether the songs are numbered, as an album's are, rather than shown with their covers, as the queue's.
  final bool numbered;

  /// How wide a numbered song's number is.
  static const numberWidth = 24.0;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: muted);
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
          title: Text('Título', style: style),
          trailing: Tooltip(
            message: 'Duração',
            child: Icon(HugeIcons.strokeRoundedClock01, size: 18, color: muted),
          ),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}
