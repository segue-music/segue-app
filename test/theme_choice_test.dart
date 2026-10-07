import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/app.dart';
import 'package:segue/session.dart';
import 'package:segue/theme_choice.dart';
import 'package:segue/ui/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  setUp(() async {
    await SharedPreferencesAsync().clear();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('the theme follows the system\'s until a pick, which the next launch, and a sign-out, keep', () async {
    expect((await ThemeChoice.load()).value, ThemeMode.system);

    await ThemeChoice().pick(ThemeMode.dark);
    await Session.clear();
    expect((await ThemeChoice.load()).value, ThemeMode.dark);

    await ThemeChoice().pick(ThemeMode.light);
    expect((await ThemeChoice.load()).value, ThemeMode.light);
  });

  test('a theme saved that the app doesn\'t know is the system\'s', () async {
    await SharedPreferencesAsync().setString('theme', 'sepia');
    expect((await ThemeChoice.load()).value, ThemeMode.system);
  });

  testWidgets('the app shows the theme picked, whatever the system\'s, as soon as it is picked', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final choice = ThemeChoice(ThemeMode.dark);
    addTearDown(choice.dispose);
    Brightness shown() => Theme.of(tester.element(find.byType(LoginPage))).brightness;

    await tester.pumpWidget(SegueApp(session: null, themeChoice: choice));
    expect(shown(), Brightness.dark);

    choice.value = ThemeMode.light;
    await tester.pumpAndSettle();
    expect(shown(), Brightness.light);
  });
}
