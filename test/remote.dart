import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picks [text] in the menu open, as the remote does: down to it, and OK.
Future<void> pickByRemote(WidgetTester tester, String text) async {
  bool focused() {
    // An item: not the menu, which has the focus as it opens.
    final focus = FocusManager.instance.primaryFocus;
    final context = focus is FocusScopeNode ? null : focus?.context;
    return context != null &&
        find
            .descendant(of: find.byElementPredicate((element) => element == context), matching: find.text(text))
            .evaluate()
            .isNotEmpty;
  }

  for (var i = 0; i < 10 && !focused(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
  }

  expect(focused(), isTrue, reason: text);
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

/// Presses [key], as the remote does. Its back button, which the tests' keyboard lacks, comes as a browser's: the same
/// key to the app.
Future<void> pressOnRemote(WidgetTester tester, LogicalKeyboardKey key) async {
  if (key == LogicalKeyboardKey.goBack) {
    await tester.sendKeyEvent(key, platform: 'web', physicalKey: PhysicalKeyboardKey.browserBack);
  } else {
    await tester.sendKeyEvent(key);
  }

  await tester.pumpAndSettle();
}

/// The message at the bottom while the remote moves a song.
final moveHint = find.text('Para cima e para baixo movem a música; OK a deixa aí, e Voltar desfaz.');
