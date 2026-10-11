import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/widgets/focus_ring.dart';
import 'package:segue/ui/widgets/segmented_choice.dart';

/// A choice between [options], "Suas mais tocadas" and "Populares" unless given, the first picked, in the app's theme,
/// as wide as it asks up to [width]; what is picked goes to [picks], and is then the one picked. With [icons], each
/// option shows one.
Future<void> pumpChoice(
  WidgetTester tester,
  List<String> picks, {
  List<String> options = const ['Suas mais tocadas', 'Populares'],
  double width = double.infinity,
  bool icons = false,
}) async {
  var selected = options.first;
  await tester.pumpWidget(
    MaterialApp(
      theme: segueTheme(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: StatefulBuilder(
              builder: (context, setState) => SegmentedChoice(
                selected,
                options: options,
                label: (option) => option,
                icon: icons
                    ? (option) =>
                          option == options.first ? HugeIcons.strokeRoundedHeadphones : HugeIcons.strokeRoundedFire
                    : null,
                onSelected: (option) => setState(() {
                  picks.add(option);
                  selected = option;
                }),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The choice, the button that holds the options.
Rect choice(WidgetTester tester) => tester.getRect(find.byType(InkWell));

/// The option that says [label], with the room around its words.
Rect option(WidgetTester tester, String label) =>
    tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(Padding)).first);

/// The thumb, which is under the option picked.
Rect thumb(WidgetTester tester) => tester.getRect(find.byType(Ink));

/// What paints the thumb, in the theme's primary color, at [place]: the material under the options.
PaintPattern thumbAt(WidgetTester tester, Rect place) => paints
  ..rrect(
    rrect: RRect.fromRectAndRadius(place, Radius.circular(place.height / 2)),
    color: Theme.of(tester.element(find.byType(InkWell))).colorScheme.primary,
  );

/// The material the thumb is painted on.
RenderObject material(WidgetTester tester) =>
    tester.renderObject(find.ancestor(of: find.byType(InkWell), matching: find.byType(Material)).first);

/// Whether the choice has the focus ring around it.
bool ringed(WidgetTester tester) {
  final ring = find.descendant(of: find.byType(FocusRing), matching: find.byType(DecoratedBox)).first;

  return (tester.widget<DecoratedBox>(ring).decoration as BoxDecoration).border != null;
}

void main() {
  testWidgets('each option is as wide as it asks, side by side, and the thumb, as tall as the button, is under the one '
      'picked, which the button says', (tester) async {
    await pumpChoice(tester, []);
    final mine = option(tester, 'Suas mais tocadas');
    final popular = option(tester, 'Populares');
    expect(popular.width, lessThan(mine.width), reason: 'its words fewer');
    expect(popular.left, mine.right, reason: 'side by side');
    expect(choice(tester), mine.expandToInclude(popular), reason: 'no room around them');
    expect(thumb(tester), mine, reason: 'from the button\'s edge, as tall as it');
    expect(
      tester.getSemantics(find.text('Suas mais tocadas')),
      isSemantics(label: 'Suas mais tocadas', isButton: true, hasTapAction: true, isFocusable: true),
    );
  });

  testWidgets('a tap anywhere on it picks the other, and the thumb slides to it, taking its width', (tester) async {
    final picks = <String>[];
    await pumpChoice(tester, picks);
    final mine = option(tester, 'Suas mais tocadas');
    final popular = option(tester, 'Populares');

    await tester.tap(find.text('Suas mais tocadas'));
    await tester.pump();
    expect(picks, ['Populares'], reason: 'the other, even with a tap on the one picked');
    await tester.pump(SegmentedChoice.duration ~/ 2);
    expect(thumb(tester).left, inExclusiveRange(mine.left, popular.left), reason: 'on its way');
    expect(thumb(tester).width, inExclusiveRange(popular.width, mine.width));
    await tester.pumpAndSettle();
    expect(thumb(tester), popular);
    expect(material(tester), thumbAt(tester, popular));
    expect(tester.getSemantics(find.text('Populares')), isSemantics(label: 'Populares'));

    await tester.tap(find.text('Populares'));
    await tester.pumpAndSettle();
    expect(picks, ['Populares', 'Suas mais tocadas'], reason: 'back to the first');
    expect(thumb(tester), mine);
  });

  testWidgets('with three, a tap picks the next, and the first after the last', (tester) async {
    final picks = <String>[];
    await pumpChoice(tester, picks, options: ['Nome', 'Mais tocados', 'Recentes']);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
    }

    expect(picks, ['Mais tocados', 'Recentes', 'Nome']);
    expect(thumb(tester), option(tester, 'Nome'));
  });

  testWidgets('where they don\'t fit, the narrow one keeps its width, and the other takes the room left', (
    tester,
  ) async {
    await pumpChoice(tester, []);
    final popular = option(tester, 'Populares').width;
    final width = 2 * popular + 10;
    expect(width, lessThan(choice(tester).width), reason: 'less than they ask');

    await pumpChoice(tester, [], width: width);
    expect(choice(tester).width, width);
    expect(option(tester, 'Populares').width, popular);
    expect(option(tester, 'Suas mais tocadas').width, width - popular);
    expect(thumb(tester), option(tester, 'Suas mais tocadas'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('where the system asks for less motion, the thumb moves at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpChoice(tester, []);
    await tester.tap(find.text('Populares'));
    await tester.pump();
    expect(thumb(tester), option(tester, 'Populares'));
  });

  testWidgets('with icons, each has its name in a tooltip, and the button says the one picked', (tester) async {
    await pumpChoice(tester, [], icons: true);
    expect(find.byType(Text), findsNothing);
    expect(find.byTooltip('Suas mais tocadas'), findsOneWidget);
    expect(find.byTooltip('Populares'), findsOneWidget);
    expect(tester.getSemantics(find.byType(InkWell)), isSemantics(label: 'Suas mais tocadas', isButton: true));

    await tester.tap(find.byTooltip('Suas mais tocadas'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byType(InkWell)), isSemantics(label: 'Populares', isButton: true));
  });

  testWidgets('the keyboard and the remote reach it, with a ring around it, and pick the other', (tester) async {
    final picks = <String>[];
    await pumpChoice(tester, picks);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(ringed(tester), isTrue, reason: 'where the thumb would hide the theme\'s tint');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(picks, ['Populares']);
    expect(thumb(tester), option(tester, 'Populares'));
    expect(ringed(tester), isTrue, reason: 'the focus staying');
  });
}
