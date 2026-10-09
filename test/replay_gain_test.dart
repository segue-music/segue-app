import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/replay_gain_choice.dart';
import 'package:segue/server/models.dart';
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

  test('off until a pick, which the next launch, and a sign-out, keep', () async {
    expect((await ReplayGainChoice.load()).value, ReplayGainMode.off);

    await ReplayGainChoice().pick(ReplayGainMode.automatic);
    await Session.clear();
    expect((await ReplayGainChoice.load()).value, ReplayGainMode.automatic);

    await ReplayGainChoice().pick(ReplayGainMode.album);
    expect((await ReplayGainChoice.load()).value, ReplayGainMode.album);
  });

  test('a way saved that the app doesn\'t know is off', () async {
    await SharedPreferencesAsync().setString('replayGain', 'smart');
    expect((await ReplayGainChoice.load()).value, ReplayGainMode.off);
  });

  test('a song plays with its own gain, or its album\'s, the other where the server gives only that one', () {
    const both = ReplayGain(trackGain: -8.5, albumGain: -6);
    expect((both.decibels(album: false), both.decibels(album: true)), (-8.5, -6));
    const own = ReplayGain(trackGain: -8.5);
    expect((own.decibels(album: false), own.decibels(album: true)), (-8.5, -8.5));
    const album = ReplayGain(albumGain: -6);
    expect((album.decibels(album: false), album.decibels(album: true)), (-6, -6));
  });

  test('a gain never makes a song clip: no louder than its peak lets it, or than it is where its peak isn\'t said', () {
    // Its loudest sample at half the loudest a file holds: 6 dB to spare.
    const quiet = ReplayGain(trackGain: 9, albumGain: 4, trackPeak: 0.5, albumPeak: 0.5);
    expect(quiet.decibels(album: false), closeTo(6.02, 0.01));
    expect(quiet.decibels(album: true), 4);
    // Past the loudest a file holds, as a lossy file may be: lowered even where the gain would raise it none.
    expect(const ReplayGain(trackGain: 0, trackPeak: 1.122).decibels(album: false), closeTo(-1, 0.01));
    expect(const ReplayGain(trackGain: 3).decibels(album: false), 0, reason: 'Jellyfin says no peak');
    expect(const ReplayGain(trackGain: 3, trackPeak: 0).decibels(album: false), 0, reason: 'no peak either');
    expect(const ReplayGain(trackGain: -7).decibels(album: false), -7);
    // The album's gain goes with the album's peak, and the song's with its own.
    const peaks = ReplayGain(trackGain: 5, albumGain: 5, trackPeak: 0.25, albumPeak: 1);
    expect((peaks.decibels(album: false), peaks.decibels(album: true)), (5, 0));
    const ownPeak = ReplayGain(trackGain: 5, trackPeak: 0.25, albumPeak: 1);
    expect(ownPeak.decibels(album: true), 5, reason: 'its own gain, with its own peak');
  });

  test('a preamp makes a song louder than its gain, still no louder than its peak lets it', () {
    const gain = ReplayGain(trackGain: -8, albumGain: 3, trackPeak: 0.5, albumPeak: 0.5);
    expect(gain.decibels(album: false, preamp: 4), -4);
    expect(gain.decibels(album: true, preamp: 4), closeTo(6.02, 0.01));
    expect(const ReplayGain(trackGain: -2).decibels(album: false, preamp: 4), 0, reason: 'no peak said');
  });
}
