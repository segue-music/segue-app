import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This device's volume, from 0 to 100, as the user last set it, here or from another device, kept across launches
/// (and sign-outs): the player starts at it. Until they set one, 100, as loud as the system's volume. The sleep timer's
/// fade isn't one: closed as the music faded, the app opens again as loud as before.
class VolumeChoice extends ValueNotifier<int> {
  VolumeChoice([super.value = 100]);

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'volume';

  /// The volume set last; all of it where none was.
  static Future<VolumeChoice> load() async => VolumeChoice((await _prefs.getInt(_key) ?? 100).clamp(0, 100));

  /// Plays at [volume] from the next launch on too.
  Future<void> pick(int volume) async {
    value = volume;
    await _prefs.setInt(_key, volume);
  }
}
