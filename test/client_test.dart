import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:web_socket_channel/adapter_web_socket_channel.dart';

void main() {
  test('a client closes at once while its connection is still opening, or when it never opened, the hub out of '
      'reach', () async {
    for (final connection in [
      () => Future<Never>.error(const SocketException('no route to host')),
      () => Completer<Never>().future,
    ]) {
      final client = SegueClient(
        url: Uri.parse('wss://hub.example/connect/v1/ws'),
        auth: const Auth.subsonic(username: 'alice', token: '-', salt: '-'),
        device: const DeviceInfo(
          id: 'phone',
          name: 'Phone',
          client: 'test',
          api: Api.subsonic,
          roles: [],
          capabilities: [],
        ),
        channelFactory: (_) => AdapterWebSocketChannel(connection()),
      );

      unawaited(client.start());
      await pumpEventQueue();
      await client.close().timeout(const Duration(seconds: 1));
    }
  });

  test(
    'a client closed while its connection opens leaves before saying hello, and the log tells of no refusal',
    () async {
      final hub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final asked = Completer<void>();
      final open = Completer<void>();
      final received = <Object?>[];
      final left = Completer<void>();
      final warnings = <LogRecord>[];

      hub.listen((request) async {
        asked.complete();
        await open.future;

        final socket = await WebSocketTransformer.upgrade(request);

        socket.listen(received.add, onDone: left.complete);
      });
      addTearDown(() => hub.close(force: true));

      final logging = Logger.root.onRecord.where((record) => record.level >= Level.WARNING).listen(warnings.add);

      addTearDown(logging.cancel);

      final client = SegueClient(
        url: Uri.parse('ws://127.0.0.1:${hub.port}/connect/v1/ws'),
        auth: const Auth.subsonic(username: 'alice', token: '-', salt: '-'),
        device: const DeviceInfo(
          id: 'phone',
          name: 'Phone',
          client: 'test',
          api: Api.subsonic,
          roles: [],
          capabilities: [],
        ),
      );

      unawaited(client.start());
      await asked.future;
      await client.close();
      open.complete();
      await left.future.timeout(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(received, isEmpty);
      expect(warnings, isEmpty);
    },
  );

  test('the other devices stay as they were while the connection is made again, and go offline once the hub is out of '
      'reach', () async {
    final hub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    const laptop = DeviceInfo(
      id: 'laptop',
      name: 'Laptop',
      client: 'test',
      api: Api.subsonic,
      roles: [Role.player],
      capabilities: [],
    );

    // A hub that welcomes each hello, listing the laptop online.
    hub.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);

      sockets.add(socket);
      socket.listen(
        (_) => socket.add(
          jsonEncode({
            'type': 'welcome',
            'serverTime': DateTime.now().millisecondsSinceEpoch,
            'devices': [
              {...laptop.toJson(), 'online': true},
            ],
          }),
        ),
      );
    });
    addTearDown(() => hub.close(force: true));

    final client = SegueClient(
      url: Uri.parse('ws://127.0.0.1:${hub.port}/connect/v1/ws'),
      auth: const Auth.subsonic(username: 'alice', token: '-', salt: '-'),
      device: const DeviceInfo(
        id: 'phone',
        name: 'Phone',
        client: 'test',
        api: Api.subsonic,
        roles: [],
        capabilities: [],
      ),
      // Over the second [SegueClient.start] waits before it connects again.
      outOfReachAfter: const Duration(seconds: 2),
    );
    var listedOffline = false;

    client.addListener(() => listedOffline |= client.devices['laptop']?.online == false);
    unawaited(client.start());
    addTearDown(client.close);
    await until(() => client.status == HubStatus.connected);

    // The hub restarting.
    await sockets.single.close(CloseCode.goingAway);
    await until(() => sockets.length == 2 && client.status == HubStatus.connected);
    expect(listedOffline, isFalse);

    // The hub gone.
    await hub.close(force: true);
    await sockets.last.close(CloseCode.goingAway);
    await until(() => client.devices['laptop']?.online == false);
    expect(client.devices['laptop']?.info.name, 'Laptop');
  });
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));

  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out');
    }

    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
