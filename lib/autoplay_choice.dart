import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device's player goes on, as its queue ends, with songs like the last one (autoplay), rather than
/// stopping: as the user turned it, kept across launches (and sign-outs), or, until they do, on. Turned off, the songs
/// it added that haven't played go out of the queue.
class AutoplayChoice extends ValueNotifier<bool> {
  AutoplayChoice([super.value = true]);

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'autoplay';

  /// As turned last; on when it never was.
  static Future<AutoplayChoice> load() async => AutoplayChoice(await _prefs.getBool(_key) ?? true);

  /// Turns autoplay [on] or off from now on, and on the next launches.
  Future<void> turn(bool on) async {
    value = on;
    await _prefs.setBool(_key, on);
  }
}
