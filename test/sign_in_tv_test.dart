import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_view_test.dart' show openSettings, pumpHome, settingsItem;

void main() {
  testWidgets('on a phone, the settings have a way to sign a TV in, by the sign-in, before signing out', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 800));
    await openSettings(tester);
    await tester.scrollUntilVisible(settingsItem('Sair'), 200, scrollable: find.byType(Scrollable).last);
    final item = settingsItem('Entrar numa TV');
    expect(item, findsOneWidget);
    expect(find.descendant(of: item, matching: find.text('Com este login, lendo o código que a TV mostra')), findsOne);
    expect(tester.getRect(item).bottom, lessThanOrEqualTo(tester.getRect(settingsItem('Sair')).top));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a TV signs in that way itself, and a computer has no camera to read the code with: neither has it', (
    tester,
  ) async {
    await pumpHome(tester, const Size(960, 540), television: true);
    await openSettings(tester);
    expect(settingsItem('Entrar numa TV'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpHome(tester, const Size(1280, 800));
    await openSettings(tester);
    expect(settingsItem('Entrar numa TV'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
