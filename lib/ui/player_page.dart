import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';

import '../connect/connect.dart';
import 'cover.dart';
import 'devices_sheet.dart';
import 'lyrics_view.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'player_controls.dart';
import 'queue_page.dart';
import 'song_link.dart';
import 'themed_icon.dart';

/// The full-screen player: what plays, wherever it plays, big, with every control, and its lyrics beside
/// it (on a phone, under it).
class PlayerPage extends StatelessWidget {
  const PlayerPage(this._lyrics, {super.key});

  /// Whether the lyrics show: turned on and off at the top, or, on a wide screen, in the bar under the player.
  final ValueNotifier<bool> _lyrics;

  /// How long the lyrics take to come in, beside the player or under it, and to go.
  static const lyricsTransition = Duration(milliseconds: 350);

  /// Slides it up over the current page, with the lyrics if [lyrics]: on a wide screen, in the page area.
  static Future<void> open(BuildContext context, {bool lyrics = false}) =>
      PageArea.navigatorOf(context).push(PlayerRoute(lyrics: lyrics));

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();

    // On a wide screen the bar stays under the player, with what would be at its top: the lyrics, the
    // queue and the devices. A phone's bar has no room for the first two, which stay at the top.
    final wide = MediaQuery.sizeOf(context).width >= NowPlayingBar.wideFrom;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: _lyrics,
          builder: (context, _) => NowPlayingBuilder(
            builder: (context, connect, now) {
              final lyrics = _lyrics.value;
              final colors = Theme.of(context).colorScheme;
              final device = now?.device;
              return Scaffold(
                appBar: AppBar(
                  // The background's color, always: neither the lyrics nor, on a phone, the page tint it as
                  // they scroll under it.
                  notificationPredicate: (_) => false,
                  leading: IconButton(
                    tooltip: 'Fechar',
                    icon: const ThemedIcon(HugeIcons.strokeRoundedArrowDown01),
                    onPressed: close,
                  ),
                  centerTitle: true,
                  title: device == null
                      ? null
                      : Text(
                          '${now!.playing ? 'Tocando' : 'Pausado'} em $device',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                  actions: [
                    if (!wide) ...[
                      IconButton(
                        tooltip: lyrics ? 'Esconder a letra' : 'Mostrar a letra',
                        icon: ThemedIcon(HugeIcons.strokeRoundedMicVocal, color: lyrics ? colors.primary : null),
                        onPressed: () => _lyrics.value = !lyrics,
                      ),
                      IconButton(
                        tooltip: 'Fila',
                        icon: const ThemedIcon(HugeIcons.strokeRoundedPlaylist03),
                        onPressed: () => QueuePage.open(context),
                      ),
                      IconButton(
                        tooltip: 'Aparelhos',
                        icon: ThemedIcon(
                          HugeIcons.strokeRoundedMonitorSpeaker,
                          color: device == null ? null : colors.primary,
                        ),
                        onPressed: () => showDevicesSheet(context),
                      ),
                    ],
                  ],
                ),
                body: now == null ? const Center(child: Text('Nada tocando')) : _Player(now, connect, lyrics: lyrics),
                bottomNavigationBar: wide ? NowPlayingBar(lyrics: _lyrics) : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The full-screen player's route, which slides it up, and holds whether it shows the lyrics: on a wide screen, the
/// home's player bar under it turns them on and off.
class PlayerRoute extends PageRouteBuilder<void> {
  PlayerRoute({bool lyrics = false}) : this._(ValueNotifier(lyrics));

  PlayerRoute._(this.lyrics)
    : super(
        pageBuilder: (_, _, _) => PlayerPage(lyrics),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
      );

  final ValueNotifier<bool> lyrics;

  @override
  void dispose() {
    lyrics.dispose();
    super.dispose();
  }
}

class _Player extends StatelessWidget {
  const _Player(this.now, this.connect, {required this.lyrics});

  final NowPlaying now;
  final ConnectController connect;

  /// Whether the lyrics show.
  final bool lyrics;

  /// From how wide the lyrics go beside the player rather than under it.
  static const _lyricsBesideFrom = 720.0;

  /// How big the cover gets, at most: as big as the image asked of the server.
  static const _maxCover = 800.0;

  @override
  Widget build(BuildContext context) {
    // How far the lyrics have come in, from 0 (gone) to 1 (there), as they come and go. Opened with them, the player
    // shows them at once: the tween starts where it ends.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: lyrics ? 1 : 0),
      duration: PlayerPage.lyricsTransition,
      curve: Curves.easeInOutCubic,
      builder: (context, shown, _) => LayoutBuilder(builder: (context, box) => _layout(context, box, shown)),
    );
  }

  /// The player and, [shown] of the way in, its lyrics, in [box].
  Widget _layout(BuildContext context, BoxConstraints box, double shown) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant;
    final beside = box.maxWidth >= _lyricsBesideFrom;
    // Beside the player, the lyrics take half the screen, the player the rest, which shrinks as they come in.
    final room = beside ? box.maxWidth * (1 - shown / 2) : box.maxWidth;
    // The cover as big as it fits, leaving room for the rest under it.
    final width = room - 48;
    final side = min(width, box.maxHeight - 280).clamp(96.0, _maxCover);
    final player = SizedBox(
      width: max(side, 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: SizedBox.square(
              dimension: side,
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Cover(now.coverArt, size: 800)),
            ),
          ),
          const SizedBox(height: 24),
          SongLink.title(
            now,
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 2,
            textAlign: TextAlign.center,
            replace: true,
          ),
          SongLink.artist(
            now,
            style: text.titleLarge?.copyWith(color: muted),
            textAlign: TextAlign.center,
            replace: true,
          ),
          if (now.album != null)
            SongLink.album(
              now,
              style: text.titleMedium?.copyWith(color: muted),
              textAlign: TextAlign.center,
              replace: true,
            ),
          const SizedBox(height: 12),
          SeekSlider(now, timesBelow: true),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ShuffleButton(now),
              IconButton(
                tooltip: 'Anterior',
                iconSize: 36,
                icon: const ThemedIcon(HugeIcons.strokeRoundedPrevious),
                onPressed: () => runCommand(context, connect.previous),
              ),
              IconButton.filled(
                tooltip: now.playing ? 'Pausar' : 'Tocar',
                iconSize: 40,
                padding: const EdgeInsets.all(14),
                icon: ThemedIcon(now.playing ? HugeIcons.strokeRoundedPause : HugeIcons.strokeRoundedPlay),
                onPressed: () => runCommand(context, connect.toggle),
              ),
              IconButton(
                tooltip: 'Próxima',
                iconSize: 36,
                icon: const ThemedIcon(HugeIcons.strokeRoundedNext),
                onPressed: () => runCommand(context, connect.next),
              ),
              RepeatButton(now),
            ],
          ),
          // Under the player, the lyrics' room grows as they fade in.
          if (shown > 0 && !beside)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: shown,
                child: Opacity(
                  opacity: shown,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: SizedBox(height: 400, child: LyricsView(now)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (!beside) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Center(child: player),
      );
    }

    // In the end, half the screen each: the player in the middle of its half, the lyrics all of theirs. On the
    // way, they slide in from the right as the player makes room for them, laid out as they end up, rather than
    // narrower, which would wrap their lines anew at every step.
    return Row(
      children: [
        SizedBox(
          width: room,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: player,
            ),
          ),
        ),
        if (shown > 0)
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minWidth: box.maxWidth / 2,
                maxWidth: box.maxWidth / 2,
                child: Opacity(opacity: shown, child: LyricsView(now)),
              ),
            ),
          ),
      ],
    );
  }
}
