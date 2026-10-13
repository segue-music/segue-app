import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../device.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/themed_icon.dart';
import 'lyrics_view.dart';
import 'now_playing_bar.dart';
import 'player_controls.dart';

/// The lyrics full screen, from under the full-screen player, where they are short: the song's title and artist above
/// them and, where the bar isn't under it (on a phone), the slider and the buttons under them. There, a line tapped
/// goes where it starts. At the top, a button takes them back to the player, and another hides them, the player
/// back as it opened. While they show, the screen stays on (on a phone or a tablet), as they are read, not touched.
class LyricsPage extends StatelessWidget {
  const LyricsPage({required this.onHide, super.key});

  /// Closes them and hides them under the player too.
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();

    final wide = MediaQuery.sizeOf(context).width >= NowPlayingBar.wideFrom;

    return KeepScreenOn(
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
        child: Focus(
          autofocus: true,
          child: PlayingPageBuilder(
            builder: (context, _, now) {
              final text = Theme.of(context).textTheme;
              final muted = Theme.of(context).colorScheme.onSurfaceVariant;
              final strings = AppLocalizations.of(context);

              return Scaffold(
                appBar: AppBar(
                  // The background's color, always: the lyrics don't tint it as they scroll under it.
                  notificationPredicate: (_) => false,
                  // Down, as they go.
                  leading: IconButton(
                    tooltip: strings.hideLyrics,
                    icon: const ThemedIcon(HugeIcons.strokeRoundedArrowDown01),
                    onPressed: onHide,
                  ),
                  centerTitle: true,
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        now.title ?? '',
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        now.artist ?? '',
                        style: text.bodySmall?.copyWith(color: muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  // Where the button that opened it was, at the lyrics' corner.
                  actions: [
                    IconButton(
                      tooltip: strings.minimizeLyrics,
                      icon: const ThemedIcon(HugeIcons.strokeRoundedArrowShrink02),
                      onPressed: close,
                    ),
                  ],
                ),
                body: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: LyricsView(now)),
                bottomNavigationBar: wide
                    ? null
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SeekSlider(now, timesBelow: true),
                              const SizedBox(height: 8),
                              PlaybackButtons(now),
                            ],
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}
