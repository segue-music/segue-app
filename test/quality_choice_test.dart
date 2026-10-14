import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/quality_choice.dart';
import 'package:segue/session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  setUp(() async {
    await SharedPreferencesAsync().clear();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('the original quality until a pick, which the next launch, and a sign-out, keep', () async {
    expect((await QualityChoice.load(mobileData: true)).value, StreamQuality.original);

    await QualityChoice().pick(StreamQuality.low);
    await Session.clear();
    expect((await QualityChoice.load(mobileData: true)).value, StreamQuality.low);

    await QualityChoice().pick(StreamQuality.high);
    expect((await QualityChoice.load(mobileData: false)).value, StreamQuality.high);
  });

  test('a quality saved that the app doesn\'t know is the original one', () async {
    await SharedPreferencesAsync().setString('quality', 'lossless');
    expect((await QualityChoice.load(mobileData: true)).value, StreamQuality.original);
  });

  test('the automatic quality is one to pick only on a device with mobile data: on another, a computer, it is the '
      'original, which it would always stream', () async {
    final (phone, laptop) = (QualityChoice(mobileData: true), QualityChoice());

    addTearDown(phone.dispose);
    addTearDown(laptop.dispose);
    expect(phone.options, StreamQuality.values);
    expect(laptop.options, [StreamQuality.original, StreamQuality.high, StreamQuality.normal, StreamQuality.low]);

    await phone.pick(StreamQuality.automatic);
    expect((await QualityChoice.load(mobileData: true)).value, StreamQuality.automatic);
    expect((await QualityChoice.load(mobileData: false)).value, StreamQuality.original);
  });

  test(
    'the original comes first, and each quality after it and the automatic one has a bitrate, lower down the list',
    () {
      expect(StreamQuality.values.take(2), [StreamQuality.original, StreamQuality.automatic]);

      final bitRates = [for (final quality in StreamQuality.values.skip(2)) quality.maxBitRate!];

      expect(StreamQuality.original.maxBitRate, isNull);
      expect(bitRates, [...bitRates]..sort((a, b) => b.compareTo(a)));
    },
  );

  test('the automatic quality is the original on Wi-Fi or a cable, and the normal one on mobile data', () {
    expect(StreamQuality.automatic.inUse(onMobileData: false), StreamQuality.original);
    expect(StreamQuality.automatic.inUse(onMobileData: true), StreamQuality.normal);
    expect(StreamQuality.low.inUse(onMobileData: false), StreamQuality.low, reason: 'a pick holds anywhere');
    expect(StreamQuality.original.inUse(onMobileData: true), StreamQuality.original);
  });
}
