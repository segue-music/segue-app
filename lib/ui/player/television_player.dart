import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../connect/connect.dart';
import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../playlist/playlist_dialogs.dart';
import '../song/favorite_button.dart';
import '../widgets/bar_traversal.dart';
import '../widgets/cover.dart';
import '../widgets/themed_icon.dart';
import 'devices_sheet.dart';
import 'player_page.dart';
import 'player_controls.dart';
import 'queue_page.dart';
import 'sleep_timer_button.dart';

/// On a TV, the full-screen player's controls, under [child], as a video player has them: they show as the player opens,
/// play taking the focus, and go after [idle] with no key pressed, leaving [child], the slider, where the song is, and
/// where it plays, when that's another device.
/// Hidden, the arrows and OK only bring them back, play taking the focus again, and the remote's back closes the
/// player; shown, back hides them first. The remote's play/pause, next and previous keys work either way.
class TelevisionControls extends StatefulWidget {
  const TelevisionControls(this.now, {required this.lyrics, required this.child, super.key});

  final NowPlaying now;

  /// Whether the full-screen player shows the lyrics, which a button turns on and off.
  final ValueNotifier<bool> lyrics;

  /// What plays: the cover, the song, its lyrics. As far from the screen's sides as the controls, whose ends it lines
  /// up with: the slider's times, where it plays.
  final Widget child;

  /// How long the controls stay with no key pressed.
  static const idle = Duration(seconds: 5);

  /// The room at the sides, of [child] and of the controls alike.
  static const side = 16.0;

  @override
  State<TelevisionControls> createState() => _TelevisionControlsState();
}

class _TelevisionControlsState extends State<TelevisionControls> {
  /// Where the focus waits while the controls are hidden: it takes the keys that bring them back.
  final _waiting = FocusNode(debugLabel: 'Hidden controls', skipTraversal: true);

  final _play = FocusNode(debugLabel: 'Play');

  bool _shown = true;
  Timer? _hiding;

  /// Whether back went down while the controls showed, hiding them: its going up is theirs too, rather than the
  /// system's, which would close the player.
  bool _backHides = false;

  /// The keys that bring the controls back: the remote's arrows and OK, a keyboard's Enter.
  static final _bringers = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  static final _backs = {LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape};

  /// How long the controls take to come and go.
  static const _fade = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_pressed);
    _hideLater();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_pressed);
    _hiding?.cancel();
    _waiting.dispose();
    _play.dispose();
    super.dispose();
  }

  /// Any key, while the controls show, keeps them a while longer: those a focused slider takes too (left and right),
  /// which never reach [_key].
  bool _pressed(KeyEvent event) {
    if (_shown && event is! KeyUpEvent) {
      _hideLater();
    }

    return false;
  }

  void _hideLater() {
    _hiding?.cancel();
    _hiding = Timer(TelevisionControls.idle, _hide);
  }

  /// Hides the controls, the focus waiting out of them, unless something opened over the player (a menu, the devices,
  /// the queue): they stay a while longer then, for the focus to come back to them.
  void _hide() {
    if (!mounted) {
      return;
    }

    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      _hideLater();
      return;
    }

    _hiding?.cancel();
    _waiting.requestFocus();
    setState(() => _shown = false);
  }

  void _show() {
    setState(() => _shown = true);
    _hideLater();
    // Once they can take it again.
    WidgetsBinding.instance.addPostFrameCallback((_) => _play.requestFocus());
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    if (_backs.contains(key)) {
      if (event is KeyDownEvent) {
        _backHides = _shown;

        if (_shown) {
          _hide();
        }
      }

      return _backHides ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (!_shown && _bringers.contains(key)) {
      if (event is KeyDownEvent) {
        _show();
      }

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final connect = ServicesScope.of(context).connect;
    final songId = now.songId;
    // Where the music goes, and what goes on beside it, as the wide player bar has them.
    final buttons = Row(
      children: [
        Expanded(
          flex: 4,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                switch (songId) {
                  final id? => FavoriteButton(FavoriteKind.song, id),
                  // Disabled for a song the hub couldn't give in the app's API.
                  null => IconButton(
                    tooltip: strings.addToFavorites,
                    icon: const ThemedIcon(HugeIcons.strokeRoundedFavourite),
                    onPressed: null,
                  ),
                },
                ShuffleButton(now),
                IconButton(
                  tooltip: strings.previous,
                  icon: const ThemedIcon(HugeIcons.strokeRoundedPrevious),
                  onPressed: () => runCommand(context, connect.previous),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: IconButton.filled(
                    focusNode: _play,
                    autofocus: true,
                    tooltip: now.playing ? strings.pause : strings.play,
                    iconSize: 32,
                    padding: const EdgeInsets.all(12),
                    icon: ThemedIcon(now.playing ? HugeIcons.strokeRoundedPause : HugeIcons.strokeRoundedPlay),
                    onPressed: () => runCommand(context, connect.toggle),
                  ),
                ),
                IconButton(
                  tooltip: strings.next,
                  icon: const ThemedIcon(HugeIcons.strokeRoundedNext),
                  onPressed: () => runCommand(context, connect.next),
                ),
                RepeatButton(now),
                ValueListenableBuilder(
                  valueListenable: widget.lyrics,
                  builder: (context, on, _) => IconButton(
                    tooltip: on ? strings.hideLyrics : strings.showLyrics,
                    icon: ThemedIcon(HugeIcons.strokeRoundedMicVocal, color: on ? colors.primary : null),
                    onPressed: () => widget.lyrics.value = !on,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AddToPlaylistButton(now),
              IconButton(
                tooltip: strings.queue,
                icon: const ThemedIcon(HugeIcons.strokeRoundedPlaylist03),
                onPressed: () => QueuePage.open(context),
              ),
              // The timer pauses this device's player: none while another device plays.
              if (now.device == null) const SleepTimerButton(),
              IconButton(
                tooltip: strings.devices,
                icon: ThemedIcon(
                  HugeIcons.strokeRoundedMonitorSpeaker,
                  color: now.device == null ? null : colors.primary,
                ),
                onPressed: () => showDevicesSheet(context),
              ),
            ],
          ),
        ),
      ],
    );
    final device = now.device;

    return Focus(
      focusNode: _waiting,
      onKeyEvent: _key,
      // While no one presses a key, the song plays to no one at the screen, maybe for hours.
      child: _Drift(
        moving: !_shown,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: TelevisionControls.side),
                child: widget.child,
              ),
            ),
            // Hidden, out of the focus's way, the slider too: the arrows only bring them back.
            ExcludeFocus(
              excluding: !_shown,
              child: FocusTraversalGroup(
                policy: BarTraversalPolicy.bottom,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: TelevisionControls.side),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Where it plays, when that's another device, stays as the buttons go, as the slider does.
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: device == null ? const SizedBox.shrink() : _PlayingOn(now, device, shown: _shown),
                          ),
                          Expanded(
                            flex: 7,
                            child: IgnorePointer(
                              ignoring: !_shown,
                              child: AnimatedOpacity(opacity: _shown ? 1 : 0, duration: _fade, child: buttons),
                            ),
                          ),
                        ],
                      ),
                      SeekSlider(now, timesAtEnds: true),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the full-screen player shows on a TV, moving slowly about its place while the controls are hidden, a few pixels
/// over minutes, which whoever watches doesn't see move: rather than the cover's edges, the title and the slider's line
/// lighting the same pixels for hours, which an OLED screen would keep a mark of (burn-in). Back in its place as the
/// controls come, for them to line up with what plays.
class _Drift extends StatefulWidget {
  const _Drift({required this.moving, required this.child});

  final bool moving;
  final Widget child;

  /// How far it goes from its place at most, sideways and up and down: less than the room at the screen's sides
  /// ([TelevisionControls.side], and the TV's edges), and than the slider's under its line.
  static const reach = Offset(12, 8);

  /// How long it takes to go to one side, to the other and back, and up, down and back: times apart, so that it goes
  /// over the whole of its room rather than to and fro along a line.
  static const sideways = Duration(minutes: 7);
  static const upAndDown = Duration(minutes: 5);

  /// How often it moves on: a step of a fraction of a pixel, which, drawn on the screen's whole pixels, moves it one
  /// now and then, with no frames in between.
  static const step = Duration(seconds: 1);

  @override
  State<_Drift> createState() => _DriftState();
}

class _DriftState extends State<_Drift> {
  Timer? _ticker;

  /// How long it has been moving.
  Duration _moved = Duration.zero;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_Drift oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.moving != oldWidget.moving) {
      _follow();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Starts moving, from its place, or stops.
  void _follow() {
    _ticker?.cancel();
    _ticker = null;
    _moved = Duration.zero;

    if (widget.moving) {
      _ticker = Timer.periodic(_Drift.step, (_) => setState(() => _moved += _Drift.step));
    }
  }

  /// Where it is, [_moved] in, on the path it takes: a Lissajous figure, from its place.
  Offset get _offset {
    double wave(Duration period) => sin(2 * pi * _moved.inMilliseconds / period.inMilliseconds);

    return Offset(_Drift.reach.dx * wave(_Drift.sideways), _Drift.reach.dy * wave(_Drift.upAndDown));
  }

  @override
  Widget build(BuildContext context) {
    // On the screen's whole pixels: between them, the cover and the text would be drawn blurred.
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final offset = widget.moving ? _offset * ratio : Offset.zero;

    return TweenAnimationBuilder(
      tween: Tween(end: Offset(offset.dx.roundToDouble(), offset.dy.roundToDouble()) / ratio),
      duration: widget.moving ? Duration.zero : _TelevisionControlsState._fade,
      curve: Curves.easeOut,
      builder: (context, offset, child) => Transform.translate(offset: offset, child: child),
      child: widget.child,
    );
  }
}

/// On a TV, the full-screen player's background: the color of the cover of what plays ([prominentColorOf]), dark in the
/// dark theme and light in the light one, for the theme's text to read on it, and darker toward the controls. It goes
/// from one song's color to the next's; meanwhile, and where there is no cover, the one before, or the theme's.
class CoverBackground extends StatefulWidget {
  const CoverBackground(this.coverArt, {required this.child, super.key});

  final String? coverArt;
  final Widget child;

  /// How long it takes to go from a color to the next.
  static const change = Duration(milliseconds: 800);

  /// The background for a cover of [color]: its hue, not too vivid, light or dark as the theme's background is.
  static Color backdrop(Color color, Brightness brightness) {
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withSaturation(min(hsl.saturation, 0.6))
        .withLightness(brightness == Brightness.dark ? 0.18 : 0.88)
        .toColor();
  }

  /// [backdrop] at the bottom: darker, for the controls, and the lyrics fading into it.
  static Color _bottom(Color backdrop, Brightness brightness) {
    final hsl = HSLColor.fromColor(backdrop);

    return hsl.withLightness(brightness == Brightness.dark ? hsl.lightness * 0.55 : hsl.lightness - 0.06).toColor();
  }

  @override
  State<CoverBackground> createState() => _CoverBackgroundState();
}

class _CoverBackgroundState extends State<CoverBackground> {
  /// The colors of the last few covers, by their ids: the player opened again on a song has its color at once.
  static final _known = <String, Color>{};

  /// How many covers' colors [_known] keeps.
  static const _remembered = 20;

  /// The cover [_color] is of, or being found out.
  String? _cover;
  Color? _color;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _find();
  }

  @override
  void didUpdateWidget(CoverBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _find();
  }

  /// Finds out the color of the cover of what plays, where it is another; the one before stays meanwhile.
  void _find() {
    final cover = widget.coverArt;

    if (cover == null || cover == _cover) {
      return;
    }

    _cover = cover;

    if (_known[cover] case final known?) {
      _color = known;
      return;
    }

    unawaited(
      Cover.prominentColor(context, cover, size: PlayerPage.coverSize.toInt()).then((color) {
        if (color == null) {
          return;
        }

        _known
          ..remove(cover)
          ..[cover] = color;

        if (_known.length > _remembered) {
          _known.remove(_known.keys.first);
        }

        if (mounted && _cover == cover) {
          setState(() => _color = color);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final color = _color;

    return TweenAnimationBuilder(
      tween: ColorTween(end: color == null ? theme.colorScheme.surface : CoverBackground.backdrop(color, brightness)),
      duration: CoverBackground.change,
      curve: Curves.easeInOut,
      builder: (context, backdrop, child) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backdrop!, CoverBackground._bottom(backdrop, brightness)],
          ),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Where the music plays, when that's another device, beside the controls.
class _PlayingOn extends StatelessWidget {
  const _PlayingOn(this.now, this.device, {required this.shown});

  final NowPlaying now;
  final String device;

  /// Whether the controls show: with them, on a pill of the theme's color; without, the words alone, faint, lined up
  /// with the cover and the times, for what plays to stand out.
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      // As the controls come and go: 1 with the pill, 0 without.
      child: TweenAnimationBuilder(
        tween: Tween<double>(end: shown ? 1 : 0),
        duration: _TelevisionControlsState._fade,
        builder: (context, pill, _) {
          final ink = Color.lerp(colors.onSurfaceVariant, colors.onPrimaryContainer, pill);

          return DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: colors.primaryContainer.a * pill),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12 * pill, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ThemedIcon(HugeIcons.strokeRoundedSpeaker, size: 18, color: ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      now.playing ? strings.playingOn(device) : strings.pausedOn(device),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: ink),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
