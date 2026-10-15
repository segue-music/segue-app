import 'package:flutter/material.dart';

import '../../services.dart';
import '../player/now_playing_bar.dart';

/// In a phone's layout, the bars at the bottom of the home, and of a page of its own over everything (the queue's), so
/// that they stay put from one to the other: the player's ([NowPlayingBar]) and the home's sections' ([sections]),
/// alike in color and corners. On a phone the player's is over the sections', which go on to the bottom of the screen,
/// a small gap between them; on a tablet narrower than [besideFrom], the same, in the middle, as wide as a phone's at
/// most ([phoneWidth]). From [besideFrom] across (a tablet's, a phone's turned), they float side by side over the page,
/// [floatingGap] from each other, the screen's sides and the system's bar, which they keep clear of: the sections' at
/// the start, in the room the player's leaves them, as tall as each other, their icons and names in the middle.
/// Nothing playing, the sections' alone.
class PhoneBars extends StatelessWidget {
  const PhoneBars({required this.sections, super.key});

  /// The home's sections' bar, on [background].
  final NavigationBar Function(Color background) sections;

  /// How wide the bars are at most, on a touch screen wider than a phone's (a tablet's): across the whole of it, the
  /// destinations and the player's few buttons would be far apart.
  static const phoneWidth = 560.0;

  /// From how wide a touch screen is (a tablet's, a phone's turned), the player's bar goes beside the sections', rather
  /// than over them: one bar's height taken from the page rather than two's, where the width has room for both.
  static const besideFrom = 760.0;

  /// How wide the player's bar is beside the sections': as on a big phone, the sections' taking the rest.
  static const besideWidth = 400.0;

  /// How far the bars, floating over the page side by side, are from each other, from the screen's sides and from the
  /// system's bar.
  static const floatingGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final connect = ServicesScope.of(context).connect;
    final color = Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: NowPlayingBar.phoneOpacity);

    if (MediaQuery.sizeOf(context).width < besideFrom) {
      return Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: phoneWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Above the sections' bar, which keeps clear of the system's at the bottom of the screen: the player's
              // needn't, and a small gap sets the two apart, alike in color. Nothing playing, there is no player to set
              // apart.
              MediaQuery.removePadding(context: context, removeBottom: true, child: const NowPlayingBar()),
              ListenableBuilder(
                listenable: connect,
                builder: (context, _) => SizedBox(height: connect.nowPlaying == null ? 0 : 2),
              ),
              // Its top corners rounded as the player's, the page showing around them.
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: NowPlayingBar.phoneCorner),
                child: sections(color),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(floatingGap, 0, floatingGap, floatingGap),
        child: ListenableBuilder(
          listenable: connect,
          child: ClipRRect(
            borderRadius: const BorderRadius.all(NowPlayingBar.phoneCorner),
            child: ColoredBox(
              color: color,
              child: Center(heightFactor: 1, child: sections(Colors.transparent)),
            ),
          ),
          builder: (context, sections) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: sections!),
                if (connect.nowPlaying != null) ...[
                  const SizedBox(width: floatingGap),
                  const SizedBox(width: besideWidth, child: NowPlayingBar()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
