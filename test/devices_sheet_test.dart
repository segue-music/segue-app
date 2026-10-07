import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/player/player.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/devices_sheet.dart';
import 'package:segue/ui/equalizer.dart';
import 'package:segue/ui/themed_icon.dart';

import 'fakes.dart';
import 'themed_icons.dart';

Device player(String id, String name, {required bool online, StampedState? state}) => Device(
  info: DeviceInfo(
    id: id,
    name: name,
    client: 'test',
    api: Api.subsonic,
    roles: const [Role.player],
    capabilities: const [],
  ),
  online: online,
  state: state,
);

/// Opens the device picker with [devices] as the user's other devices, on a screen of [size] (the test's, by
/// default), on a [television] or not.
Future<void> openSheet(WidgetTester tester, List<Device> devices, {Size? size, bool television = false}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((_) async => http.Response('', 404)),
  );
  final client = SegueClient(
    url: Uri.parse('ws://unused'),
    auth: const Auth.subsonic(username: 'a', token: 't', salt: 's'),
    device: const DeviceInfo(id: 'me', name: 'me', client: 'test', api: Api.subsonic, roles: [], capabilities: []),
  );

  for (final device in devices) {
    client.devices[device.id] = device;
  }

  final player = PlayerController(FakeEngine(), api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'Notebook'),
    api,
    player,
    ConnectController(player: player, client: client),
  );
  await tester.pumpWidget(
    MaterialApp(
      // Above the navigator, as in the app, so that the sheet sees it.
      builder: (context, child) => MediaQuery(
        // As DirectionalNavigation says it, on a TV.
        data: MediaQuery.of(context)
            .copyWith(navigationMode: television ? NavigationMode.directional : NavigationMode.traditional),
        child: ServicesScope(services: services, child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showDevicesSheet(context), child: const Text('abrir')),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// The icon beside "Este aparelho".
Finder thisDevice(HugeIconData icon) =>
    find.descendant(of: find.widgetWithText(ListTile, 'Este aparelho (Notebook)'), matching: themedIcon(icon));

void main() {
  testWidgets('the picker lists only the devices that are online', (tester) async {
    await openSheet(tester, [
      player('tv', 'Sala de estar', online: true),
      player('old', 'Celular antigo', online: false),
    ]);
    expect(find.text('Este aparelho (Notebook)'), findsOneWidget);
    expect(find.text('Sala de estar'), findsOneWidget);
    expect(find.text('Celular antigo'), findsNothing);
  });

  testWidgets('each device that plays has the equalizer, and each one says what it plays or has paused', (
    tester,
  ) async {
    StampedState holding(String title, PlaybackStatus status, {required int at}) => StampedState(
      status: status,
      positionMs: 0,
      at: at,
      index: 0,
      queue: [QueueItem(id: title, title: title, artist: 'Aerosmith')],
    );
    await openSheet(tester, [
      player('tv', 'Sala de estar', online: true, state: holding('Dream On', PlaybackStatus.playing, at: 1)),
      player('bedroom', 'Quarto', online: true, state: holding('Walk This Way', PlaybackStatus.playing, at: 2)),
      player('kitchen', 'Cozinha', online: true, state: holding('Sweet Emotion', PlaybackStatus.paused, at: 3)),
      player('phone', 'Celular', online: true),
    ], size: const Size(800, 1200));
    Finder inTile(String name, Finder finder) =>
        find.descendant(of: find.widgetWithText(ListTile, name), matching: finder);

    expect(inTile('Sala de estar', find.text('Dream On · Aerosmith')), findsOneWidget);
    expect(inTile('Sala de estar', find.byType(Equalizer)), findsOneWidget);
    expect(inTile('Quarto', find.text('Walk This Way · Aerosmith')), findsOneWidget);
    expect(inTile('Quarto', find.byType(Equalizer)), findsOneWidget, reason: 'two play at once');
    expect(inTile('Cozinha', find.text('Sweet Emotion · Aerosmith')), findsOneWidget);
    expect(inTile('Cozinha', find.byType(Equalizer)), findsNothing, reason: 'paused');
    expect(inTile('Celular', find.text('test')), findsOneWidget, reason: 'with nothing, its app');
    expect(find.textContaining('Tocando'), findsNothing);
    expect(find.textContaining('Pausado'), findsNothing);
  });

  testWidgets('this device shows as a computer on a computer', variant: TargetPlatformVariant.desktop(), (
    tester,
  ) async {
    await openSheet(tester, []);
    expect(thisDevice(HugeIcons.strokeRoundedComputer), findsOneWidget);
  });

  testWidgets('as a phone on a phone', variant: TargetPlatformVariant.mobile(), (tester) async {
    await openSheet(tester, [], size: const Size(360, 640));
    expect(thisDevice(HugeIcons.strokeRoundedSmartphone), findsOneWidget);
  });

  testWidgets('as a tablet on a touch screen as wide as a tablet\'s', variant: TargetPlatformVariant.mobile(), (
    tester,
  ) async {
    await openSheet(tester, [], size: const Size(800, 1280));
    expect(thisDevice(HugeIcons.strokeRoundedTablet01), findsOneWidget);
  });

  testWidgets('and as a TV on a TV, which the remote drives, whatever its size', (tester) async {
    await openSheet(tester, [], size: const Size(1920, 1080), television: true);
    expect(thisDevice(HugeIcons.strokeRoundedTv01), findsOneWidget);
  });
}
