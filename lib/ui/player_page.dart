import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';

import '../connect/connect.dart';
import '../segue/protocol.dart';
import '../services.dart';
import 'cover.dart';
import 'devices_sheet.dart';
import 'lyrics_page.dart';
import 'lyrics_view.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'player_controls.dart';
import 'queue_page.dart';
import 'song_link.dart';
import 'themed_icon.dart';

/// The full-screen player: what plays, wherever it plays, big, and its lyrics beside it (on a phone, under it). On a
/// wide screen the player bar stays under it, with the controls; on a phone, where there is none, it has every control
/// itself.
class PlayerPage extends StatelessWidget {
  const PlayerPage(this._lyrics, {super.key});

  /// Whether the lyrics show: turned on and off at the top, or, on a wide screen, in the bar under the player.
  final ValueNotifier<bool> _lyrics;

  /// How long the lyrics take to come in, beside the player or under it, and to go.
  static const lyricsTransition = Duration(milliseconds: 350);

  /// Slides it up over the current page, with the lyrics if [lyrics]: on a wide screen, in the page area; on a phone,
  /// over everything, the page area's bars too.
  static Future<void> open(BuildContext context, {bool lyrics = false}) =>
      PageArea.playerNavigatorOf(context).push(PlayerRoute(lyrics: lyrics, area: PageArea.maybeOf(context)));

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();

    // On a wide screen the bar stays under the player, with what would be at its top: the lyrics, the
    // queue and the devices. On a phone, which has no bar there, they go in one of their own, at the bottom.
    final wide = MediaQuery.sizeOf(context).width >= NowPlayingBar.wideFrom;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: _lyrics,
          builder: (context, _) => NowPlayingBuilder(
            builder: (context, _, now) {
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
                  // On a wide screen, where it plays, when that's another device. On a phone, the song's album:
                  // there the devices button at the bottom, tinted, says where it plays.
                  title: switch (now) {
                    final now? when wide && device != null => Text(
                      '${now.playing ? 'Tocando' : 'Pausado'} em $device',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    final now? when !wide && now.album != null => SongLink.album(
                      now,
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                      replace: true,
                    ),
                    _ => null,
                  },
                  // As wide as the close button, so that the album stays in the middle, a long one too.
                  actions: [if (!wide) const SizedBox(width: kToolbarHeight)],
                ),
                body: now == null
                    ? const Center(child: Text('Nada tocando'))
                    : _Player(now, lyrics: lyrics, controls: !wide),
                bottomNavigationBar: wide
                    ? NowPlayingBar(lyrics: _lyrics)
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                tooltip: lyrics ? 'Esconder a letra' : 'Mostrar a letra',
                                icon: ThemedIcon(
                                  HugeIcons.strokeRoundedMicVocal,
                                  color: lyrics ? colors.primary : null,
                                ),
                                onPressed: () => _lyrics.value = !lyrics,
                              ),
                              IconButton(
                                tooltip: 'Aparelhos',
                                icon: ThemedIcon(
                                  HugeIcons.strokeRoundedMonitorSpeaker,
                                  color: device == null ? null : colors.primary,
                                ),
                                onPressed: () => showDevicesSheet(context),
                              ),
                              IconButton(
                                tooltip: 'Fila',
                                icon: const ThemedIcon(HugeIcons.strokeRoundedPlaylist03),
                                onPressed: () => QueuePage.open(context),
                              ),
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

/// The full-screen player's route, which slides it up, and holds whether it shows the lyrics: on a wide screen, the
/// home's player bar under it turns them on and off.
class PlayerRoute extends PageRouteBuilder<void> {
  PlayerRoute({bool lyrics = false, PageArea? area}) : this._(ValueNotifier(lyrics), area);

  PlayerRoute._(this.lyrics, this.area)
    : super(
        pageBuilder: (_, _, _) => area == null
            ? PlayerPage(lyrics)
            : PageArea(
                navigator: area.navigator,
                history: area.history,
                underTopBar: area.underTopBar,
                child: PlayerPage(lyrics),
              ),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
      );

  final ValueNotifier<bool> lyrics;

  /// The page area the player opened from, which it takes along: on a phone, where it opens over the area, out of it,
  /// its links open their pages there all the same.
  final PageArea? area;

  @override
  void dispose() {
    lyrics.dispose();
    super.dispose();
  }
}

class _Player extends StatelessWidget {
  const _Player(this.now, {required this.lyrics, required this.controls});

  final NowPlaying now;

  /// Whether the lyrics show.
  final bool lyrics;

  /// Whether the slider and the buttons show under the song: on a phone, where the bar isn't under the player.
  final bool controls;

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
    // The cover as big as it fits, leaving room for the rest under it: the song, and the controls where they show.
    // Under the player, the lyrics take that room from the cover as they come in: in the end, it keeps two fifths.
    final width = room - 48;
    final height = box.maxHeight - (controls ? 280 : 160);
    final alone = min(width, height).clamp(96.0, _maxCover);
    final withLyrics = min(width, height * 2 / 5).clamp(96.0, _maxCover);
    final side = beside ? alone : alone + (withLyrics - alone) * shown;
    // As wide as the cover alone: the rest keeps its width as the lyrics make the cover smaller.
    final player = SizedBox(
      width: max(alone, 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: _SwipeToSkip(
              child: SizedBox.square(
                dimension: side,
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Cover(now.coverArt, size: 800)),
              ),
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
          // On a phone the album is in the top bar.
          if (!controls && now.album != null)
            SongLink.album(
              now,
              style: text.titleMedium?.copyWith(color: muted),
              textAlign: TextAlign.center,
              replace: true,
            ),
          if (controls) ...[
            const SizedBox(height: 12),
            SeekSlider(now, timesBelow: true),
            const SizedBox(height: 8),
            PlaybackButtons(now),
          ],
          // Under the player, the lyrics are as tall as the room the cover gives up in the end (on a small phone, still
          // a few lines' worth), and their room grows to it as they fade in.
          if (shown > 0 && !beside)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: shown,
                child: Opacity(
                  opacity: shown,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    // A tap opens them full screen, as does the button at their corner.
                    child: SizedBox(
                      height: max(height - withLyrics - 24, 200),
                      child: Stack(
                        children: [
                          LyricsView(now, onTap: () => LyricsPage.open(context)),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              tooltip: 'Maximizar a letra',
                              icon: const ThemedIcon(HugeIcons.strokeRoundedArrowExpand01),
                              onPressed: () => LyricsPage.open(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (!beside) {
      // In the middle of the room between the bars. Taller than it, as on a small phone with the lyrics, it goes out
      // at the top rather than the bottom: the cover, rather than the controls and the lyrics' line that plays.
      return SingleChildScrollView(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: max(0, box.maxHeight - 16)),
          child: Center(child: player),
        ),
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

/// The cover, which a swipe to the side goes to the next song with (to the left) or to the previous one (to the
/// right). It follows the finger; let go past a third of its width, or flung, it goes out on that side and comes back
/// from the other, with the song it went to, and otherwise back to its place.
class _SwipeToSkip extends StatefulWidget {
  const _SwipeToSkip({required this.child});

  final Widget child;

  @override
  State<_SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<_SwipeToSkip> with SingleTickerProviderStateMixin {
  /// How far the cover is from its place, in pixels: to the left, below zero.
  late final _offset = AnimationController.unbounded(vsync: this);

  /// How wide the cover is, from when a drag starts.
  double _width = 0;

  /// How fast a fling goes to another song, however short, in pixels a second.
  static const _flingFrom = 700.0;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  /// What a swipe [toward] a side does: to the left, the next song; to the right, the previous one, wherever the song
  /// is (the button, past a song's first seconds, starts it over), by its place in the queue, on a device that takes a
  /// jump to one. On the first song there is none to go to.
  Future<Result> Function()? _skip(double toward) {
    final connect = ServicesScope.of(context).connect;

    if (toward < 0) {
      return connect.next;
    }

    if (!(connect.nowPlaying?.canJump ?? false)) {
      return connect.previous;
    }

    final previous = connect.queue.index - 1;
    return previous < 0 ? null : () => connect.jump(previous);
  }

  Future<void> _letGo(DragEndDetails details) async {
    final velocity = details.primaryVelocity ?? 0;
    final offset = _offset.value;
    // Where it goes: where it was flung, or else where it was let go, past a third of its width.
    final toward = velocity.abs() >= _flingFrom ? velocity : (offset.abs() > _width / 3 ? offset : 0.0);
    final skip = toward == 0 ? null : _skip(toward);

    if (skip == null) {
      await _offset.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      return;
    }

    unawaited(runCommand(context, skip));
    final out = toward < 0 ? -_width : _width;
    await _offset.animateTo(out, duration: const Duration(milliseconds: 150), curve: Curves.easeIn);

    if (!mounted) {
      return;
    }

    _offset.value = -out;
    await _offset.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragStart: (_) {
      _offset.stop();
      _width = context.size?.width ?? 0;
    },
    onHorizontalDragUpdate: (details) => _offset.value += details.primaryDelta ?? 0,
    onHorizontalDragEnd: _letGo,
    child: AnimatedBuilder(
      animation: _offset,
      // Fading as it goes, to half at a width away.
      builder: (context, child) => Transform.translate(
        offset: Offset(_offset.value, 0),
        child: Opacity(opacity: _width == 0 ? 1 : 1 - min(_offset.value.abs() / _width, 1) / 2, child: child),
      ),
      child: widget.child,
    ),
  );
}
