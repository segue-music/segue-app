import 'dart:async';
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
}
