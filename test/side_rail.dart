import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// On a wide screen, the side rail's button for [section], selected: the section the home shows. The top bar has no
/// section name there.
Finder selectedInRail(String section) => find.descendant(
  of: find.byTooltip(section),
  matching: find.byWidgetPredicate((widget) => widget is IconButton && (widget.isSelected ?? false)),
);

/// On a wide screen, that the home shows its own section, which the side rail doesn't list: none of its buttons is
/// selected.
void expectHomeInRail() {
  for (final section in ['Álbuns', 'Artistas', 'Gêneros']) {
    expect(selectedInRail(section), findsNothing, reason: section);
  }
}
