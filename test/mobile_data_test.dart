import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/mobile_data.dart';

void main() {
  test('on mobile data only when it is the one connection, as the system sends through Wi-Fi or a cable first', () {
    expect(MobileData.inUse([ConnectivityResult.mobile]), isTrue);
    expect(MobileData.inUse([ConnectivityResult.mobile, ConnectivityResult.vpn]), isTrue, reason: 'a VPN over it');
    expect(MobileData.inUse([ConnectivityResult.wifi]), isFalse);
    expect(MobileData.inUse([ConnectivityResult.wifi, ConnectivityResult.mobile]), isFalse);
    expect(MobileData.inUse([ConnectivityResult.ethernet, ConnectivityResult.mobile]), isFalse);
    expect(MobileData.inUse([ConnectivityResult.none]), isFalse);
    expect(MobileData.inUse(const []), isFalse);
  });

  test('where the system can\'t say, it is no mobile data: with no binding (as the hub\'s tests start the services), '
      'or with no plugin', () async {
    for (final binding in [false, true]) {
      if (binding) {
        TestWidgetsFlutterBinding.ensureInitialized();
      }

      final mobileData = await MobileData.watch(askSystem: true);

      await Future<void>.delayed(const Duration(milliseconds: 100)); // for an error that would come later
      expect(mobileData.value, isFalse);
      mobileData.dispose();
    }
  });

  test('a computer isn\'t asked, and has no mobile data', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methods = MethodChannel('dev.fluttercommunity.plus/connectivity');
    var asked = false;

    // A system that would say mobile data.
    messenger.setMockMethodCallHandler(methods, (_) async {
      asked = true;
      return ['mobile'];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));

    final mobileData = await MobileData.watch();

    addTearDown(mobileData.dispose);
    expect(asked, isFalse);
    expect(mobileData.value, isFalse);
  });

  test('a system slow to say how it is online first still has what it says next count', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methods = MethodChannel('dev.fluttercommunity.plus/connectivity');
    const changes = EventChannel('dev.fluttercommunity.plus/connectivity_status');
    final listening = Completer<MockStreamHandlerEventSink>();

    messenger
      ..setMockMethodCallHandler(methods, (_) => Completer<Object?>().future)
      ..setMockStreamHandler(changes, MockStreamHandler.inline(onListen: (_, sink) => listening.complete(sink)));
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(methods, null)
        ..setMockStreamHandler(changes, null);
    });

    // Past the 2 s it waits for the first answer.
    final mobileData = await MobileData.watch(askSystem: true);

    addTearDown(mobileData.dispose);
    expect(mobileData.value, isFalse);
    (await listening.future.timeout(const Duration(seconds: 1))).success(['mobile']);
    await pumpEventQueue();
    expect(mobileData.value, isTrue);
  });
}
