import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device.dart';
import 'mobile_data.dart';
import 'quality_choice.dart';

/// How the app downloads songs: in which quality, the files as they are or transcoded down to a bitrate by the media
/// server, and whether over mobile data too, rather than waiting for Wi-Fi or a cable.
@immutable
class DownloadSettings {
  const DownloadSettings({this.quality = StreamQuality.original, this.onMobileData = false});

  /// Not [StreamQuality.automatic]: a download is kept, whatever connection it came over.
  final StreamQuality quality;

  final bool onMobileData;

  DownloadSettings copyWith({StreamQuality? quality, bool? onMobileData}) =>
      DownloadSettings(quality: quality ?? this.quality, onMobileData: onMobileData ?? this.onMobileData);

  @override
  bool operator ==(Object other) =>
      other is DownloadSettings && other.quality == quality && other.onMobileData == onMobileData;

  @override
  int get hashCode => Object.hash(quality, onMobileData);
}

/// How the app downloads, as the user picked it, kept across launches (and sign-outs); until they pick, the files as
/// they are, and over Wi-Fi or a cable alone. A pick holds for the songs downloaded from then on: those on the device
/// stay as they came.
class DownloadChoice extends ValueNotifier<DownloadSettings> {
  DownloadChoice({DownloadSettings value = const DownloadSettings(), this.mobileData = false}) : super(value);

  static final _prefs = SharedPreferencesAsync();
  static const _qualityKey = 'downloadQuality';
  static const _onMobileDataKey = 'downloadOnMobileData';

  /// Whether the device can go online through mobile data ([hasMobileData]): elsewhere, downloading over it is no
  /// choice.
  final bool mobileData;

  /// The qualities to pick from, in their order.
  static const qualities = [StreamQuality.original, StreamQuality.high, StreamQuality.normal, StreamQuality.low];

  /// As picked last. [mobileData] says whether the device has mobile data, which tests set; by default, as the system
  /// says ([hasMobileData]).
  static Future<DownloadChoice> load({@visibleForTesting bool? mobileData}) async {
    final quality = StreamQuality.values.asNameMap()[await _prefs.getString(_qualityKey)];

    return DownloadChoice(
      value: DownloadSettings(
        quality: qualities.contains(quality) ? quality! : StreamQuality.original,
        onMobileData: await _prefs.getBool(_onMobileDataKey) ?? false,
      ),
      mobileData: mobileData ?? await hasMobileData(),
    );
  }

  /// Downloads in [quality] from now on, and on the next launches.
  Future<void> pickQuality(StreamQuality quality) async {
    value = value.copyWith(quality: quality);
    await _prefs.setString(_qualityKey, quality.name);
  }

  /// Downloads over mobile data too ([on]), or waits for Wi-Fi or a cable, from now on, and on the next launches.
  Future<void> pickOnMobileData(bool on) async {
    value = value.copyWith(onMobileData: on);
    await _prefs.setBool(_onMobileDataKey, on);
  }
}

/// Whether the downloads wait: on mobile data ([MobileData]), where the user keeps them off it ([DownloadSettings]), as
/// either changes.
class DownloadHold extends ValueNotifier<bool> {
  DownloadHold(this._settings, this._mobileData) : super(false) {
    _settings.addListener(_update);
    _mobileData.addListener(_update);
    _update();
  }

  final ValueListenable<DownloadSettings> _settings;
  final ValueListenable<bool> _mobileData;

  void _update() => value = _mobileData.value && !_settings.value.onMobileData;

  @override
  void dispose() {
    _settings.removeListener(_update);
    _mobileData.removeListener(_update);
    super.dispose();
  }
}
