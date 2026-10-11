import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The equalizer's bands, by their center frequencies, in Hz: ten, an octave apart, as music players have them.
const equalizerFrequencies = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// The most a band raises or lowers its frequencies, in dB.
const maxBandGain = 12;

/// A curve of the equalizer's bands, made for a kind of music, or the user's own ([custom]). The kinds' are Android's
/// presets, which have five bands, spread over these ten.
enum EqualizerPreset {
  /// Every band as it is.
  flat([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  rock([5, 5, 4, 3, 1, -1, 1, 3, 4, 5]),
  pop([-1, -1, 1, 2, 4, 5, 3, 1, -1, -2]),
  jazz([4, 4, 3, 2, 0, -2, 0, 2, 4, 5]),
  classical([5, 5, 4, 3, 0, -2, 1, 4, 4, 4]),
  electronic([6, 6, 3, 0, 1, 2, 3, 4, 2, 1]),
  hipHop([5, 5, 4, 3, 1, 0, 0, 1, 2, 3]),

  /// Voices forward: the middle up, the lowest and the highest down.
  vocal([-2, -2, -1, 1, 3, 4, 4, 2, 0, -1]),
  bassBoost([6, 6, 5, 3, 1, 0, 0, 0, 0, 0]),
  trebleBoost([0, 0, 0, 0, 0, 0, 1, 3, 5, 6]),

  /// The user's own, as they moved the bands.
  custom(null);

  const EqualizerPreset(this.gains);

  /// Each band's gain, in dB, in the order of [equalizerFrequencies]; null for [custom], whose are the user's.
  final List<int>? gains;
}

/// The equalizer as the user set it: [on] or not, the curve picked ([preset]), and their own ([custom]), kept while
/// another is picked.
@immutable
class EqualizerSettings {
  const EqualizerSettings({this.on = false, this.preset = EqualizerPreset.flat, this.custom = _flat});

  static const _flat = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  final bool on;
  final EqualizerPreset preset;

  /// The user's own curve: each band's gain, in dB, in the order of [equalizerFrequencies].
  final List<int> custom;

  /// The gains of the curve picked, in the order of [equalizerFrequencies], on or not: what the bands show.
  List<int> get gains => preset.gains ?? custom;

  /// What the player plays with: each band's gain, in dB, by its frequency; none while off.
  Map<int, double> get bandGains =>
      on ? {for (final (i, frequency) in equalizerFrequencies.indexed) frequency: gains[i].toDouble()} : const {};

  EqualizerSettings copyWith({bool? on, EqualizerPreset? preset, List<int>? custom}) =>
      EqualizerSettings(on: on ?? this.on, preset: preset ?? this.preset, custom: custom ?? this.custom);

  @override
  bool operator ==(Object other) =>
      other is EqualizerSettings && other.on == on && other.preset == preset && listEquals(other.custom, custom);

  @override
  int get hashCode => Object.hash(on, preset, Object.hashAll(custom));

  @override
  String toString() => 'EqualizerSettings(on: $on, preset: ${preset.name}, custom: $custom)';
}

/// The equalizer of this device's player, as the user set it, kept across launches (and sign-outs); until they turn it
/// on, off. A change holds at once, for the song that plays too.
class EqualizerChoice extends ValueNotifier<EqualizerSettings> {
  EqualizerChoice([super.value = const EqualizerSettings()]);

  static final _prefs = SharedPreferencesAsync();
  static const _onKey = 'equalizer';
  static const _presetKey = 'equalizerPreset';
  static const _customKey = 'equalizerCustom';

  /// The equalizer as it was last set; off, flat, when it never was. A curve saved that the app can't read is flat.
  static Future<EqualizerChoice> load() async {
    final saved = await _prefs.getStringList(_customKey);
    final custom = saved?.map(int.tryParse).toList();

    return EqualizerChoice(
      EqualizerSettings(
        on: await _prefs.getBool(_onKey) ?? false,
        preset: EqualizerPreset.values.asNameMap()[await _prefs.getString(_presetKey)] ?? EqualizerPreset.flat,
        custom: custom != null && custom.length == equalizerFrequencies.length && !custom.contains(null)
            ? [for (final gain in custom) gain!.clamp(-maxBandGain, maxBandGain)]
            : EqualizerSettings._flat,
      ),
    );
  }

  /// Turns the equalizer on, or off, keeping its curve for the next time it is on.
  Future<void> setOn(bool on) async {
    value = value.copyWith(on: on);
    await _prefs.setBool(_onKey, on);
  }

  /// Plays with [preset]'s curve, or, [EqualizerPreset.custom], the user's own.
  Future<void> pick(EqualizerPreset preset) async {
    value = value.copyWith(preset: preset);
    await _prefs.setString(_presetKey, preset.name);
  }

  /// Moves the band at [band] (of [equalizerFrequencies]) to [gain], in dB: the curve shown, with it moved, becomes the
  /// user's own, the one picked.
  Future<void> setGain(int band, int gain) async {
    final custom = [...value.gains]..[band] = gain.clamp(-maxBandGain, maxBandGain);
    value = value.copyWith(preset: EqualizerPreset.custom, custom: custom);
    await _prefs.setString(_presetKey, EqualizerPreset.custom.name);
    await _prefs.setStringList(_customKey, [for (final gain in custom) '$gain']);
  }
}
