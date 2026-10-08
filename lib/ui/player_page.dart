import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';

import '../connect/connect.dart';
import '../l10n/app_localizations.dart';
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
/// itself, and a drag down closes it.
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
        child: _DragToClose(
          enabled: !wide,
          builder: (context, scroll) => ListenableBuilder(
            listenable: _lyrics,
            builder: (context, _) => NowPlayingBuilder(
              builder: (context, _, now) {
                final lyrics = _lyrics.value;
                final colors = Theme.of(context).colorScheme;
                final device = now?.device;
                final strings = AppLocalizations.of(context);
                return Scaffold(
                  appBar: AppBar(
                    // The background's color, always: neither the lyrics nor, on a phone, the page tint it as
                    // they scroll under it.
                    notificationPredicate: (_) => false,
                    leading: IconButton(
                      tooltip: strings.close,
                      icon: const ThemedIcon(HugeIcons.strokeRoundedArrowDown01),
                      onPressed: close,
                    ),
                    centerTitle: true,
                    // On a wide screen, where it plays, when that's another device. On a phone, the song's album:
                    // there the devices button at the bottom, tinted, says where it plays.
                    title: switch (now) {
                      final now? when wide && device != null => Text(
                        now.playing ? strings.playingOn(device) : strings.pausedOn(device),
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
                      ? Center(child: Text(strings.nothingPlaying))
                      : _Player(now, lyrics: lyrics, controls: !wide, scroll: scroll),
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
                                  tooltip: lyrics ? strings.hideLyrics : strings.showLyrics,
                                  icon: ThemedIcon(
                                    HugeIcons.strokeRoundedMicVocal,
                                    color: lyrics ? colors.primary : null,
                                  ),
                                  onPressed: () => _lyrics.value = !lyrics,
                                ),
                                IconButton(
                                  tooltip: strings.devices,
                                  icon: ThemedIcon(
                                    HugeIcons.strokeRoundedMonitorSpeaker,
                                    color: device == null ? null : colors.primary,
                                  ),
                                  onPressed: () => showDevicesSheet(context),
                                ),
                                IconButton(
                                  tooltip: strings.queue,
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
      ),
    );
  }
}

/// The full-screen player's route, which slides it up, and holds whether it shows the lyrics: on a wide screen, the
/// home's player bar under it turns them on and off. On a phone, a drag down slides it down ([_CloseDrag]).
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
      );

  final ValueNotifier<bool> lyrics;

  /// The page area the player opened from, which it takes along: on a phone, where it opens over the area, out of it,
  /// its links open their pages there all the same.
  final PageArea? area;

  /// Slides it up as it opens and down as it closes, and, as a drag down moves it, with no curve, with the finger.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = Tween(begin: const Offset(0, 1), end: Offset.zero);
    return SlideTransition(
      position: (popGestureInProgress ? slide : slide.chain(CurveTween(curve: Curves.easeOutCubic))).animate(animation),
      child: child,
    );
  }

  /// Starts a drag of the player down, [height] pixels tall.
  _CloseDrag _startClosing(double height) => _CloseDrag(this, controller!, height);

  @override
  void dispose() {
    lyrics.dispose();
    super.dispose();
  }
}

/// A finger dragging the full-screen player down, on a phone: the player follows it, and let go, closes, or goes back
/// up ([end]). The navigator takes it as a user's gesture, as it does the iOS back swipe: until the player has settled,
/// its route slides it with no curve ([PlayerRoute.buildTransitions]), and the page under it shows.
class _CloseDrag {
  _CloseDrag(this._route, this._controller, this._height) : _navigator = _route.navigator! {
    _navigator.didStartUserGesture();
  }

  final PlayerRoute _route;
  final NavigatorState _navigator;

  /// The route's animation: 1 with the player open, 0 with it a screen down, closed.
  final AnimationController _controller;

  /// How tall the player is: how far down it goes to close.
  final double _height;

  /// How fast a fling down closes the player, however short, in pixels a second.
  static const _flingFrom = 700.0;

  /// Whether the player is down from where it opens.
  bool get moved => _controller.value < 1;

  /// Moves the player [down] pixels down (below zero, up), no higher than it opens, and returns what is left of
  /// [down]: up, past where it opens.
  double update(double down) {
    if (!_route.isCurrent) {
      return down;
    }

    final moving = max(down, -(1 - _controller.value) * _height);
    _controller.value -= moving / _height;
    return down - moving;
  }

  /// Lets go of the player, moving at [velocity] pixels a second down (below zero, up): flung down, or let go past a
  /// third of the way down, it closes; otherwise it goes back up.
  void end(double velocity) {
    final close = _route.isCurrent
        ? moved && (velocity.abs() >= _flingFrom ? velocity > 0 : _controller.value < 2 / 3)
        // Gone from the top meanwhile: closed, it goes on closing; under another page, it goes back up.
        : !_route.isActive;

    if (!close) {
      _controller.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      if (_route.isCurrent) {
        _navigator.pop();
      }

      // From where it is, unless it has closed already, from all the way down.
      if (_controller.isAnimating) {
        _controller.animateBack(0, curve: Curves.easeOutCubic);
      }
    }

    if (!_controller.isAnimating) {
      _settle(closed: close);
      return;
    }

    late final AnimationStatusListener settle;
    settle = (_) {
      _controller.removeStatusListener(settle);
      _settle(closed: close);
    };
    _controller.addStatusListener(settle);
  }

  /// Ends the drag as [end] does for a finger let go still, after this frame: for one that nothing follows any more, as
  /// its widgets go, when the navigator can't change.
  void endLater() => WidgetsBinding.instance.addPostFrameCallback((_) => end(0));

  /// Ends the user's gesture, the player settled. Back up, it takes back the focus, which the navigator gave the page
  /// under it for the gesture (Esc closes it again): after the frame that lets it have it.
  void _settle({required bool closed}) {
    if (!_navigator.mounted) {
      return;
    }

    _navigator.didStopUserGesture();

    if (!closed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _route.subtreeContext;

        if (_route.isCurrent && context != null) {
          FocusScope.of(context, createDependency: false).requestFocus();
        }
      });
    }
  }
}

/// On a phone, the full-screen player, which a drag down takes down with it, toward closing it ([_CloseDrag]): on the
/// bars as on the song, and, where the page is taller than the screen (on a small phone, with the lyrics), once it has
/// scrolled to its top ([_ClosingScrollPosition]). The lyrics scroll as they do.
class _DragToClose extends StatefulWidget {
  const _DragToClose({required this.enabled, required this.builder});

  /// Whether a drag down closes the player: on a phone.
  final bool enabled;

  /// The player, whose page scrolls with `scroll`, where it is taller than the screen.
  final Widget Function(BuildContext context, ScrollController scroll) builder;

  @override
  State<_DragToClose> createState() => _DragToCloseState();
}

class _DragToCloseState extends State<_DragToClose> {
  late final _scroll = _ClosingScrollController(_start);

  /// The drag down under way on the page, rather than on its scroll view, which follows its own.
  _CloseDrag? _drag;

  /// Starts a drag of the player down, if one closes it.
  _CloseDrag? _start() {
    final route = ModalRoute.of(context);
    return widget.enabled && route is PlayerRoute && route.isCurrent ? route._startClosing(context.size!.height) : null;
  }

  void _update(DragUpdateDetails details) {
    final down = details.primaryDelta ?? 0;

    if (_drag == null && down > 0) {
      _drag = _start();
    }

    _drag?.update(down);
  }

  void _end(DragEndDetails details) {
    _drag?.end(details.primaryVelocity ?? 0);
    _drag = null;
  }

  /// Ends the drag under way, whose end won't come, as the page goes or stops being a phone's.
  void _abandon() {
    _drag?.endLater();
    _drag = null;
  }

  @override
  void didUpdateWidget(_DragToClose oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.enabled) {
      _abandon();
    }
  }

  @override
  void dispose() {
    _abandon();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragUpdate: widget.enabled ? _update : null,
    onVerticalDragEnd: widget.enabled ? _end : null,
    child: widget.builder(context, _scroll),
  );
}

/// The player's scroll controller, whose page, dragged down at its top, drags the player down instead
/// ([_ClosingScrollPosition]).
class _ClosingScrollController extends ScrollController {
  _ClosingScrollController(this._start);

  /// Starts a drag of the player down, if one closes it.
  final _CloseDrag? Function() _start;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _ClosingScrollPosition(_start, physics: physics, context: context, oldPosition: oldPosition);
}

/// Where the player's page has scrolled to, when it is taller than the screen: dragged down at its top, the cover's, it
/// drags the player down, toward closing it, as the finger goes on, and scrolls again once the player is back up.
class _ClosingScrollPosition extends ScrollPositionWithSingleContext {
  _ClosingScrollPosition(this._start, {required super.physics, required super.context, super.oldPosition});

  /// Starts a drag of the player down, if one closes it.
  final _CloseDrag? Function() _start;

  /// The drag of the player down under way, from when the finger went on down from the page's top.
  _CloseDrag? _drag;

  /// Whether the offsets go up the screen: the player's page, which starts at its bottom, is reversed.
  bool get _reversed => axisDirectionIsReversed(axisDirection);

  @override
  void applyUserOffset(double delta) {
    var down = _reversed ? -delta : delta;

    // Down to the page's top, the page scrolls, and from there on, the player goes down, until it is back up.
    if (!(_drag?.moved ?? false)) {
      final scrolling = min(down, max(_reversed ? maxScrollExtent - pixels : pixels - minScrollExtent, 0.0));
      _scroll(scrolling);
      down -= scrolling;

      if (down <= 0) {
        return;
      }

      _drag ??= _start();
    }

    _scroll(_drag?.update(down) ?? down);
  }

  /// Scrolls the page as a finger going [down] pixels down does.
  void _scroll(double down) {
    if (down != 0) {
      super.applyUserOffset(_reversed ? -down : down);
    }
  }

  /// The finger let go: the player closes or goes back up, and the page, if the player took the drag, stays.
  @override
  void goBallistic(double velocity) {
    final drag = _drag;

    if (drag == null) {
      super.goBallistic(velocity);
      return;
    }

    _drag = null;
    final moved = drag.moved;
    drag.end(_reversed ? velocity : -velocity);
    super.goBallistic(moved ? 0 : velocity);
  }

  @override
  void dispose() {
    // Gone as the page changes, with no end to come to the drag.
    _drag?.endLater();
    super.dispose();
  }
}

class _Player extends StatelessWidget {
  const _Player(this.now, {required this.lyrics, required this.controls, required this.scroll});

  final NowPlaying now;

  /// Whether the lyrics show.
  final bool lyrics;

  /// Whether the slider and the buttons show under the song: on a phone, where the bar isn't under the player.
  final bool controls;

  /// How the page scrolls, under the player, where it is taller than the screen.
  final ScrollController scroll;

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
          Center(child: _SwipeToSkip(now.coverArt, side: side)),
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
                              tooltip: AppLocalizations.of(context).maximizeLyrics,
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
        controller: scroll,
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
/// right). It follows the finger; let go past a third of its width, or flung, it goes out on that side, as it was, and
/// comes back from the other, with the song it went to, and otherwise back to its place. The covers of the songs on
/// either side load ahead, so that the one that comes back is there at once.
class _SwipeToSkip extends StatefulWidget {
  const _SwipeToSkip(this.coverArt, {required this.side});

  /// The cover of the song that plays.
  final String? coverArt;

  /// How big the cover is, square.
  final double side;

  @override
  State<_SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<_SwipeToSkip> with SingleTickerProviderStateMixin {
  /// How far the cover is from its place, in pixels: to the left, below zero.
  late final _offset = AnimationController.unbounded(vsync: this);

  /// How wide the cover is, from when a drag starts.
  double _width = 0;

  /// As a swipe goes to another song, the cover that goes out: the one of the song it leaves, though the song changes
  /// on the way.
  ({String? coverArt})? _leaving;

  /// The covers loaded ahead.
  ({String? next, String? previous})? _ahead;

  /// How fast a fling goes to another song, however short, in pixels a second.
  static const _flingFrom = 700.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preload();
  }

  @override
  void didUpdateWidget(_SwipeToSkip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _preload();
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  /// Loads the covers of the songs a swipe goes to, once each, so that the one that comes back shows at once, rather
  /// than nothing until it has loaded.
  void _preload() {
    final connect = ServicesScope.of(context).connect;
    final ahead = (next: connect.coverArtBeside(1), previous: connect.coverArtBeside(-1));

    if (ahead == _ahead) {
      return;
    }

    _ahead = ahead;

    for (final id in [ahead.next, ahead.previous].nonNulls) {
      unawaited(Cover.preload(context, id, size: _Player._maxCover.toInt()));
    }
  }

  /// What a swipe [toward] a side does: to the left, the next song; to the right, the previous one, wherever the song
  /// is (the button, past a song's first seconds, starts it over), by its place in the queue, on a device that takes a
  /// jump to one. On the first song there is none to go to, and on the last none either, unless the queue repeats: then
  /// the next one is the first (SPEC.md, section 5).
  Future<Result> Function()? _skip(double toward) {
    final connect = ServicesScope.of(context).connect;

    if (toward < 0) {
      final queue = connect.queue;
      final last = queue.index == queue.tracks.length - 1;
      return last && connect.nowPlaying?.repeat == Repeat.off ? null : connect.next;
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

    setState(() => _leaving = (coverArt: widget.coverArt));
    unawaited(runCommand(context, skip));
    final out = toward < 0 ? -_width : _width;
    await _offset.animateTo(out, duration: const Duration(milliseconds: 150), curve: Curves.easeIn);

    if (!mounted) {
      return;
    }

    setState(() => _leaving = null);
    _offset.value = -out;
    await _offset.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    return GestureDetector(
      onHorizontalDragStart: (_) {
        _offset.stop();
        _width = context.size?.width ?? 0;
        // Caught on its way out, it shows the song it went to: the swipe that sent it out won't bring it back.
        setState(() => _leaving = null);
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
        child: SizedBox.square(
          dimension: widget.side,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Cover(
              leaving == null ? widget.coverArt : leaving.coverArt,
              size: _Player._maxCover.toInt(),
              gapless: true,
            ),
          ),
        ),
      ),
    );
  }
}
