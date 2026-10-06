import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../services.dart';
import 'current_song.dart';
import 'themed_icon.dart';

/// A cover from the media server, or a placeholder.
class Cover extends StatelessWidget {
  const Cover(this.id, {this.size = 300, this.icon = HugeIcons.strokeRoundedCd, super.key});

  final String? id;

  /// Pixels asked of the server.
  final int size;

  /// What the placeholder shows.
  final HugeIconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: ThemedIcon(icon)),
    );
    final id = this.id;

    if (id == null) {
      return placeholder;
    }

    return Image.network(
      ServicesScope.of(context).api.coverArtUrl(id, size: size).toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// A small cover, for a list.
class Thumbnail extends StatelessWidget {
  const Thumbnail(this.coverArt, {this.round = false, this.playing = false, super.key});

  final String? coverArt;

  /// An artist's: round, with a person for a placeholder.
  final bool round;

  /// A song's that plays: the equalizer goes over it, on a veil.
  final bool playing;

  /// How big it is, square.
  static const size = 48.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: round
        ? ClipOval(child: Cover(coverArt, size: 96, icon: HugeIcons.strokeRoundedUser))
        : ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(coverArt, size: 96),
                // The primary color's light tone in either theme, which stands out on the dark veil.
                if (playing)
                  ColoredBox(
                    color: Colors.black54,
                    child: ThemedIcon(CurrentSong.icon, color: Theme.of(context).colorScheme.primaryFixedDim),
                  ),
              ],
            ),
          ),
  );
}
