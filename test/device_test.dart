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

  testWidgets('the screen stays on while one keeps it so, though another that did goes as it comes', (tester) async {
    final keptOn = <Object?>[];

    messenger.setMockMethodCallHandler(channel, (call) async {
      keptOn.add(call.arguments);

      return null;
    });
    Widget keeping({required bool first, required bool second}) => Column(
      children: [
        if (first) const KeepScreenOn(key: ValueKey('first'), child: SizedBox()),
        if (second) const KeepScreenOn(key: ValueKey('second'), child: SizedBox()),
      ],
    );

    await tester.pumpWidget(keeping(first: true, second: false));
    expect(keptOn, [true]);
    await tester.pumpWidget(keeping(first: true, second: true));
    await tester.pumpWidget(keeping(first: false, second: true));
    expect(keptOn, [true], reason: 'the second still keeps it on');
    await tester.pumpWidget(keeping(first: false, second: false));
    expect(keptOn, [true, false]);
  });

  testWidgets('where the platform has no such channel (a computer), the screen goes off as the system has it', (
    tester,
  ) async {
    await tester.pumpWidget(const KeepScreenOn(child: SizedBox()));
    await tester.pumpWidget(const SizedBox());
  });

  test('the device goes by the name its system gives it (on Android, its settings), not the system\'s', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'deviceName' ? 'TV do quarto' : null);
    expect(await systemDeviceName(), 'TV do quarto');
  });

  test('where the platform has no such channel (Linux), it goes by the computer\'s name', () async {
    expect(await systemDeviceName(), Platform.localHostname);
  });
}
