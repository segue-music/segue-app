import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../equalizer_choice.dart';
import '../../l10n/app_localizations.dart';
import '../app/page_area.dart';
import '../widgets/directional_navigation.dart';

/// The equalizer of this device's player: on or off, and its curve, one of those made for a kind of music, as chips,
/// or the user's own, by moving the bands, side by side under them, each a slider up and down. Moving one makes the
/// curve shown the user's own. While off, the curve stays in sight, faded, and nothing in it can be picked. In the
/// page area, from the settings.
class EqualizerPage extends StatelessWidget {
  const EqualizerPage({required this.choice, super.key});

  final EqualizerChoice choice;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
        automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
        title: Text(strings.equalizer),
      ),
      body: ListenableBuilder(
        listenable: choice,
        builder: (context, _) {
          final settings = choice.value;

          return ListView(
            // At the end, clear of the bars a phone's home has over it.
            padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              SwitchListTile(title: Text(strings.useEqualizer), value: settings.on, onChanged: choice.setOn),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in EqualizerPreset.values)
                      ChoiceChip(
                        label: Text(strings.equalizerPreset(preset.name)),
                        selected: preset == settings.preset,
                        onSelected: settings.on ? (_) => choice.pick(preset) : null,
                        mouseCursor: WidgetStateMouseCursor.clickable,
                      ),
                  ],
                ),
              ),
              // No wider than a phone's, on a wide screen: the bands' sliders an arm's length apart there would be
              // a stretch to read across.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        for (final (i, frequency) in equalizerFrequencies.indexed)
                          Expanded(
                            child: EqualizerBand(
                              frequency: frequency,
                              gain: settings.gains[i],
                              onChanged: settings.on ? (gain) => choice.setGain(i, gain) : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One of the equalizer's bands: its gain, in dB, over a slider up and down, from [maxBandGain] below to as much
/// above, a line from zero to its thumb, and its frequency under it. A tap or a drag moves it, in whole dB, and a double
/// tap takes it back to 0 dB; the keyboard's up and down move it too while it has the focus, and left and right go on to
/// the band beside it. On a TV, where the D-pad
/// has only those four, up and down move the focus too, to the chips above, until the center button takes the band:
/// they move it then, until the button again, or the focus leaves it. Its own, rather than Material's slider turned
/// upright, which takes up and down only as the keyboard's, and left and right on a TV.
class EqualizerBand extends StatefulWidget {
  const EqualizerBand({required this.frequency, required this.gain, required this.onChanged, super.key});

  /// Its center frequency, in Hz.
  final int frequency;

  final int gain;

  /// Null while it can't move: the equalizer is off.
  final ValueChanged<int>? onChanged;

  /// How tall its slider's track is.
  static const trackHeight = 180.0;

  @override
  State<EqualizerBand> createState() => _EqualizerBandState();
}

class _EqualizerBandState extends State<EqualizerBand> {
  // Whether its focus shows: it has it, from the keyboard or a remote.
  bool _highlighted = false;

  // On a TV, whether the center button took it, for up and down to move it.
  bool _taken = false;

  // Its gain, as it last moved it: keys pressed one after another, before the page shows the first, go on from there.
  late int _gain = widget.gain;

  // Room over and under the track, for the thumb at either end.
  static const _margin = 12.0;

  // Where the last tap was, while a second near it makes a double tap; and until when. GestureDetector's own double tap
  // would hold every tap back until no second came, before moving the band. Flutter's counts from one tap's lift to the
  // next one's press; this, to the next one's lift, a press later.
  Offset? _lastTap;
  Timer? _doubleTapTimer;
  static final _doubleTapTimeout = kDoubleTapTimeout + kPressTimeout;

  @override
  void didUpdateWidget(EqualizerBand old) {
    super.didUpdateWidget(old);
    _gain = widget.gain;
  }

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    super.dispose();
  }

  /// Whether up and down move it, rather than the focus: always, but on a TV until the center button takes it.
  bool get _keysMove => widget.onChanged != null && (_taken || !context.television);

  void _move(int gain) {
    final clamped = gain.clamp(-maxBandGain, maxBandGain);

    if (clamped != _gain) {
      _gain = clamped;
      widget.onChanged?.call(clamped);
    }
  }

  /// A tap at [position], from the band's top: to the gain there, or, right after another near it, back to 0 dB.
  void _tapped(Offset position) {
    final last = _lastTap;
    _doubleTapTimer?.cancel();

    if (last != null && (position - last).distance <= kDoubleTapSlop) {
      _lastTap = null;
      _move(0);
      return;
    }

    _lastTap = position;
    _doubleTapTimer = Timer(_doubleTapTimeout, () => _lastTap = null);
    _moveTo(position.dy - _sliderTop);
  }

  /// To the gain at [y], from the top of the slider.
  void _moveTo(double y) {
    final fraction = ((y - _margin) / EqualizerBand.trackHeight).clamp(0.0, 1.0);
    _move((maxBandGain - fraction * 2 * maxBandGain).round());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = widget.onChanged != null;
    final gain = widget.gain;
    final frequency = widget.frequency;
    final label = theme.textTheme.labelSmall?.copyWith(
      color: enabled ? colors.onSurfaceVariant : colors.onSurface.withValues(alpha: 0.38),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      slider: true,
      enabled: enabled,
      label: frequency < 1000 ? strings.hertz(frequency) : strings.kilohertz(frequency ~/ 1000),
      value: strings.decibels(_signed(gain)),
      increasedValue: gain < maxBandGain ? strings.decibels(_signed(gain + 1)) : null,
      decreasedValue: gain > -maxBandGain ? strings.decibels(_signed(gain - 1)) : null,
      onIncrease: enabled && gain < maxBandGain ? () => _move(_gain + 1) : null,
      onDecrease: enabled && gain > -maxBandGain ? () => _move(_gain - 1) : null,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (shown) => setState(() => _highlighted = shown),
        onFocusChange: (focused) {
          if (!focused) {
            setState(() => _taken = false);
          }
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(-1),
        },
        actions: {
          _MoveIntent: _MoveAction(this),
          // The center button, or Enter, takes it and lets it go.
          if (context.television)
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => setState(() => _taken = !_taken)),
        },
        child: ExcludeSemantics(
          child: GestureDetector(
            onTapUp: enabled ? (details) => _tapped(details.localPosition) : null,
            onVerticalDragStart: enabled ? (details) => _moveTo(details.localPosition.dy - _sliderTop) : null,
            onVerticalDragUpdate: enabled ? (details) => _moveTo(details.localPosition.dy - _sliderTop) : null,
            // Always the same tree, the tint coming and going with the focus.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _highlighted ? theme.focusColor : null,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    SizedBox(
                      height: _labelHeight,
                      child: Center(
                        child: Text(
                          _signed(gain),
                          style: _taken ? label?.copyWith(color: colors.primary, fontWeight: FontWeight.bold) : label,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: EqualizerBand.trackHeight + 2 * _margin,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _BandPainter(
                          gain: gain,
                          margin: _margin,
                          track: colors.surfaceContainerHighest,
                          zero: colors.outline,
                          // Faded while off, but opaque: the track under the thumb doesn't show through.
                          fill: enabled
                              ? colors.primary
                              : Color.alphaBlend(colors.onSurface.withValues(alpha: 0.38), colors.surface),
                          ring: _taken ? colors.onSurface : null,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: _labelHeight,
                      child: Center(
                        child: Text(
                          frequency < 1000 ? '$frequency' : strings.kilohertzShort(frequency ~/ 1000),
                          style: label,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The room each label takes, over and under the slider; the slider's top, from the band's.
  static const _labelHeight = 20.0;
  static const _sliderTop = 8 + _labelHeight;

  /// [gain] with its sign: +3, 0, −3.
  static String _signed(int gain) => gain > 0 ? '+$gain' : (gain < 0 ? '−${-gain}' : '0');
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.decibels);

  final int decibels;
}

/// Moves the band by a key, up or down, while keys move it; otherwise the key goes on, to move the focus.
class _MoveAction extends Action<_MoveIntent> {
  _MoveAction(this._band);

  final _EqualizerBandState _band;

  @override
  bool isEnabled(_MoveIntent intent) => _band._keysMove;

  @override
  void invoke(_MoveIntent intent) => _band._move(_band._gain + intent.decibels);
}

/// A band's slider: its [track], up and down, with a mark at [zero], the line from there to its thumb in [fill], and
/// the thumb, with a [ring] around it, larger, while a TV's center button has taken the band.
class _BandPainter extends CustomPainter {
  _BandPainter({
    required this.gain,
    required this.margin,
    required this.track,
    required this.zero,
    required this.fill,
    required this.ring,
  });

  final int gain;
  final double margin;
  final Color track;
  final Color zero;
  final Color fill;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final height = size.height - 2 * margin;
    double at(int gain) => margin + (maxBandGain - gain) / (2 * maxBandGain) * height;

    final line = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset(x, at(maxBandGain)), Offset(x, at(-maxBandGain)), line..color = track)
      ..drawLine(
        Offset(x - 7, at(0)),
        Offset(x + 7, at(0)),
        line
          ..strokeWidth = 2
          ..color = zero,
      );

    if (gain != 0) {
      canvas.drawLine(
        Offset(x, at(0)),
        Offset(x, at(gain)),
        line
          ..strokeWidth = 4
          ..color = fill,
      );
    }

    final ring = this.ring;
    final thumb = Offset(x, at(gain));

    if (ring != null) {
      canvas.drawCircle(thumb, 13, Paint()..color = ring);
    }

    canvas.drawCircle(thumb, ring != null ? 10 : 8, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.gain != gain ||
      old.margin != margin ||
      old.track != track ||
      old.zero != zero ||
      old.fill != fill ||
      old.ring != ring;
}
