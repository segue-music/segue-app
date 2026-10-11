import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's colors, all the icon's (tool/icon.png), each in a light and a dark version, which the theme's mode picks.
enum Palette {
  /// The icon's pink, on the black around it in the dark: the app's first.
  segue,

  /// In the dark, the icon's pink on the wine inside its rounded square; in the light, pink backgrounds, with text in
  /// the wine.
  wine,

  /// Grays, the icon's black the darkest, with its pinks only where something stands out.
  neutral,
}

/// The theme as the user picked it: light, dark or the system's ([mode]), in which colors ([palette]), and with
/// stronger text and outlines ([highContrast]) or not.
@immutable
class ThemeSettings {
  const ThemeSettings({this.mode = ThemeMode.system, this.palette = Palette.segue, this.highContrast = false});

  final ThemeMode mode;
  final Palette palette;
  final bool highContrast;

  ThemeSettings copyWith({ThemeMode? mode, Palette? palette, bool? highContrast}) => ThemeSettings(
    mode: mode ?? this.mode,
    palette: palette ?? this.palette,
    highContrast: highContrast ?? this.highContrast,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings && other.mode == mode && other.palette == palette && other.highContrast == highContrast;

  @override
  int get hashCode => Object.hash(mode, palette, highContrast);

  @override
  String toString() => 'ThemeSettings(mode: ${mode.name}, palette: ${palette.name}, highContrast: $highContrast)';
}

/// The theme the app shows, as the user picked it, kept across launches (and sign-outs): until they pick, light or dark
/// as the system's, in the icon's pink on its black, and the contrast Material's.
class ThemeChoice extends ValueNotifier<ThemeSettings> {
  ThemeChoice([super.value = const ThemeSettings()]);

  static final _prefs = SharedPreferencesAsync();
  static const _modeKey = 'theme';
  static const _paletteKey = 'themePalette';
  static const _highContrastKey = 'themeHighContrast';

  /// The theme picked last; the system's mode and the first colors where none was, or one the app doesn't know.
  static Future<ThemeChoice> load() async => ThemeChoice(
    ThemeSettings(
      mode: ThemeMode.values.asNameMap()[await _prefs.getString(_modeKey)] ?? ThemeMode.system,
      palette: Palette.values.asNameMap()[await _prefs.getString(_paletteKey)] ?? Palette.segue,
      highContrast: await _prefs.getBool(_highContrastKey) ?? false,
    ),
  );

  /// Shows the theme in [mode], light, dark or the system's, from now on, and on the next launches.
  Future<void> pickMode(ThemeMode mode) async {
    value = value.copyWith(mode: mode);
    await _prefs.setString(_modeKey, mode.name);
  }

  /// Shows the theme in [palette]'s colors from now on, and on the next launches.
  Future<void> pickPalette(Palette palette) async {
    value = value.copyWith(palette: palette);
    await _prefs.setString(_paletteKey, palette.name);
  }

  /// Shows the theme with stronger text and outlines ([on]), or Material's, from now on, and on the next launches.
  Future<void> turnHighContrast(bool on) async {
    value = value.copyWith(highContrast: on);
    await _prefs.setBool(_highContrastKey, on);
  }
}
