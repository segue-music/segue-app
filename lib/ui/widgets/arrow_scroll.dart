import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Up and down (a TV remote's, a keyboard's) for a view in which nothing takes the focus: each scrolls [controller]'s
/// most of a screen up or down, and only at its ends goes on, to what is around it. It takes the focus as it comes.
class ArrowScroll extends StatelessWidget {
  const ArrowScroll({required this.controller, required this.child, super.key});

  final ScrollController controller;
  final Widget child;

  /// Scrolls most of a screen up or down for the arrow up or down; at the end it goes to, leaves the arrow to the focus,
  /// which goes on past the view.
  KeyEventResult _scrollByArrow(FocusNode _, KeyEvent event) {
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };

    if (direction == 0 || event is KeyUpEvent || !controller.hasClients) {
      return KeyEventResult.ignored;
    }

    final position = controller.position;
    final to = (position.pixels + direction * position.viewportDimension * 0.8).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (to == position.pixels) {
      return KeyEventResult.ignored;
    }

    position.animateTo(to, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(autofocus: true, onKeyEvent: _scrollByArrow, child: child);
}
