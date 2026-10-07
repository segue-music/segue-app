import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import 'lyrics_view.dart';
import 'now_playing_bar.dart';
import 'player_controls.dart';
import 'themed_icon.dart';

/// The lyrics full screen, from under the full-screen player, where they are short: the song's title and artist above
/// them and, where the bar isn't under it (on a phone), the slider and the buttons under them. There, a line tapped
/// goes where it starts.
class LyricsPage extends StatelessWidget {
  const LyricsPage({super.key});

  /// Fades it in over the full-screen player.
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const LyricsPage(),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();

    final wide = MediaQuery.sizeOf(context).width >= NowPlayingBar.wideFrom;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: NowPlayingBuilder(
          builder: (context, _, now) {
            final text = Theme.of(context).textTheme;
            final muted = Theme.of(context).colorScheme.onSurfaceVariant;
            final strings = AppLocalizations.of(context);
            return Scaffold(
              appBar: AppBar(
                // The background's color, always: the lyrics don't tint it as they scroll under it.
                notificationPredicate: (_) => false,
                automaticallyImplyLeading: false,
                // As wide as the button at the other end, so that the song stays in the middle.
                leading: const SizedBox(),
                centerTitle: true,
                title: now == null
                    ? null
                    : Column(
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
              body: now == null
                  ? Center(child: Text(strings.nothingPlaying))
                  : Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: LyricsView(now)),
              bottomNavigationBar: now == null || wide
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
    );
  }
}
