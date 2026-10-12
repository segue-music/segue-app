import 'package:flutter/material.dart';

import 'shortcuts.dart';

/// On a TV, the app as it's read and driven from across the room: by the remote ([DirectionalNavigation]), its text a
/// bit bigger than the system's, and away from the screen's edges, which some TVs cut off (overscan). The edges' room
/// is Android TV's, 48 by 27, as the system's own padding: the bars and the pages keep their content out of it, as of a
/// phone's notch and status bar, and their backgrounds go on to the edges.
class TelevisionScreen extends StatelessWidget {
  const TelevisionScreen({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  /// How much bigger the text is: a seventh, about, over the sizes Material gives a phone, which are Android TV's own.
  static const textScale = 1.15;

  /// The room at the screen's edges.
  static const margins = EdgeInsets.symmetric(horizontal: 48, vertical: 27);

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return DirectionalNavigation(enabled: false, child: child);
    }

    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(media.textScaler.scale(1) * textScale),
        padding: media.padding + margins,
        viewPadding: media.viewPadding + margins,
      ),
      child: DirectionalNavigation(enabled: true, child: child),
    );
  }
}
