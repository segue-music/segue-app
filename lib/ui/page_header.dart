import 'package:flutter/material.dart';

import 'page_area.dart';

/// The top of a page whose name is by its picture (an album's, an artist's), beside the back arrow where the page has
/// one of its own (on a phone): in the room a top bar would take, which had nothing but the arrow. The page's bar
/// ([bar]) then has no height. Under a wide screen's top bar, whose arrow goes back, the page has neither.
class PageHeader extends StatelessWidget {
  const PageHeader({required this.child, this.centered = false, super.key});

  /// The header, from the arrow or the page's margin on the left, with whatever room it needs on its other sides; or,
  /// [centered], in the middle of the page.
  final Widget child;

  /// Whether [child] is centered on the page, between the room the arrow takes and as much on the other side, the
  /// arrow beside its top.
  final bool centered;

  /// The page's top bar, where it has one of its own: while the header doesn't show yet ([shown]), as the page's
  /// content comes or when it fails, the usual one, with the back arrow; then one of no height, which only gives the
  /// system's bar at the top of the screen the page's color. Or, [seeThrough], it lets the page show there instead, as
  /// an artist's picture at its top does: for a page that goes on under it ([Scaffold.extendBodyBehindAppBar]).
  static PreferredSizeWidget? bar(BuildContext context, {required bool shown, bool seeThrough = false}) {
    if (PageArea.holdsUnderTopBar(context)) {
      return null;
    }

    if (!shown) {
      return AppBar();
    }

    // The page's color with none of it: the system's icons take their brightness from the color, which the page has
    // under them.
    final clear = Theme.of(context).colorScheme.surface.withValues(alpha: 0);
    return AppBar(toolbarHeight: 0, automaticallyImplyLeading: false, backgroundColor: seeThrough ? clear : null);
  }

  @override
  Widget build(BuildContext context) {
    // As a top bar has it: only where there is a page to go back to.
    final arrow = !PageArea.holdsUnderTopBar(context) && (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    // Where a top bar would have it, in its color.
    final back = SizedBox.square(
      dimension: kToolbarHeight,
      child: Center(child: BackButton(color: Theme.of(context).colorScheme.onSurface)),
    );

    if (centered) {
      return Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kToolbarHeight),
            child: Center(child: child),
          ),
          if (arrow) back,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (arrow) back else const SizedBox(width: 16),
        Expanded(child: child),
      ],
    );
  }
}
