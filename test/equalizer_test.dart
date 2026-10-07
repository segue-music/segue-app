import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/equalizer.dart';

void main() {
  setUp(() => Equalizer.moves = true);
  tearDown(() => Equalizer.moves = false);

  testWidgets('the equalizer moves, and stands still where the system asks for less motion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: Equalizer())));
    expect(tester.hasRunningAnimations, isTrue);
    expect(tester.getSize(find.byType(Equalizer)), const Size.square(24), reason: 'an icon');

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);

    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });
}
