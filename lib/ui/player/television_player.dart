import 'dart:async';

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
import '../widgets/themed_icon.dart';
import 'devices_sheet.dart';
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
                        Expanded(flex: 3, child: device == null ? const SizedBox.shrink() : _PlayingOn(now, device)),
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
    );
  }
}

/// Where the music plays, when that's another device, beside the controls.
class _PlayingOn extends StatelessWidget {
  const _PlayingOn(this.now, this.device);

  final NowPlaying now;
  final String device;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThemedIcon(HugeIcons.strokeRoundedSpeaker, size: 18, color: colors.onPrimaryContainer),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  now.playing ? strings.playingOn(device) : strings.pausedOn(device),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.onPrimaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
