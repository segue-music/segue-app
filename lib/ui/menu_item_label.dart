import 'package:flutter/material.dart';

import 'themed_icon.dart';

/// A menu item's text, after its icon (the picked one's check) or the room for one, so that the texts line up.
class MenuItemLabel extends StatelessWidget {
  const MenuItemLabel(this.text, {this.icon, super.key});

  final String text;

  /// Before the text; none, its room.
  final HugeIconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Row(
      children: [
        SizedBox.square(dimension: 24, child: icon == null ? null : ThemedIcon(icon)),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ],
    );
  }
}
