import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/crossfade_choice.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/settings.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';
import 'themed_icons.dart';

void main() {
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  setUp(() async {
    await SharedPreferencesAsync().clear();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('none until a length is picked, which the next launch, and a sign-out, keep', () async {
    expect((await CrossfadeChoice.load()).value, Duration.zero);

    await CrossfadeChoice().pick(const Duration(seconds: 6));
    await Session.clear();
    expect((await CrossfadeChoice.load()).value, const Duration(seconds: 6));

    await CrossfadeChoice().pick(Duration.zero);
    expect((await CrossfadeChoice.load()).value, Duration.zero);
  });

  test('a length kept that the app no longer offers is none', () async {
    await SharedPreferencesAsync().setInt('crossfade', 7);
    expect((await CrossfadeChoice.load()).value, Duration.zero);
  });

  /// The settings' page, with [settings] to pick, or none.
  Future<void> pumpSettings(WidgetTester tester, Settings? settings) async {
    const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final player = PlayerController(FakeEngine(), api);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
    );
    // A window tall enough for every line of the settings.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) {
          final page = ServicesScope(services: services, child: child!);

          return settings == null ? page : SettingsScope(settings: settings, child: page);
        },
        home: SettingsPage(onSignOut: () {}),
      ),
    );
  }

  testWidgets('the settings pick how long the songs crossfade for, under the playback, none with what it does', (
    tester,
  ) async {
    final settings = Settings();

    addTearDown(settings.dispose);

    final crossfade = settings.crossfade;

    await pumpSettings(tester, settings);

    final line = find.widgetWithText(ListTile, 'Crossfade');

    expect(tester.getRect(line).top, greaterThan(tester.getRect(find.text('Reprodução')).bottom));
    expect(find.descendant(of: line, matching: find.text('Desligado')), findsOneWidget);
    expect(find.descendant(of: line, matching: themedIcon(HugeIcons.strokeRoundedBlend)), findsOneWidget);

    await tester.tap(line);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);

    expect(find.descendant(of: sheet, matching: find.text('Cada música logo depois da anterior, sem pausa')), findsOne);

    for (final length in ['2 segundos', '4 segundos', '6 segundos', '8 segundos', '10 segundos', '12 segundos']) {
      expect(find.descendant(of: sheet, matching: find.text(length)), findsOneWidget);
    }

    await tester.tap(find.descendant(of: sheet, matching: find.text('6 segundos')));
    await tester.pumpAndSettle();
    expect(crossfade.value, const Duration(seconds: 6));
    expect(find.descendant(of: line, matching: find.text('6 segundos')), findsOneWidget);
    expect(
      await tester.runAsync(() async => (await CrossfadeChoice.load()).value),
      const Duration(seconds: 6),
      reason: 'kept',
    );

    await pumpSettings(tester, null);
    expect(line, findsNothing);
  });
}
