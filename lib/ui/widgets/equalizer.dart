import 'dart:math';

import 'package:flutter/material.dart';

/// What marks the song that plays, and the device that plays it: Hugeicons' audio wave
/// (`strokeRoundedAudioWave01`), drawn here so that its bars can rise and fall, as a music player's equalizer's do.
/// Still where the system asks for less motion. It takes its size and color from the [IconTheme], as a [ThemedIcon]
/// does; given a box larger than its size, as on a thumbnail's veil, it fills it, as the icon would.
class Equalizer extends StatefulWidget {
  const Equalizer({this.color, super.key});

  /// Whether equalizers move. The tests stop them (`flutter_test_config.dart`), since a page with one that moves
  /// never settles.
  @visibleForTesting
  static bool moves = true;

  /// The theme's when null.
  final Color? color;

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: _cycle);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  bool get _still => !Equalizer.moves || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final color = widget.color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: theme.size ?? 24,
        child: CustomPaint(
          painter: _EqualizerPainter(
            _still ? null : _controller,
            color: color.withValues(alpha: color.a * (theme.opacity ?? 1)),
          ),
        ),
      ),
    );
  }
}

/// One cycle of the controller, which holds a whole number of each bar's waves.
const _cycle = Duration(seconds: 3);

/// The icon's bars, in its 24 by 24 box: where each stands, half its length in the icon, how far from the middle it
/// reaches as it moves, and the two waves it moves by (how many in a cycle, and where in theirs each starts).
const _bars = [
  (x: 3.0, still: 1.0, reach: 4.0, waves: (3, 5), phases: (0.00, 0.60)),
  (x: 6.0, still: 5.0, reach: 7.0, waves: (4, 2), phases: (0.35, 0.10)),
  (x: 9.0, still: 9.0, reach: 9.0, waves: (2, 5), phases: (0.70, 0.40)),
  (x: 12.0, still: 6.0, reach: 8.0, waves: (5, 3), phases: (0.15, 0.80)),
  (x: 15.0, still: 3.0, reach: 6.0, waves: (3, 4), phases: (0.50, 0.20)),
  (x: 18.0, still: 5.0, reach: 7.0, waves: (4, 6), phases: (0.85, 0.55)),
  (x: 21.0, still: 1.0, reach: 4.0, waves: (2, 3), phases: (0.25, 0.90)),
];

class _EqualizerPainter extends CustomPainter {
  _EqualizerPainter(this.animation, {required this.color}) : super(repaint: animation);

  /// Null when it stands still.
  final Animation<double>? animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..translate(-12, -12);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final time = animation?.value;

    for (final bar in _bars) {
      final half = time == null ? bar.still : 1 + (bar.reach - 1) * _level(bar.waves, bar.phases, time);
      canvas.drawLine(Offset(bar.x, 12 - half), Offset(bar.x, 12 + half), paint);
    }
  }

  /// How high a bar is at [time] in the cycle, from 0 (a dot) to 1 (its reach): the sum of its two waves.
  static double _level((int, int) waves, (double, double) phases, double time) =>
      0.5 + sin(2 * pi * (waves.$1 * time + phases.$1)) / 4 + sin(2 * pi * (waves.$2 * time + phases.$2)) / 4;

  @override
  bool shouldRepaint(_EqualizerPainter old) => old.animation != animation || old.color != color;
}
