import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How long this device's player crossfades the songs for, each fading into the next, or none, the songs one right after
/// the other (gapless): as the user picked, kept across launches (and sign-outs), or, until they pick, none. A pick holds
/// at once, for the song that plays too. It is this device's own, as autoplay is: the protocol knows nothing of it.
class CrossfadeChoice extends ValueNotifier<Duration> {
  CrossfadeChoice([super.value = Duration.zero]);

  /// The lengths offered, none first.
  static const lengths = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 6),
    Duration(seconds: 8),
    Duration(seconds: 10),
    Duration(seconds: 12),
  ];

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'crossfade';

  /// The length picked last; none where none was, or one the app no longer offers.
  static Future<CrossfadeChoice> load() async {
    final seconds = await _prefs.getInt(_key);

    return CrossfadeChoice(lengths.firstWhere((length) => length.inSeconds == seconds, orElse: () => Duration.zero));
  }

  /// Crossfades the songs for [length] from now on, and on the next launches.
  Future<void> pick(Duration length) async {
    value = length;
    await _prefs.setInt(_key, length.inSeconds);
  }
}
