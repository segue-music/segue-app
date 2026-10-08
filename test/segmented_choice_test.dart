import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/focus_ring.dart';
import 'package:segue/ui/segmented_choice.dart';
import 'package:segue/ui/theme.dart';

/// A choice between "Suas mais tocadas" and "Populares", the first picked, in the app's theme; what is picked goes to
/// [picks], and is then the one picked.
Future<void> pumpChoice(WidgetTester tester, List<String> picks) async {
  var selected = 'Suas mais tocadas';
  await tester.pumpWidget(
    MaterialApp(
      theme: segueTheme(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: StatefulBuilder(
            builder: (context, setState) => SegmentedChoice(
              selected,
              options: const ['Suas mais tocadas', 'Populares'],
              label: (option) => option,
              onSelected: (option) => setState(() {
                picks.add(option);
                selected = option;
              }),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The option that says [label].
Finder option(String label) => find.ancestor(of: find.text(label), matching: find.byType(InkWell));

/// The thumb, which is under the option picked.
Rect thumb(WidgetTester tester) =>
    tester.getRect(find.descendant(of: find.byType(FractionallySizedBox), matching: find.byType(DecoratedBox)));

/// Whether the option that says [label] has the focus ring around it.
bool ringed(WidgetTester tester, String label) {
  final ring = find.descendant(
    of: find.ancestor(of: option(label), matching: find.byType(FocusRing)),
    matching: find.byType(DecoratedBox),
  );
  return (tester.widget<DecoratedBox>(ring.first).decoration as BoxDecoration).border != null;
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the options are as wide as the widest, and the thumb is under the one picked, which says so', (
    tester,
  ) async {
    await pumpChoice(tester, []);
    final mine = tester.getRect(option('Suas mais tocadas'));
    final popular = tester.getRect(option('Populares'));
    expect(popular.size, mine.size);
    expect(popular.left, mine.right, reason: 'side by side');
    expect(thumb(tester), mine);
    expect(
      tester.getSemantics(find.text('Suas mais tocadas')),
      isSemantics(label: 'Suas mais tocadas', isButton: true, isSelected: true, isInMutuallyExclusiveGroup: true),
    );
    expect(tester.getSemantics(find.text('Populares')), isSemantics(label: 'Populares', isSelected: false));
  });

  testWidgets('picking another slides the thumb to it', (tester) async {
    final picks = <String>[];
    await pumpChoice(tester, picks);
    final mine = tester.getRect(option('Suas mais tocadas'));
    final popular = tester.getRect(option('Populares'));

    await tester.tap(find.text('Populares'));
    await tester.pump();
    expect(picks, ['Populares']);
    await tester.pump(SegmentedChoice.duration ~/ 2);
    expect(thumb(tester).left, inExclusiveRange(mine.left, popular.left), reason: 'on its way');
    await tester.pumpAndSettle();
    expect(thumb(tester), popular);
    expect(tester.getSemantics(find.text('Populares')), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.text('Suas mais tocadas')), isSemantics(isSelected: false));
  });

  testWidgets('where the system asks for less motion, the thumb moves at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpChoice(tester, []);
    await tester.tap(find.text('Populares'));
    await tester.pump();
    expect(thumb(tester), tester.getRect(option('Populares')));
  });

  testWidgets('the keyboard and the remote go from one option to the next, with a ring around it, and pick it', (
    tester,
  ) async {
    final picks = <String>[];
    await pumpChoice(tester, picks);
    await press(tester, LogicalKeyboardKey.tab);
    expect(ringed(tester, 'Suas mais tocadas'), isTrue, reason: 'where the thumb would hide the theme\'s tint');
    expect(ringed(tester, 'Populares'), isFalse);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(ringed(tester, 'Populares'), isTrue);
    expect(ringed(tester, 'Suas mais tocadas'), isFalse);
    expect(picks, isEmpty, reason: 'the focus only passing by');

    await press(tester, LogicalKeyboardKey.select);
    expect(picks, ['Populares']);
    expect(thumb(tester), tester.getRect(option('Populares')));
  });
}
