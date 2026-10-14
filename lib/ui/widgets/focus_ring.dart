import 'package:flutter/material.dart';

import 'directional_navigation.dart';

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

  /// On a TV, the room a card grows into above and below and its ring in view too, with some room around them, once the
  /// focus has scrolled the card itself into view: a card at the screen's bottom grew past it, its ring cut off. Not
  /// sideways: a row of cards keeps the one with the focus in its first one's place (`TileRow`), and a grid doesn't
  /// scroll that way.
  void _showGrown() {
    if (!widget.grows || !context.television) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = mounted ? context.findRenderObject() : null;

      if (!_focused || box is! RenderBox || !box.hasSize) {
        return;
      }

      final grown = box.size.height * (FocusRing.grownScale - 1) / 2;
      box.showOnScreen(
        rect: EdgeInsets.symmetric(vertical: grown + _roomAround).inflateRect(Offset.zero & box.size),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  /// How far a grown card's ring stays from the screen's edges.
  static const _roomAround = 8.0;

  @override
  Widget build(BuildContext context) {
    final shown = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final grown = shown && widget.grows && context.television;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        setState(() => _focused = focused);

        if (focused) {
          _showGrown();
        }
      },
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
