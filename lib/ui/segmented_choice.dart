import 'package:flutter/material.dart';

import 'focus_ring.dart';

/// A choice of a few [options], side by side in a pill-shaped track, the one [selected] under a thumb that slides to
/// another as it's picked: for a page's views of one thing, where chips would read as orders or filters. The options
/// are as wide as the widest, so that the thumb keeps its size on the way; where the system asks for less motion, it
/// moves at once.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice(
    this.selected, {
    required this.options,
    required this.label,
    required this.onSelected,
    super.key,
  });

  /// The one picked.
  final T selected;

  final List<T> options;

  /// What an option says of itself.
  final String Function(T option) label;

  final ValueChanged<T> onSelected;

  /// How long the thumb takes from one option to another.
  static const duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
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
                          // On the thumb the theme's focus tint, in its color, wouldn't show.
                          child: FocusRing(
                            borderRadius: const BorderRadius.all(Radius.circular(100)),
                            child: InkWell(
                              onTap: () => onSelected(option),
                              customBorder: const StadiumBorder(),
                              mouseCursor: WidgetStateMouseCursor.clickable,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Center(
                                  child: AnimatedDefaultTextStyle(
                                    style: text.labelLarge!.copyWith(
                                      color: option == selected ? colors.onPrimary : colors.onSurfaceVariant,
                                    ),
                                    duration: duration,
                                    child: Text(
                                      label(option),
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
}
