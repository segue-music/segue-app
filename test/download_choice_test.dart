import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/download_choice.dart';
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

  test('the files as they are, over Wi-Fi alone, until a pick, which the next launch, and a sign-out, keep', () async {
    final first = await DownloadChoice.load(mobileData: true);

    expect(first.value, const DownloadSettings());
    expect(first.value.quality, StreamQuality.original);
    expect(first.value.onMobileData, isFalse);

    await first.pickQuality(StreamQuality.normal);
    await first.pickOnMobileData(true);
    await Session.clear();

    final again = await DownloadChoice.load(mobileData: true);

    expect(again.value, const DownloadSettings(quality: StreamQuality.normal, onMobileData: true));
  });

  test('the automatic quality, or one the app doesn\'t know, saved as the downloads\', is the original', () async {
    await SharedPreferencesAsync().setString('downloadQuality', 'automatic');
    expect((await DownloadChoice.load(mobileData: true)).value.quality, StreamQuality.original);
    await SharedPreferencesAsync().setString('downloadQuality', 'lossless');
    expect((await DownloadChoice.load(mobileData: true)).value.quality, StreamQuality.original);
  });

  test('the downloads wait on mobile data, unless the user lets them go over it', () {
    final settings = ValueNotifier(const DownloadSettings());
    final mobileData = ValueNotifier(false);
    final hold = DownloadHold(settings, mobileData);

    addTearDown(hold.dispose);
    expect(hold.value, isFalse);

    mobileData.value = true;
    expect(hold.value, isTrue);

    settings.value = const DownloadSettings(onMobileData: true);
    expect(hold.value, isFalse);

    settings.value = const DownloadSettings();
    mobileData.value = false;
    expect(hold.value, isFalse);
  });
}
