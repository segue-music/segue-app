import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/theme.dart';

/// An app in the app's theme, on a page that opens a second, with a row that goes on sideways and a button counted in
/// [presses]. Opens the second.
Future<void> pumpPages(WidgetTester tester, {List<int>? presses}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: segueTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Second')),
                    body: ListView(
                      children: [
                        SizedBox(
                          height: 100,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [for (var i = 0; i < 20; i++) SizedBox(width: 100, child: Text('Item $i'))],
                          ),
                        ),
                        TextButton(onPressed: () => presses?.add(1), child: const Text('Press')),
                        const SizedBox(height: 300, child: Center(child: Text('Body'))),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Whether the navigator's pages take a touch: not during a swipe.
bool swiping(WidgetTester tester) => tester.state<NavigatorState>(find.byType(Navigator)).userGestureInProgress;

void main() {
  testWidgets('a finger swiping a page to the right, from its middle, moves it as far, the page under showing beside '
      'it, and takes it back once let go past the middle', (tester) async {
    await pumpPages(tester);
    final title = tester.getTopLeft(find.text('Second')).dx;
    expect(find.text('Open'), findsNothing, reason: 'under the second page');

    var gesture = await tester.startGesture(tester.getCenter(find.text('Body')));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Second')).dx, moreOrLessEquals(title + 220, epsilon: 20));
    expect(find.text('Open'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Second')).dx, title, reason: 'not past the middle');
    expect(find.text('Open'), findsNothing);
    expect(swiping(tester), isFalse);

    gesture = await tester.startGesture(tester.getCenter(find.text('Body')));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(500, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(swiping(tester), isFalse);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget, reason: 'the first page takes a touch again');
  });

  testWidgets('flung to the right, a short swipe takes the page back too; a slow one leaves it', (tester) async {
    await pumpPages(tester);
    await tester.timedDrag(find.text('Body'), const Offset(150, 0), const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);

    await tester.fling(find.text('Body'), const Offset(150, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('a row that goes on sideways goes on, rather than the page back, and a button still takes a press', (
    tester,
  ) async {
    final presses = <int>[];
    await pumpPages(tester, presses: presses);
    await tester.drag(find.text('Item 1'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Item 0'), findsNothing);

    await tester.drag(find.text('Item 4'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Item 0'), findsOneWidget);

    await tester.tap(find.text('Press'));
    expect(presses, [1]);
  });

  testWidgets('a mouse drag leaves the page', (tester) async {
    await pumpPages(tester);
    await tester.dragFrom(tester.getCenter(find.text('Body')), const Offset(600, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('the first page, with nothing to go back to, has no swipe', (tester) async {
    await pumpPages(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Open'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(swiping(tester), isFalse);
  });
}
