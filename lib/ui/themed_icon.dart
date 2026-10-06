import 'package:flutter/widgets.dart';
import 'package:hugeicons/hugeicons.dart';

/// One of Hugeicons' icons (`HugeIcons.strokeRounded...`): the SVG elements that draw it.
typedef HugeIconData = List<List<dynamic>>;

/// A Hugeicons icon that takes its size and color from the [IconTheme], as an [Icon] does. A [HugeIcon] alone is
/// 24 pixels wherever it is, in a button of 40 as in a label of 16.
class ThemedIcon extends StatelessWidget {
  const ThemedIcon(this.icon, {this.size, this.color, super.key});

  final HugeIconData icon;

  /// The theme's when null.
  final double? size;

  /// The theme's when null.
  final Color? color;

  @override
  Widget build(BuildContext context) => HugeIcon(icon: icon, size: size, color: color);
}
