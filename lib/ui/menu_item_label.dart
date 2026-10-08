import 'package:flutter/material.dart';

import 'themed_icon.dart';

/// A menu item's text, after its icon (the picked one's check) or the room for one, so that the texts line up.
class MenuItemLabel extends StatelessWidget {
  const MenuItemLabel(this.text, {this.icon, this.detail, super.key});

  final String text;

  /// Before the text; none, its room.
  final HugeIconData? icon;

  /// Under the text, smaller: what the choice does.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final (icon, detail) = (this.icon, this.detail);
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox.square(dimension: 24, child: icon == null ? null : ThemedIcon(icon)),
        const SizedBox(width: 12),
        Flexible(
          child: detail == null
              ? Text(text)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(text),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
