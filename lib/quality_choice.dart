import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The quality this device's player streams the media server's songs in: the files as they are, or transcoded down to a
/// bitrate, for a slow connection or a data plan; or, automatic, as the connection is.
enum StreamQuality {
  /// The original on Wi-Fi or a cable, and [normal] on mobile data.
  automatic(null),
  original(null),
  high(320),
  normal(160),
  low(96);

  const StreamQuality(this.maxBitRate);

  /// In kbps; null, the file as it is, and for [automatic], none of its own ([inUse]).
  final int? maxBitRate;

  /// The quality the player streams in, on mobile data or not: this one, or, for [automatic], the one for the
  /// connection.
  StreamQuality inUse({required bool onMobileData}) => switch (this) {
    automatic => onMobileData ? normal : original,
    _ => this,
  };
}

/// The quality the player streams in: the one the user picked, kept across launches (and sign-outs), or, until they pick
/// one, the automatic one. A pick holds from the next song the player loads on.
class QualityChoice extends ValueNotifier<StreamQuality> {
  QualityChoice([super.value = StreamQuality.automatic]);

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'quality';

  /// The quality picked last; the automatic one when none was.
  static Future<QualityChoice> load() async =>
      QualityChoice(StreamQuality.values.asNameMap()[await _prefs.getString(_key)] ?? StreamQuality.automatic);

  /// Streams in [quality] from now on, and on the next launches.
  Future<void> pick(StreamQuality quality) async {
    value = quality;
    await _prefs.setString(_key, quality.name);
  }
}
