import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Shows a change of theme as the app, as it was, fading away over the app in the new theme. On the way, from white to
/// black, it is gray: the fade goes fast through the middle and slow at its ends, so that the gray is a moment only.
/// Where the system asks for less motion, the new theme shows at once.
class ThemeFade extends StatefulWidget {
  const ThemeFade({required this.child, super.key});

  final Widget child;

  /// How long the old theme takes to fade away.
  static const duration = Duration(milliseconds: 300);

  /// The app as it was, over the new theme while it fades away.
  @visibleForTesting
  static const oldThemeKey = ValueKey('old theme');

  /// Fades the app, in the theme about to change, into the new one: to be called before the change, while the app
  /// still shows the old theme.
  static void start(BuildContext context) => context.findAncestorStateOfType<_ThemeFadeState>()?._start();

  @override
  State<ThemeFade> createState() => _ThemeFadeState();
}

class _ThemeFadeState extends State<ThemeFade> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final _controller = AnimationController(vsync: this, duration: ThemeFade.duration)
    ..addStatusListener((status) {
      if (status.isCompleted) {
        _clear();
      }
    });
  late final _opacity = CurvedAnimation(parent: ReverseAnimation(_controller), curve: Curves.easeInOut);

  /// The app as it was, as last painted, while it fades away.
  ui.Image? _old;

  void _start() {
    final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    if (boundary == null || !boundary.hasSize || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return;
    }

    // The app as last painted, which a debug build asserts is the app as it is: where something waits to be painted,
    // the new theme shows at once there.
    var painted = true;
    assert(() {
      painted = !boundary.debugNeedsPaint;

      return true;
    }());

    if (!painted) {
      return;
    }

    final old = boundary.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));

    _old?.dispose();
    setState(() => _old = old);
    _controller.forward(from: 0);
  }

  void _clear() {
    final old = _old;

    setState(() => _old = null);
    old?.dispose();
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    _old?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;

    return Stack(
      alignment: Alignment.topLeft,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (old != null)
          Positioned.fill(
            // Pointers go through to the app in the new theme, laid out as the old one was.
            child: IgnorePointer(
              child: FadeTransition(
                key: ThemeFade.oldThemeKey,
                opacity: _opacity,
                child: RawImage(image: old, fit: BoxFit.fill),
              ),
            ),
          ),
      ],
    );
  }
}
