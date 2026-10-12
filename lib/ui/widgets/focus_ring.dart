import 'package:flutter/material.dart';

/// A ring around [child] while something in it has the focus, when the keyboard or a remote drives
/// the app (not a touch or a mouse). For tiles whose image would hide the theme's focus tint, which
/// is painted under it. On a TV, a card ([grows]) grows a little with it too, as Google TV's do, for the focus to
/// show from across the room.
class FocusRing extends StatefulWidget {
  const FocusRing({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.grows = false,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Whether [child] is a card (an album's, an artist's, a mix's), which grows with the focus on a TV.
  final bool grows;

  /// How much a card grows.
  static const grownScale = 1.06;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode mode) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final shown = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final grown = shown && widget.grows && MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      // Always the same tree, the border coming and going, the card growing and shrinking: putting the box in only
      // with the focus would rebuild the child, whose focus would then be lost as soon as it got there.
      child: AnimatedScale(
        scale: grown ? FocusRing.grownScale : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: shown
              ? BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3),
                  borderRadius: widget.borderRadius,
                )
              : const BoxDecoration(),
          child: widget.child,
        ),
      ),
    );
  }
}
