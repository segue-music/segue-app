import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/equalizer_choice.dart';
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

  test('off and flat until set, which the next launch, and a sign-out, keep', () async {
    expect((await EqualizerChoice.load()).value, const EqualizerSettings());

    final choice = EqualizerChoice();
    await choice.setOn(true);
    await choice.pick(EqualizerPreset.jazz);
    await Session.clear();
    expect((await EqualizerChoice.load()).value, const EqualizerSettings(on: true, preset: EqualizerPreset.jazz));

    await choice.setGain(9, -4);
    expect((await EqualizerChoice.load()).value, choice.value);
  });

  test('moving a band makes the curve shown the user\'s own, which another picked keeps for later', () async {
    final choice = EqualizerChoice(const EqualizerSettings(on: true, preset: EqualizerPreset.rock));
    await choice.setGain(5, 6);
    expect(choice.value.preset, EqualizerPreset.custom);
    expect(choice.value.gains, [5, 5, 4, 3, 1, 6, 1, 3, 4, 5], reason: 'rock\'s, with 1 kHz moved');

    await choice.pick(EqualizerPreset.pop);
    expect(choice.value.gains, EqualizerPreset.pop.gains);
    await choice.pick(EqualizerPreset.custom);
    expect(choice.value.gains, [5, 5, 4, 3, 1, 6, 1, 3, 4, 5]);
  });

  test('a band goes no further than 12 dB, up or down', () async {
    final choice = EqualizerChoice();
    await choice.setGain(0, 20);
    await choice.setGain(1, -20);
    expect(choice.value.gains.take(2), [12, -12]);
  });

  test('the player gets each band\'s gain by its frequency, and none while off', () {
    const settings = EqualizerSettings(on: true, preset: EqualizerPreset.bassBoost);
    expect(settings.bandGains, {31: 6, 63: 6, 125: 5, 250: 3, 500: 1, 1000: 0, 2000: 0, 4000: 0, 8000: 0, 16000: 0});
    expect(settings.copyWith(on: false).bandGains, isEmpty);
  });

  test('every curve has a gain for each band, within reach of the sliders', () {
    for (final preset in EqualizerPreset.values) {
      final gains = preset.gains ?? const EqualizerSettings().custom;
      expect(gains, hasLength(equalizerFrequencies.length), reason: preset.name);
      expect(gains, everyElement(inInclusiveRange(-maxBandGain, maxBandGain)), reason: preset.name);
    }
  });

  test('a curve saved that the app can\'t read is flat, and a curve it doesn\'t know, flat', () async {
    final prefs = SharedPreferencesAsync();

    for (final saved in [
      ['1', '2'],
      ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'loud'],
    ]) {
      await prefs.setStringList('equalizerCustom', saved);
      expect((await EqualizerChoice.load()).value.custom, everyElement(0), reason: '$saved');
    }

    await prefs.setStringList('equalizerCustom', ['30', '-30', '0', '0', '0', '0', '0', '0', '0', '0']);
    expect((await EqualizerChoice.load()).value.custom.take(2), [12, -12], reason: 'as far as a band goes');

    await prefs.setString('equalizerPreset', 'disco');
    expect((await EqualizerChoice.load()).value.preset, EqualizerPreset.flat);
  });
}
