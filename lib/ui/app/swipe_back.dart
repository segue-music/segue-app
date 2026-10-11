import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// A page's transitions, [builder]'s, with a swipe to the right going back from it, as its back arrow does: from
/// anywhere on the page, rather than only from the screen's edge, as iOS's back swipe and Android's back gesture. The
/// page follows the finger, iOS's way while it does (the platform's own transition, on Android, would move it only a
/// little and fade it), the one under it showing beside it, and goes back once let go past the middle, or flung to the
/// right. Only a finger swipes it: a mouse drag selects, as ever.
///
/// What the page has that a swipe moves (a row that goes on sideways, a slider) moves as before: its own gesture wins.
/// Only a page that can go back has the swipe: one pushed over another ([TransitionRoute.popGestureEnabled]), on top.
class SwipeBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const SwipeBackPageTransitionsBuilder(this.builder);

  /// The transitions as the page opens and closes otherwise: the platform's own.
  final PageTransitionsBuilder builder;

  @override
  Duration get transitionDuration => builder.transitionDuration;

  @override
  Duration get reverseTransitionDuration => builder.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => builder.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _SwipeBack(
    route: route,
    // The pages of the navigator a swipe is in, the one swiped and the one under it, iOS's way.
    child: (route.popGestureInProgress ? const CupertinoPageTransitionsBuilder() : builder).buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    ),
  );
}

/// Takes [route] back as a finger swipes it to the right, as Flutter's iOS back swipe does from the screen's edge.
class _SwipeBack extends StatefulWidget {
  const _SwipeBack({required this.route, required this.child});

  final PageRoute<Object?> route;

  final Widget child;

  @override
  State<_SwipeBack> createState() => _SwipeBackState();
}

class _SwipeBackState extends State<_SwipeBack> {
  late final _drag = HorizontalDragGestureRecognizer(debugOwner: this, supportedDevices: {PointerDeviceKind.touch})
    ..onStart = _started
    ..onUpdate = _moved
    ..onEnd = _ended
    ..onCancel = _cancelled;

  /// The navigator of a swipe under way, which knows of it: its pages don't take a touch until it ends.
  NavigatorState? _swiping;

  /// How fast a swipe let go has to go, in screen widths a second, for where it went to decide whether the page goes
  /// back rather than how far it went: iOS's.
  static const _flingVelocity = 1.0;

  void _touched(PointerDownEvent event) {
    final route = widget.route;

    if (route.isCurrent && route.popGestureEnabled) {
      _drag.addPointer(event);
    }
  }

  void _started(DragStartDetails details) {
    _swiping = widget.route.navigator;
    widget.route.handleStartBackGesture(progress: 1);
  }

  void _moved(DragUpdateDetails details) {
    final route = widget.route;
    final progress = route.animation!.value - details.primaryDelta! / context.size!.width;
    route.handleUpdateBackGestureProgress(progress: clampDouble(progress, 0, 1));
  }

  void _ended(DragEndDetails details) {
    final route = widget.route;
    final navigator = _swiping!;
    _swiping = null;
    final velocity = details.velocity.pixelsPerSecond.dx / context.size!.width;
    final back = velocity.abs() >= _flingVelocity ? velocity > 0 : route.animation!.value < 0.5;

    if (!back || !route.isCurrent) {
      route.handleCancelBackGesture();
      return;
    }

    // Not with handleCommitBackGesture, which would take the page back where the swipe started first, for Android's
    // own back gesture: from where it is, as the finger left it.
    navigator.pop();
    final animation = route.animation!;

    if (!animation.isAnimating) {
      navigator.didStopUserGesture();
      return;
    }

    // Following the finger's line, rather than the transition's curve, until it is gone.
    late final AnimationStatusListener gone;
    gone = (_) {
      navigator.didStopUserGesture();
      animation.removeStatusListener(gone);
    };
    animation.addStatusListener(gone);
  }

  /// A touch that never became a swipe.
  void _cancelled() {
    if (_swiping != null) {
      _swiping = null;
      widget.route.handleCancelBackGesture();
    }
  }

  @override
  void dispose() {
    _drag.dispose();
    final navigator = _swiping;

    // Gone in the middle of a swipe, as the page is closed some other way: the navigator's pages take a touch again.
    if (navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) {
          navigator.didStopUserGesture();
        }
      });
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(onPointerDown: _touched, child: widget.child);
}
