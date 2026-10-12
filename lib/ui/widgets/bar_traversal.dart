import 'package:flutter/widgets.dart';

/// Moving around a bar with the arrows (a TV remote's): left and right along its row of buttons, up and down between
/// its rows (the player bar's slider and its buttons), out of it on the side of the page ([out]), and nowhere past its
/// other edges. Flutter's own directional search looks at the whole screen, where the page's cards lie under the bars,
/// scrolled under the top one or built past the bottom of the screen under the player's, level with their buttons, and
/// could win.
class BarTraversalPolicy extends ReadingOrderTraversalPolicy {
  BarTraversalPolicy._(this.out);

  /// The player bar's, at the bottom of the screen.
  static final bottom = BarTraversalPolicy._(TraversalDirection.up);

  /// The top bar's.
  static final top = BarTraversalPolicy._(TraversalDirection.down);

  /// Where the page is, past the bar's edge: the way out of it, where the arrow goes on as anywhere else.
  final TraversalDirection out;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final here = currentNode.rect;
    final nodes = [
      for (final node in currentNode.nearestScope!.traversalDescendants)
        if (node != currentNode && FocusTraversalGroup.maybeOfNode(node) == this) node,
    ];
    // One stop where a node holds another, as the search bar's ink holds its text field: the one held, and from it, not
    // the one holding it.
    final bar = [
      for (final node in nodes)
        if (!currentNode.ancestors.contains(node) && !nodes.any((other) => other.ancestors.contains(node))) node,
    ];

    bool level(FocusNode node) => node.rect.top < here.bottom && node.rect.bottom > here.top;

    double away(FocusNode node) => (node.rect.center - here.center).distance;

    FocusNode? closest(Iterable<FocusNode> nodes) =>
        nodes.isEmpty ? null : nodes.reduce((a, b) => away(a) <= away(b) ? a : b);

    final target = closest(switch (direction) {
      TraversalDirection.left => bar.where((node) => level(node) && node.rect.center.dx < here.center.dx),
      TraversalDirection.right => bar.where((node) => level(node) && node.rect.center.dx > here.center.dx),
      TraversalDirection.up => bar.where((node) => node.rect.bottom <= here.top + 1),
      TraversalDirection.down => bar.where((node) => node.rect.top >= here.bottom - 1),
    });

    if (target != null) {
      requestFocusCallback(target);
      return true;
    }

    return direction == out && super.inDirection(currentNode, direction);
  }
}
