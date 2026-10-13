import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/app.dart';
import 'package:segue/session.dart';
import 'package:segue/settings.dart';
import 'package:segue/theme_choice.dart';
import 'package:segue/ui/app/login_page.dart';
import 'package:segue/ui/app/theme.dart';
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
    expect((await ThemeChoice.load()).value.mode, ThemeMode.system);

    await ThemeChoice().pickMode(ThemeMode.dark);
    await Session.clear();
    expect((await ThemeChoice.load()).value.mode, ThemeMode.dark);

    await ThemeChoice().pickMode(ThemeMode.light);
    expect((await ThemeChoice.load()).value.mode, ThemeMode.light);
  });

  test(
    'the colors are the icon\'s pink on its black, and the contrast Material\'s, until a pick, which the next launch, '
    'and a sign-out, keep, each apart from the rest',
    () async {
      expect((await ThemeChoice.load()).value, const ThemeSettings());

      final choice = await ThemeChoice.load();
      await choice.pickMode(ThemeMode.dark);
      await choice.pickPalette(Palette.wine);
      await choice.turnHighContrast(true);
      await Session.clear();
      expect(
        (await ThemeChoice.load()).value,
        const ThemeSettings(mode: ThemeMode.dark, palette: Palette.wine, highContrast: true),
      );

      await ThemeChoice((await ThemeChoice.load()).value).pickPalette(Palette.neutral);
      expect(
        (await ThemeChoice.load()).value,
        const ThemeSettings(mode: ThemeMode.dark, palette: Palette.neutral, highContrast: true),
      );
    },
  );

  test('a theme or colors saved that the app doesn\'t know are the system\'s and the first', () async {
    await SharedPreferencesAsync().setString('theme', 'sepia');
    await SharedPreferencesAsync().setString('themePalette', 'ocean');
    expect((await ThemeChoice.load()).value, const ThemeSettings());
  });

  testWidgets('the app shows the theme picked, whatever the system\'s, as soon as it is picked', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final settings = Settings(theme: ThemeChoice(const ThemeSettings(mode: ThemeMode.dark)));
    addTearDown(settings.dispose);
    final choice = settings.theme;
    ThemeData shown() => Theme.of(tester.element(find.byType(LoginPage)));

    await tester.pumpWidget(SegueApp(session: null, settings: settings));
    expect(shown().brightness, Brightness.dark);
    expect(shown().colorScheme.surface, iconBlack);

    choice.value = const ThemeSettings(mode: ThemeMode.dark, palette: Palette.wine);
    await tester.pumpAndSettle();
    expect(shown().colorScheme.surface, iconWine, reason: 'the colors picked');

    choice.value = const ThemeSettings(mode: ThemeMode.dark, palette: Palette.wine, highContrast: true);
    await tester.pumpAndSettle();
    expect(shown().colorScheme, segueColors(Brightness.dark, palette: Palette.wine, highContrast: true));

    choice.value = const ThemeSettings(mode: ThemeMode.light);
    await tester.pumpAndSettle();
    expect(shown().brightness, Brightness.light);
  });
}
