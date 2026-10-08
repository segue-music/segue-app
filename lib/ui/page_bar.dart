import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
