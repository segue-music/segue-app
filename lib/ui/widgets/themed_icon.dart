import 'package:flutter/widgets.dart';
import 'package:hugeicons/hugeicons.dart';

/// One of Hugeicons' icons (`HugeIcons.strokeRounded...`): the SVG elements that draw it.
typedef HugeIconData = List<List<dynamic>>;

/// A Hugeicons icon that takes its size and color from the [IconTheme], as an [Icon] does: the app's one way of drawing
/// them. [HugeIcon] itself does too in hugeicons 1.2.0, the version the app takes; the one this was first written for
/// was 24 pixels wherever it was, in a button of 40 as in a label of 16.
class ThemedIcon extends StatelessWidget {
  const ThemedIcon(this.icon, {this.size, this.color, this.strokeWidth, super.key});

  final HugeIconData icon;

  /// The theme's when null.
  final double? size;

  /// The theme's when null.
  final Color? color;

  /// How thick its lines are, of the 24 it's drawn in; the icon's own when null, 1.5 for most.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) => HugeIcon(icon: icon, size: size, color: color, strokeWidth: strokeWidth);
}
