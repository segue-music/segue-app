import 'package:flutter/material.dart';

/// The [orders] a list can come in, as chips in a line that scrolls sideways when it doesn't fit: the one picked, and
/// the others to pick. Above the list, its line takes the whole width, the chips starting at its left, lined up with
/// what the list shows.
class OrderChips<T> extends StatelessWidget {
  const OrderChips(this.order, {required this.orders, required this.label, required this.onOrder, super.key});

  /// The one picked.
  final T order;

  final List<T> orders;

  /// What a chip says of its order.
  final String Function(T order) label;

  final ValueChanged<T> onOrder;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    // Room under them that stays as the list scrolls, whose own room above goes away with it.
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      children: [
        for (final option in orders)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label(option)),
              selected: option == order,
              onSelected: (_) => onOrder(option),
              mouseCursor: WidgetStateMouseCursor.clickable,
            ),
          ),
      ],
    ),
  );
}
