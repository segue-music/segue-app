import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The quality this device's player streams the media server's songs in: the files as they are, or transcoded down to a
/// bitrate, for a slow connection or a data plan.
enum StreamQuality {
  original(null),
  high(320),
  normal(160),
  low(96);

  const StreamQuality(this.maxBitRate);

  /// In kbps; null, the file as it is.
  final int? maxBitRate;
}

/// The quality the player streams in: the one the user picked, kept across launches (and sign-outs), or, until they pick
/// one, the original. A pick holds from the next song the player loads on.
class QualityChoice extends ValueNotifier<StreamQuality> {
  QualityChoice([super.value = StreamQuality.original]);

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'quality';

  /// The quality picked last; the original when none was.
  static Future<QualityChoice> load() async =>
      QualityChoice(StreamQuality.values.asNameMap()[await _prefs.getString(_key)] ?? StreamQuality.original);

  /// Streams in [quality] from now on, and on the next launches.
  Future<void> pick(StreamQuality quality) async {
    value = quality;
    await _prefs.setString(_key, quality.name);
  }
}
