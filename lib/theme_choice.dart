import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app shows its light theme or its dark one: the one the user picked, kept across launches (and sign-outs),
/// or until they pick one, the system's.
class ThemeChoice extends ValueNotifier<ThemeMode> {
  ThemeChoice([super.value = ThemeMode.system]);

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'theme';

  /// The theme picked last; the system's when none was.
  static Future<ThemeChoice> load() async =>
      ThemeChoice(ThemeMode.values.asNameMap()[await _prefs.getString(_key)] ?? ThemeMode.system);

  /// Shows [mode] from now on, and on the next launches.
  Future<void> pick(ThemeMode mode) async {
    value = mode;
    await _prefs.setString(_key, mode.name);
  }
}
