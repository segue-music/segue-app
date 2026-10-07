import 'package:flutter/material.dart';

import 'page_area.dart';

/// The top of a page whose name is by its picture (an album's, an artist's), beside the back arrow where the page has
/// one of its own (on a phone): in the room a top bar would take, which had nothing but the arrow. The page's bar
/// ([bar]) then has no height. Under a wide screen's top bar, whose arrow goes back, the page has neither.
class PageHeader extends StatelessWidget {
  const PageHeader({required this.child, super.key});

  /// The header, from the arrow or the page's margin on the left, with whatever room it needs on its other sides.
  final Widget child;

  /// The page's top bar, where it has one of its own: while the header doesn't show yet ([shown]), as the page's
  /// content comes or when it fails, the usual one, with the back arrow; then one of no height, which only keeps the
  /// page clear of the system's bar at the top of the screen.
  static PreferredSizeWidget? bar(BuildContext context, {required bool shown}) {
    if (PageArea.holdsUnderTopBar(context)) {
      return null;
    }

    return shown ? AppBar(toolbarHeight: 0, automaticallyImplyLeading: false) : AppBar();
  }

  @override
  Widget build(BuildContext context) {
    // As a top bar has it: only where there is a page to go back to.
    final arrow = !PageArea.holdsUnderTopBar(context) && (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Where a top bar would have it, in its color.
        if (arrow)
          SizedBox.square(
            dimension: kToolbarHeight,
            child: Center(child: BackButton(color: Theme.of(context).colorScheme.onSurface)),
          )
        else
          const SizedBox(width: 16),
        Expanded(child: child),
      ],
    );
  }
}
