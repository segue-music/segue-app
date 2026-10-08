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

  test('the files as they are until a pick, which the next launch, and a sign-out, keep', () async {
    expect((await QualityChoice.load()).value, StreamQuality.original);

    await QualityChoice().pick(StreamQuality.low);
    await Session.clear();
    expect((await QualityChoice.load()).value, StreamQuality.low);

    await QualityChoice().pick(StreamQuality.high);
    expect((await QualityChoice.load()).value, StreamQuality.high);
  });

  test('a quality saved that the app doesn\'t know is the original', () async {
    await SharedPreferencesAsync().setString('quality', 'lossless');
    expect((await QualityChoice.load()).value, StreamQuality.original);
  });

  test('each quality but the original has a bitrate, lower down the list', () {
    final bitRates = [for (final quality in StreamQuality.values.skip(1)) quality.maxBitRate!];
    expect(StreamQuality.original.maxBitRate, isNull);
    expect(bitRates, [...bitRates]..sort((a, b) => b.compareTo(a)));
  });
}
