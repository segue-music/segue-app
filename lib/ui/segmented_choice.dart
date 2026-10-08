import 'package:flutter/material.dart';

import 'focus_ring.dart';
import 'themed_icon.dart';

/// A choice of a few [options], side by side in a pill-shaped track, the one [selected] under a thumb that slides to
/// another as it's picked: for a page's two or three views of one thing, as an artist's songs or the library's artists.
/// More, as the albums' orders, are chips (`OrderChips`), which scroll sideways where they don't fit. The options are
/// as wide as the widest, so that the thumb keeps its size on the way; where the system asks for less motion, it moves
/// at once. They say themselves in words, or with an [icon] each.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice(
    this.selected, {
    required this.options,
    required this.label,
    required this.onSelected,
    this.icon,
    super.key,
  });

  /// The one picked.
  final T selected;

  final List<T> options;

  /// What an option says of itself.
  final String Function(T option) label;

  /// What an option shows instead of its [label], which is then its tooltip, and what a screen reader says of it.
  final HugeIconData Function(T option)? icon;

  final ValueChanged<T> onSelected;

  /// How long the thumb takes from one option to another.
  static const duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : SegmentedChoice.duration;
    final index = options.indexOf(selected);
    return IntrinsicWidth(
      child: DecoratedBox(
        decoration: ShapeDecoration(color: colors.surfaceContainerHigh, shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              // As tall as the options, and as wide as one of them, from the first one's place to the last one's.
              Positioned.fill(
                child: AnimatedAlign(
                  alignment: Alignment(options.length > 1 ? 2 * index / (options.length - 1) - 1 : 0, 0),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: FractionallySizedBox(
                    widthFactor: 1 / options.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(color: colors.primary, shape: const StadiumBorder()),
                    ),
                  ),
                ),
              ),
              // Over the thumb, where the ink of a tap, a hover and the focus shows on it too.
              Material(
                type: MaterialType.transparency,
                child: Row(
                  children: [
                    for (final option in options)
                      Expanded(
                        child: Semantics(
                          container: true,
                          button: true,
                          selected: option == selected,
                          inMutuallyExclusiveGroup: true,
                          child: _option(context, option, duration),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// An option, over the thumb where it's [selected], its words or its icon in the color they have on it; taking
  /// [duration] to change it.
  Widget _option(BuildContext context, T option, Duration duration) {
    final colors = Theme.of(context).colorScheme;
    final color = option == selected ? colors.onPrimary : colors.onSurfaceVariant;
    final icon = this.icon;
    // On the thumb the theme's focus tint, in its color, wouldn't show.
    final button = FocusRing(
      borderRadius: const BorderRadius.all(Radius.circular(100)),
      child: InkWell(
        onTap: () => onSelected(option),
        customBorder: const StadiumBorder(),
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Center(
            child: icon == null
                ? AnimatedDefaultTextStyle(
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(color: color),
                    duration: duration,
                    child: Text(label(option), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
                  )
                // As tall as the words' line.
                : TweenAnimationBuilder(
                    tween: ColorTween(end: color),
                    duration: duration,
                    builder: (context, color, _) => ThemedIcon(icon(option), size: 20, color: color),
                  ),
          ),
        ),
      ),
    );
    return icon == null ? button : Tooltip(message: label(option), child: button);
  }
}
