import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Moves the focus a page down the list or the grid it is in, or up ([down] false), as a TV remote's channel buttons
/// do: the list scrolls by as much as it shows, and the focus goes to what is then where it was on the screen. At the
/// list's end it goes to the last row in view instead (going up, the first). Returns whether the focus is in such a
/// list: one that scrolls up and down, around a row of tiles, which scrolls sideways.
bool focusNextPage({required bool down}) {
  final inList = _focusInList();

  if (inList == null) {
    return false;
  }

  final (:scrollable, :scope, :box) = inList;
  final position = scrollable.position;
  final point = box.localToGlobal(box.size.center(Offset.zero));
  final target = (position.pixels + (down ? 1 : -1) * position.viewportDimension).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );

  if (target == position.pixels) {
    final viewport = _rectOf(scrollable.context);

    focusNearest(scrollable, Offset(point.dx, down ? viewport.bottom : viewport.top), scope: scope);
  } else {
    position.jumpTo(target);
    // Once what scrolled into view is there.
    WidgetsBinding.instance.addPostFrameCallback((_) => focusNearest(scrollable, point, scope: scope));
  }

  return true;
}

/// Scrolls the list the focus is in back to its start, the focus going to what comes first there, as a TV remote's back
/// does before it leaves a page: where what has the focus is past the list's first screen. Nearer, back leaves the page
/// at once. Returns whether it scrolled.
bool focusListStart() {
  final inList = _focusInList();

  if (inList == null) {
    return false;
  }

  final (:scrollable, :scope, :box) = inList;
  final position = scrollable.position;
  final bottom = box.localToGlobal(box.size.bottomCenter(Offset.zero)).dy - _rectOf(scrollable.context).top;

  // Where it ends in the list, from its start.
  if (position.pixels + bottom <= position.minScrollExtent + position.viewportDimension) {
    return false;
  }

  position.jumpTo(position.minScrollExtent);
  WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirst(scrollable, scope));

  return true;
}

/// Scrolls the grid whose sliver has the key [grid] (a [SliverGrid]'s) until its child at [index] is at the top, or as
/// far as it goes: a long list's jump to a letter. Nothing where the grid isn't there.
void scrollToGridChild(GlobalKey grid, int index) {
  final sliver = grid.currentContext?.findRenderObject();

  if (sliver is! RenderSliverGrid) {
    return;
  }

  // Given more children, a grid keeps the length it had until it is laid out again, as scrolling does: Flutter lays
  // out again only for the children it has (SliverMultiBoxAdaptorElement.performRebuild). Before it goes anywhere, at
  // its length now.
  sliver.markNeedsLayout();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = grid.currentContext;

    if (context == null || !sliver.attached || sliver.geometry == null) {
      return;
    }

    final position = Scrollable.of(context).position;
    final child = sliver.gridDelegate.getLayout(sliver.constraints).getGeometryForChildIndex(index);
    // Past what comes before the grid.
    final start = sliver.constraints.precedingScrollExtent + child.scrollOffset;

    position.jumpTo(start.clamp(position.minScrollExtent, position.maxScrollExtent));
  });
}

/// Scrolls the first list under [context] that scrolls up and down (a section's, a page's) back to its start, as a
/// side rail's button does, picked again where it shows already. Smoothly, from a screen away at most: from farther,
/// past the rest at once, rather than building, and asking the covers of, all on the way.
void scrollToStart(BuildContext context) {
  ScrollableState? found;

  void visit(Element element) {
    if (found != null) {
      return;
    }

    if (element case StatefulElement(state: final ScrollableState scrollable)
        when scrollable.position.axis == Axis.vertical) {
      found = scrollable;
      return;
    }

    element.visitChildren(visit);
  }

  context.visitChildElements(visit);

  final position = found?.position;

  if (position == null) {
    return;
  }

  final start = position.minScrollExtent;

  if (position.pixels > start + position.viewportDimension) {
    position.jumpTo(start + position.viewportDimension);
  }

  position.animateTo(start, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
}

/// Gives the focus to what, in [scrollable]'s view and in [scope], can take it and is nearest [point] on the screen:
/// wholly in view where something is, the rest only where nothing is.
void focusNearest(ScrollableState scrollable, Offset point, {required FocusScopeNode scope}) {
  final viewport = _rectOf(scrollable.context);
  final inView = _focusableInView(scrollable, scope);
  final wholly = [
    for (final node in inView)
      if (viewport.inflate(1).contains(node.rect.topLeft) && viewport.inflate(1).contains(node.rect.bottomRight)) node,
  ];
  final candidates = wholly.isNotEmpty ? wholly : inView;

  if (candidates.isEmpty) {
    return;
  }

  double distance(FocusNode node) => (node.rect.center - point).distanceSquared;

  candidates.reduce((a, b) => distance(b) < distance(a) ? b : a).requestFocus();
}

/// Gives the focus to what comes first in [scrollable]'s view, in [scope]: at the top, and the leftmost there.
void _focusFirst(ScrollableState scrollable, FocusScopeNode scope) {
  final inView = _focusableInView(scrollable, scope);

  if (inView.isEmpty) {
    return;
  }

  final top = inView.reduce((a, b) => b.rect.top < a.rect.top ? b : a);
  // Those beside it, which a card grown with the focus may stand a little above.
  final row = [
    for (final node in inView)
      if (node.rect.top < top.rect.center.dy) node,
  ];

  row.reduce((a, b) => b.rect.left < a.rect.left ? b : a).requestFocus();
}

/// What can take the focus in [scope] with its middle in [scrollable]'s view: in [scrollable] itself, not in a list
/// beside it, nor in another one in it that scrolls up and down too.
List<FocusNode> _focusableInView(ScrollableState scrollable, FocusScopeNode scope) {
  final viewport = _rectOf(scrollable.context);

  return [
    for (final node in scope.traversalDescendants)
      if (node is! FocusScopeNode && _laidOut(node) && viewport.contains(node.rect.center))
        if (Scrollable.maybeOf(node.context!, axis: Axis.vertical) == scrollable) node,
  ];
}

/// The list the focus is in, one that scrolls up and down, the focus' scope and what has it; none where it isn't in one.
({ScrollableState scrollable, FocusScopeNode scope, RenderBox box})? _focusInList() {
  final focus = FocusManager.instance.primaryFocus;
  final focused = focus?.context;
  final scope = focus?.nearestScope;
  final scrollable = focused == null ? null : Scrollable.maybeOf(focused, axis: Axis.vertical);
  final box = focused?.findRenderObject();

  if (scrollable == null || scope == null || box is! RenderBox || !box.hasSize) {
    return null;
  }

  return (scrollable: scrollable, scope: scope, box: box);
}

bool _laidOut(FocusNode node) {
  final box = node.context?.findRenderObject();

  return box is RenderBox && box.attached && box.hasSize;
}

/// Where [context]'s box is on the screen.
Rect _rectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;

  return box.localToGlobal(Offset.zero) & box.size;
}
