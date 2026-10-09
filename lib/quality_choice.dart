import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device.dart';

/// The quality this device's player streams the media server's songs in: the files as they are, or transcoded down to a
/// bitrate, for a slow connection or a data plan; or, automatic, as the connection is.
enum StreamQuality {
  original(null),

  /// The original on Wi-Fi or a cable, and [normal] on mobile data.
  automatic(null),
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
/// one, the original. A pick holds from the next song the player loads on. The automatic one only on a device with
/// mobile data ([mobileData]): elsewhere it would always be the original.
class QualityChoice extends ValueNotifier<StreamQuality> {
  QualityChoice({StreamQuality value = StreamQuality.original, this.mobileData = false}) : super(value);

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'quality';

  /// Whether the device can go online through mobile data ([hasMobileData]).
  final bool mobileData;

  /// The qualities to pick from, in their order: the automatic one only with [mobileData].
  List<StreamQuality> get options => [
    for (final quality in StreamQuality.values)
      if (quality != StreamQuality.automatic || mobileData) quality,
  ];

  /// The quality picked last, among [options]; the original when none was, or when it was the automatic one on a device
  /// that has no mobile data, where the two stream alike. [mobileData] says whether it has, which tests set; by default,
  /// as the system says ([hasMobileData]).
  static Future<QualityChoice> load({@visibleForTesting bool? mobileData}) async {
    final choice = QualityChoice(mobileData: mobileData ?? await hasMobileData());
    final picked = StreamQuality.values.asNameMap()[await _prefs.getString(_key)];

    if (picked != null && choice.options.contains(picked)) {
      choice.value = picked;
    }

    return choice;
  }

  /// Streams in [quality] from now on, and on the next launches.
  Future<void> pick(StreamQuality quality) async {
    value = quality;
    await _prefs.setString(_key, quality.name);
  }
}
