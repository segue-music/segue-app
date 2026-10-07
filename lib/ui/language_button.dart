import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../language_choice.dart';
import 'themed_icon.dart';

/// Picks the language the app shows, in a menu: the system's, or one of those the app has, each by its own name. The
/// one picked has a check: the system's, until another is. In the home's top bar, and in the sign-in's corner.
class LanguageButton extends StatelessWidget {
  const LanguageButton(this.choice, {super.key});

  final LanguageChoice choice;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    // By language code, and '' for the system's: a menu takes a null for no pick.
    final options = [
      ('', strings.systemLanguage),
      for (final language in LanguageChoice.languages)
        (language.languageCode, lookupAppLocalizations(language).languageName),
    ];
    final picked = choice.value?.languageCode ?? '';
    return PopupMenuButton<String>(
      tooltip: strings.language,
      icon: const ThemedIcon(HugeIcons.strokeRoundedTranslate),
      // The one picked highlighted, level with the button.
      initialValue: picked,
      onSelected: (code) => choice.pick(code.isEmpty ? null : Locale(code)),
      itemBuilder: (context) => [
        for (final (code, name) in options)
          PopupMenuItem(
            value: code,
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 24,
                  child: code == picked ? const ThemedIcon(HugeIcons.strokeRoundedTick02) : null,
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(name)),
              ],
            ),
          ),
      ],
    );
  }
}
