import 'package:flutter/material.dart';

import '../widgets/directional_navigation.dart';

/// On a TV, the app as it's read and driven from across the room: by the remote ([DirectionalNavigation]), its text a
/// bit bigger than the system's, and away from the screen's edges, which some TVs cut off (overscan). The edges' room
/// goes in as the system's own padding: the bars and the pages keep their content out of it, as of a phone's notch and
/// status bar, and their backgrounds go on to the edges.
class TelevisionScreen extends StatelessWidget {
  const TelevisionScreen({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  /// How much bigger the text is: a seventh, about, over the sizes Material gives a phone, which are Android TV's own.
  static const textScale = 1.15;

  /// The room at the screen's edges: an eighth of Android TV's 48 at the sides, and less than a quarter of its 27 above
  /// and below, since the bars keep their own room inside it. With all of it, on a TV that shows its whole picture, the
  /// content stood 60 from the sides and the two bars took a third of the screen's height; with half, it still looked
  /// far from the edges, and with a quarter, the home's sides too.
  static const margins = EdgeInsets.all(6);

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
