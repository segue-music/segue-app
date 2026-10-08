import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The top bar of a page whose name is by its picture on a wide screen (an album's, an artist's), where the page has a
/// bar of its own (on a phone, not under a top bar: `PageArea.holdsUnderTopBar`): the back arrow, where there is a page
/// to go back to, and the page's [title] in the middle, which stay as the page scrolls under them. In the page's color;
/// or, for a page that goes on under the bar ([Scaffold.extendBodyBehindAppBar]), with as much of that color as [shade]
/// says, as the page scrolls; the title then has a halo of it, which keeps it easy to read over what passes under it
/// while the bar has little of it.
class PageBar extends StatelessWidget implements PreferredSizeWidget {
  const PageBar({this.title, this.shade, super.key});

  /// The page's name, on one line, cut short where it's longer; none where the page shows it by its picture.
  final String? title;

  /// How much of the page's color the bar has, from none (0) to all of it (1); all of it where null.
  final ValueListenable<double>? shade;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final shade = this.shade;

    if (shade == null) {
      return _bar(context, 1);
    }

    return ValueListenableBuilder(valueListenable: shade, builder: (context, shade, _) => _bar(context, shade));
  }

  /// The bar, with [shade] of the page's color. The system's icons over it take their brightness from the color, the
  /// page's whatever of it there is.
  Widget _bar(BuildContext context, double shade) {
    final title = this.title;
    final surface = Theme.of(context).colorScheme.surface;
    return AppBar(
      backgroundColor: surface.withValues(alpha: shade),
      centerTitle: true,
      title: title == null
          ? null
          : Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: this.shade == null ? null : TextStyle(shadows: [Shadow(color: surface, blurRadius: 8)]),
            ),
      // As much room at the end as the arrow takes at the start, so that the title is in the middle of the page, not of
      // the room the arrow leaves.
      actions: const [SizedBox(width: kToolbarHeight)],
    );
  }
}

/// The bar of a page whose name is by its picture (an album's, an artist's) on a wide screen, under the home's top bar,
/// whose arrows go back: nothing while the picture shows; as it goes up past the top of the page, the page's [title],
/// after what plays it ([leading]: an album's play button), in the page's color, coming in as [shade] says, and staying
/// as the page scrolls on. The first of the page's slivers, over the top of the others: it takes none of their room,
/// but what the page brings into view, as the focus moves through it, stays clear of it, as of a pinned bar.
class PageBarSliver extends StatelessWidget {
  const PageBarSliver({required this.title, required this.shade, this.leading, super.key});

  final String title;

  /// How much of the bar shows, from none (0) to all of it (1): [shadeAt] the page's scroll.
  final ValueListenable<double> shade;

  final Widget? leading;

  /// How much of the bar shows with the page scrolled [offset] down, its picture's bottom [pictureBottom] from its top:
  /// none until that bottom is a bar's height below the bar's, all of it once it reaches the bar's bottom, the picture
  /// then all under the bar, and the name beside it gone.
  static double shadeAt(double offset, {required double pictureBottom}) =>
      ((offset - (pictureBottom - 2 * kToolbarHeight)) / kToolbarHeight).clamp(0, 1);

  // Nothing at all while it doesn't show, where the page under it takes taps. For the pointer only: the keyboard and
  // the remote go by the page's own buttons, at its top, as up the songs its [leading] would take the focus before the
  // song hidden under it, which the page then brings into view.
  @override
  Widget build(BuildContext context) => _OverlaySliver(
    child: ValueListenableBuilder(
      valueListenable: shade,
      builder: (context, shade, _) => shade == 0
          ? const SizedBox.shrink()
          : ExcludeFocus(
              child: Opacity(opacity: shade, child: _bar(context)),
            ),
    ),
  );

  /// The bar: [leading] and the title from the page's margin, as its picture and its songs; a line under them, as the
  /// side rail has beside the page.
  Widget _bar(BuildContext context) {
    final leading = this.leading;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: kToolbarHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (leading != null) ...[leading, const SizedBox(width: 12)],
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// A sliver that paints its child at the top of the viewport, over the slivers after it, which start where it does: it
/// takes none of the scroll view's room, but the viewport keeps what it brings into view clear of it
/// (`maxScrollObstructionExtent`), as of a pinned header.
class _OverlaySliver extends SingleChildRenderObjectWidget {
  const _OverlaySliver({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOverlaySliver();
}

class _RenderOverlaySliver extends RenderSliverSingleBoxAdapter {
  @override
  void performLayout() {
    final child = this.child;

    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }

    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = child.size.height;
    geometry = SliverGeometry(
      paintExtent: min(extent, constraints.remainingPaintExtent),
      layoutExtent: 0,
      maxPaintExtent: extent,
      maxScrollObstructionExtent: extent,
      hasVisualOverflow: true,
    );
  }

  // Where the viewport starts, however far it has scrolled.
  @override
  double childMainAxisPosition(RenderBox child) => 0;

  // Not scrolled by a screen reader's gestures, as a pinned header isn't.
  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.addTagForChildren(RenderViewport.excludeFromScrolling);
  }
}
