import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../connect/connect.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../widgets/themed_icon.dart';
import 'player_controls.dart';

/// The volume of the device the app controls, at the end of the player bar on a computer: a button that mutes it, or
/// gives it back the volume it had, and over it, as the pointer comes to it or the keyboard's focus, a slider, upright,
/// which stays while the pointer is on either, or drags it. The mouse's wheel moves the volume over either, and the
/// keyboard's up and down arrows on the button. This device's volume follows the slider as it moves; another device's
/// takes it as it stops, a moment after its last step (the drag let go, the wheel or the keys still), rather than a
/// command for each step on the way.
class VolumeControl extends StatefulWidget {
  const VolumeControl(this.now, {super.key});

  final NowPlaying now;

  /// Whether the platform has it: a computer. A phone's buttons, and a TV remote's, set the system's volume.
  static bool get shown => switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => true,
    _ => false,
  };

  /// How much a notch of the mouse's wheel, or an arrow, moves the volume.
  static const step = 5;

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> with SingleTickerProviderStateMixin {
  /// The volume shown in place of the device's: while it moves, and after, until the device has it (another device's
  /// comes with its next report).
  int? _held;

  /// The volume as it started moving, which unmuting gives back where it moved down to none.
  int? _from;

  bool _dragging = false;

  /// A moment after the last step, when the volume stops moving.
  Timer? _stop;
  Timer? _letGo;

  final _slider = OverlayPortalController();
  final _button = LayerLink();

  // What keeps the slider open: the pointer on the button or on it, a drag, or the button's focus.
  bool _overButton = false;
  bool _overSlider = false;
  bool _focused = false;

  /// A moment after none keeps it open, when the slider closes: time for the pointer to go from the button to it.
  Timer? _close;

  /// How far open the slider is: as it opens, it grows up out of the button, from a circle over it, and shows; as it
  /// closes, back. Closed, it goes.
  late final _opening =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 200),
        reverseDuration: const Duration(milliseconds: 150),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          _slider.hide();
        }
      });
  late final _openness = CurvedAnimation(
    parent: _opening,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  static final _height = Tween<double>(begin: 40, end: 140);

  @override
  void dispose() {
    _stop?.cancel();
    _letGo?.cancel();
    _close?.cancel();
    _openness.dispose();
    _opening.dispose();
    super.dispose();
  }

  /// Opens the slider, or closes it a moment after nothing keeps it open.
  void _openOrClose() {
    if (_overButton || _overSlider || _dragging || _focused) {
      _close?.cancel();
      _close = null;
      _slider.show();
      unawaited(_opening.forward());
      return;
    }

    _close ??= Timer(const Duration(milliseconds: 300), () {
      _close = null;
      unawaited(_opening.reverse());
    });
  }

  int get _volume => _held ?? widget.now.volume;

  ConnectController get _connect => ServicesScope.of(context).connect;

  /// Shows [volume], and sets it if it plays here.
  void _move(int volume) {
    _from ??= _volume;
    _waitForStop();

    if (volume == _volume) {
      return;
    }

    setState(() => _held = volume);

    if (widget.now.device == null) {
      unawaited(runCommand(context, () => _connect.setVolume(volume)));
    }
  }

  /// The volume stops moving a moment after its last step, unless a drag holds it.
  void _waitForStop() {
    _letGo?.cancel();
    _stop?.cancel();
    _stop = Timer(const Duration(milliseconds: 300), () {
      if (!_dragging) {
        _stopped();
      }
    });
  }

  /// The volume stopped moving: it goes to the device, wherever it plays, and the device's shows again once it has it.
  void _stopped() {
    final volume = _held;
    final from = _from;
    _from = null;
    _stop?.cancel();

    if (volume == null || !mounted) {
      return;
    }

    unawaited(runCommand(context, () => _connect.setVolume(volume, from: from)));
    _letGo = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _held = null);
      }
    });
  }

  void _scrolled(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !widget.now.canSetVolume) {
      return;
    }

    // Over the bar alone: should it ever be in something that scrolls, that doesn't scroll too.
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final down = (event as PointerScrollEvent).scrollDelta.dy;

      if (down != 0) {
        _move((_volume + (down < 0 ? VolumeControl.step : -VolumeControl.step)).clamp(0, 100));
      }
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final louder = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => true,
      LogicalKeyboardKey.arrowDown => false,
      _ => null,
    };

    if (louder == null || event is KeyUpEvent || !widget.now.canSetVolume) {
      return KeyEventResult.ignored;
    }

    _move((_volume + (louder ? VolumeControl.step : -VolumeControl.step)).clamp(0, 100));

    return KeyEventResult.handled;
  }

  void _toggleMute() {
    // A move that hasn't stopped yet goes first: where it went down to none, unmuting gives back the volume before it.
    if (_stop?.isActive ?? false) {
      _stopped();
    }

    final muted = _volume == 0;
    _letGo?.cancel();
    setState(() => _held = _from = null);
    unawaited(runCommand(context, muted ? _connect.unmute : () => _connect.setVolume(0)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final now = widget.now;

    if (_held == now.volume && !_dragging && _from == null) {
      _held = null; // the device has it
    }

    final volume = _volume;

    return Listener(
      onPointerSignal: _scrolled,
      child: CompositedTransformTarget(
        link: _button,
        child: OverlayPortal(
          controller: _slider,
          overlayChildBuilder: _buildSlider,
          child: MouseRegion(
            onEnter: (_) {
              _overButton = true;
              _openOrClose();
            },
            onExit: (_) {
              _overButton = false;
              _openOrClose();
            },
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) {
                _focused = focused;
                _openOrClose();
              },
              onKeyEvent: _key,
              // No tooltip, which would cover the slider: its words for a screen reader alone.
              child: MergeSemantics(
                child: Semantics(
                  label: volume == 0 ? strings.unmute : strings.mute,
                  child: IconButton(
                    icon: ThemedIcon(switch (volume) {
                      0 => HugeIcons.strokeRoundedVolumeOff,
                      < 50 => HugeIcons.strokeRoundedVolumeLow,
                      _ => HugeIcons.strokeRoundedVolumeHigh,
                    }),
                    onPressed: now.canSetVolume ? _toggleMute : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The slider, upright over the button, as tall as three of the bar's buttons once open.
  Widget _buildSlider(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final enabled = widget.now.canSetVolume;
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;

    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _button,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topCenter,
        followerAnchor: Alignment.bottomCenter,
        child: MouseRegion(
          onEnter: (_) {
            _overSlider = true;
            _openOrClose();
          },
          onExit: (_) {
            _overSlider = false;
            _openOrClose();
          },
          child: Listener(
            onPointerSignal: _scrolled,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: AnimatedBuilder(
                animation: _openness,
                builder: (context, slider) => Opacity(
                  opacity: _openness.value,
                  child: Material(
                    color: color,
                    elevation: 3,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(width: 40, height: _height.evaluate(_openness), child: slider),
                  ),
                ),
                // The slider on its side, its start at the bottom, as tall as it is once open: the room around it
                // shows more of it as it grows, rather than squeezing its track.
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  maxHeight: _height.end,
                  child: SizedBox(
                    height: _height.end,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: thinSliderTheme(context),
                        child: Semantics(
                          label: strings.volume,
                          child: Slider(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            max: 100,
                            value: _volume.toDouble(),
                            semanticFormatterCallback: (value) => strings.volumeLevel(value.round()),
                            onChangeStart: enabled ? (_) => _dragging = true : null,
                            onChanged: enabled ? (value) => _move(value.round()) : null,
                            onChangeEnd: enabled
                                ? (_) {
                                    _dragging = false;
                                    _waitForStop();
                                    _openOrClose();
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
