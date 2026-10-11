import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'focus_ring.dart';
import 'themed_icon.dart';

/// A choice of a few [options], side by side in a pill-shaped button, the one [selected] under a thumb as tall as the
/// button: for a page's two views of one thing, as an artist's songs or their albums. A tap anywhere on it picks the
/// next option, and the thumb slides to it, from the last back to the first, so that with two each tap goes from one to
/// the other. More, as the library's albums' and artists' orders, are chips (`OrderChips`), which pick any at once and
/// scroll sideways where they don't fit. Each option is as wide as it asks, as a chip is, and the thumb takes the width of the one it goes to on
/// the way; where the system asks for less motion, it moves at once. They say themselves in words, or with an [icon]
/// each.
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

  /// What an option shows instead of its [label], which is then its tooltip.
  final HugeIconData Function(T option)? icon;

  final ValueChanged<T> onSelected;

  /// How long the thumb takes from one option to another.
  static const duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : SegmentedChoice.duration;
    final index = options.indexOf(selected);
    // The same widgets on every frame of the thumb's way, which then aren't built again.
    final children = [
      // On the material's ink, under that of a tap, a hover and the focus.
      Ink(
        decoration: ShapeDecoration(color: colors.primary, shape: const StadiumBorder()),
      ),
      for (final option in options) _option(context, option, duration),
    ];

    // On the thumb the theme's focus tint, in its color, would hardly show.
    return FocusRing(
      borderRadius: const BorderRadius.all(Radius.circular(100)),
      // A button that says the option picked, a screen reader's tap picking the next as a finger's does.
      child: Semantics(
        container: true,
        button: true,
        label: label(selected),
        child: Material(
          color: colors.surfaceContainerHigh,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: () => onSelected(options[(index + 1) % options.length]),
            customBorder: const StadiumBorder(),
            mouseCursor: WidgetStateMouseCursor.clickable,
            child: ExcludeSemantics(
              child: TweenAnimationBuilder(
                tween: Tween(end: index.toDouble()),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, position, _) => _Options(thumbPosition: position, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// An option, its words or its icon in the color they have on the thumb where it's [selected]; taking [duration] to
  /// change it.
  Widget _option(BuildContext context, T option, Duration duration) {
    final colors = Theme.of(context).colorScheme;
    final color = option == selected ? colors.onPrimary : colors.onSurfaceVariant;
    final icon = this.icon;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
    );

    return icon == null ? content : Tooltip(message: label(option), child: content);
  }
}

/// The thumb, then the options, side by side, each as wide as it asks and all as tall as the tallest, where they fit;
/// where they don't, the narrow ones as wide as they ask and the others sharing the room left. The thumb is as tall as
/// they are and under the option at [thumbPosition], or, between two, as far along from one's place and width to the
/// other's.
class _Options extends MultiChildRenderObjectWidget {
  const _Options({required this.thumbPosition, required super.children});

  /// Where the thumb is: the index of the option it's under, or a fraction of the way between two.
  final double thumbPosition;

  @override
  _RenderOptions createRenderObject(BuildContext context) => _RenderOptions(thumbPosition);

  @override
  void updateRenderObject(BuildContext context, _RenderOptions renderObject) =>
      renderObject.thumbPosition = thumbPosition;
}

class _OptionParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderOptions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _OptionParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _OptionParentData> {
  _RenderOptions(this._thumbPosition);

  double get thumbPosition => _thumbPosition;
  double _thumbPosition;

  set thumbPosition(double value) {
    if (value != _thumbPosition) {
      _thumbPosition = value;
      markNeedsLayout();
    }
  }

  RenderBox get _thumb => firstChild!;

  List<RenderBox> get _options => getChildrenAsList().sublist(1);

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OptionParentData) {
      child.parentData = _OptionParentData();
    }
  }

  /// The options' sizes in [constraints], each laid out by [layoutChild].
  List<Size> _sizes(BoxConstraints constraints, ChildLayouter layoutChild) {
    final options = _options;
    final loose = constraints.loosen();
    final sizes = [for (final option in options) layoutChild(option, loose)];
    final widths = [for (final size in sizes) size.width];

    if (widths.fold(0.0, (sum, width) => sum + width) <= constraints.maxWidth) {
      return sizes;
    }

    // The narrowest keep their width as long as the others can share what's left of the room equally.
    var room = constraints.maxWidth;
    var sharing = widths.length;

    for (final width in widths.toList()..sort()) {
      if (width > room / sharing) {
        break;
      }

      room -= width;
      sharing--;
    }

    final share = room / sharing;

    return [
      for (final (i, size) in sizes.indexed)
        size.width <= share ? size : layoutChild(options[i], loose.copyWith(maxWidth: share)),
    ];
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final sizes = _sizes(constraints, ChildLayoutHelper.dryLayoutChild);

    return constraints.constrain(
      Size(
        sizes.fold(0.0, (sum, size) => sum + size.width),
        sizes.fold(0.0, (height, size) => max(height, size.height)),
      ),
    );
  }

  @override
  void performLayout() {
    final sizes = _sizes(constraints, ChildLayoutHelper.layoutChild);
    final height = sizes.fold(0.0, (height, size) => max(height, size.height));
    final places = <Rect>[];
    var left = 0.0;

    for (final (i, option) in _options.indexed) {
      (option.parentData! as _OptionParentData).offset = Offset(left, (height - sizes[i].height) / 2);
      places.add(Rect.fromLTWH(left, 0, sizes[i].width, height));
      left += sizes[i].width;
    }

    size = constraints.constrain(Size(left, height));

    if (places.isEmpty) {
      _thumb.layout(BoxConstraints.tight(Size.zero));
      return;
    }

    final position = thumbPosition.clamp(0.0, places.length - 1.0);
    final from = position.floor();
    final place = Rect.lerp(places[from], places[min(from + 1, places.length - 1)], position - from)!;
    _thumb.layout(BoxConstraints.tight(place.size));
    (_thumb.parentData! as _OptionParentData).offset = place.topLeft;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _options.fold(0.0, (sum, option) => sum + option.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _options.fold(0.0, (sum, option) => sum + option.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _options.fold(0.0, (height, option) => max(height, option.getMinIntrinsicHeight(double.infinity)));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _options.fold(0.0, (height, option) => max(height, option.getMaxIntrinsicHeight(double.infinity)));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
