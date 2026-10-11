import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';

/// The language the app shows: the one the user picked, kept across launches (and sign-outs), or until they pick one,
/// the system's (null). Of the system's languages, the first the app has; English when it has none of them.
class LanguageChoice extends ValueNotifier<Locale?> {
  LanguageChoice([super.value]);

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'language';

  /// The language the app falls back to when it has none of the system's.
  static const _fallback = Locale('en');

  /// The languages the app has, in the order its language menu lists them: by their own names.
  static List<Locale> get languages =>
      [...AppLocalizations.supportedLocales]
        ..sort((a, b) => lookupAppLocalizations(a).languageName.compareTo(lookupAppLocalizations(b).languageName));

  /// The language picked last; the system's (null) when none was, or one the app no longer has.
  static Future<LanguageChoice> load() async {
    final code = await _prefs.getString(_key);

    return LanguageChoice(
      AppLocalizations.supportedLocales.where((language) => language.languageCode == code).firstOrNull,
    );
  }

  /// Of [system]'s languages, in the order the system prefers them, the first the app has ([supported]); English when
  /// it has none of them. What MaterialApp shows while the user hasn't picked one. English isn't one more of the
  /// system's languages, after them: Flutter's resolution would take it, a perfect match, over one of theirs that
  /// matches without its country (es for es_ES).
  static Locale resolve(List<Locale>? system, Iterable<Locale> supported) {
    final languageCodes = {for (final language in supported) language.languageCode};
    final shared = [...?system].where((language) => languageCodes.contains(language.languageCode)).toList();

    return shared.isEmpty ? _fallback : basicLocaleListResolution(shared, supported);
  }

  /// Shows [language] from now on, and on the next launches; null, the system's.
  Future<void> pick(Locale? language) async {
    value = language;

    if (language == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, language.languageCode);
    }
  }
}
