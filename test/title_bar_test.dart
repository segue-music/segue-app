import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/app.dart';
import 'package:segue/ui/theme.dart';

const channel = MethodChannel('segue/window');

/// What the window is told to paint its title bar, in the theme of [brightness].
Map<String, int> titleBarColors(Brightness brightness) {
  final colors = segueTheme(brightness).colorScheme;
  return {'background': colors.surface.toARGB32(), 'foreground': colors.onSurface.toARGB32()};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<Object?> painted;

  setUp(() {
    painted = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setTitleBarColors') {
        painted.add(call.arguments);
      }

      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('the window\'s title bar takes the app\'s background and text, in the dark and in the light', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const SegueApp(session: null));
    expect(painted.last, titleBarColors(Brightness.dark));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(painted.last, titleBarColors(Brightness.light));
  });

  testWidgets('the window is told the colors when they change, not on every frame', (tester) async {
    await tester.pumpWidget(const SegueApp(session: null));
    await tester.enterText(find.widgetWithText(TextFormField, 'Servidor'), 'music.example');
    await tester.pumpAndSettle();
    expect(painted, [titleBarColors(Brightness.light)]);
  });

  testWidgets('where the window has no title bar of the app\'s (no such channel), the app goes on as ever', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, null);
    await tester.pumpWidget(const SegueApp(session: null));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Servidor'), findsOneWidget);
  });
}
