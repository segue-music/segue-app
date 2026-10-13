import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/autoplay_choice.dart';
import 'package:segue/connect/connect.dart';
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

  test('autoplay is on until turned off, which the next launch, and a sign-out, keep', () async {
    expect((await AutoplayChoice.load()).value, isTrue);

    await AutoplayChoice().turn(false);
    await Session.clear();
    expect((await AutoplayChoice.load()).value, isFalse);

    await AutoplayChoice(false).turn(true);
    expect((await AutoplayChoice.load()).value, isTrue);
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

  testWidgets('the settings turn autoplay off and on, under the playback, with what it does', (tester) async {
    final settings = Settings();
    addTearDown(settings.dispose);
    final autoplay = settings.autoplay;
    await pumpSettings(tester, settings);
    final toggle = find.widgetWithText(SwitchListTile, 'Reprodução automática');
    expect(find.text('Reprodução'), findsOneWidget);
    expect(tester.getRect(toggle).top, greaterThan(tester.getRect(find.text('Reprodução')).bottom));
    expect(find.text('Quando a fila acaba, músicas parecidas continuam tocando.'), findsOneWidget);
    expect(find.descendant(of: toggle, matching: themedIcon(HugeIcons.strokeRoundedInfinity01)), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pump();
    expect(autoplay.value, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(await tester.runAsync(() async => (await AutoplayChoice.load()).value), isFalse, reason: 'kept');

    await pumpSettings(tester, null);
    expect(toggle, findsNothing);
    expect(find.text('Reprodução'), findsNothing, reason: 'with nothing in it to pick');
  });
}
