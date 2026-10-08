import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../language_choice.dart';
import 'menu_item_label.dart';
import 'themed_icon.dart';

/// Picks the language the app shows, in a menu: the system's, or one of those the app has, each by its own name. The
/// one picked has a check: the system's, until another is. In the sign-in's corner; once signed in, the settings pick
/// it.
class LanguageButton extends StatelessWidget {
  const LanguageButton(this.choice, {super.key});

  final LanguageChoice choice;

  /// The languages to pick from, each by its name: the system's (null), then those the app has, each by its own name.
  /// The language menu's, and the settings'.
  static List<(Locale?, String)> options(AppLocalizations strings) => [
    (null, strings.systemLanguage),
    for (final language in LanguageChoice.languages) (language, lookupAppLocalizations(language).languageName),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    // By language code, and '' for the system's: a menu takes a null for no pick.
    String code(Locale? language) => language?.languageCode ?? '';
    final picked = code(choice.value);
    return PopupMenuButton<String>(
      tooltip: strings.language,
      icon: const ThemedIcon(HugeIcons.strokeRoundedTranslate),
      // The one picked highlighted, level with the button.
      initialValue: picked,
      onSelected: (languageCode) => choice.pick(languageCode.isEmpty ? null : Locale(languageCode)),
      itemBuilder: (context) => [
        for (final (language, name) in options(strings))
          PopupMenuItem(
            value: code(language),
            child: MenuItemLabel(name, icon: code(language) == picked ? HugeIcons.strokeRoundedTick02 : null),
          ),
      ],
    );
  }
}
