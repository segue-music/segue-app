import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/device.dart';

const channel = MethodChannel('segue/device');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  test('on a TV, the focus always shows: a remote is all there is, never a touch', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'isTelevision');
    expect(await isTelevision(), isTrue);
    await adaptToTelevision();
    expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.alwaysTraditional);
  });

  test('elsewhere, Flutter goes on deciding by the last touch or key', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    await adaptToTelevision();
    expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.automatic);
  });

  test('where the platform has no such channel (Linux), it is no TV', () async {
    expect(await isTelevision(), isFalse);
    await adaptToTelevision();
    expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.automatic);
  });

  test('a phone, or a tablet with a SIM, has mobile data, as its system says', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'hasMobileData');
    expect(await hasMobileData(), isTrue);

    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await hasMobileData(), isFalse, reason: 'a TV, a tablet with Wi-Fi only');
  });

  test('where the platform has no such channel (a computer), there is no mobile data', () async {
    expect(await hasMobileData(), isFalse);
  });

  test('the device goes by the name its system gives it (on Android, its settings), not the system\'s', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'deviceName' ? 'TV do quarto' : null);
    expect(await systemDeviceName(), 'TV do quarto');
  });

  test('where the platform has no such channel (Linux), it goes by the computer\'s name', () async {
    expect(await systemDeviceName(), Platform.localHostname);
  });
}
