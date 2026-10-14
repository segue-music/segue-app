import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The ARB file of [language] (lib/l10n), its messages by name.
Map<String, Object?> arb(String language) =>
    jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync()) as Map<String, Object?>;

/// The placeholders [message] uses: "{error}", and the "{count, plural, ...}" of a plural or a select. Not the cases'
/// texts, as in "=1{1 album}", whose brace follows the case's name.
Set<String> placeholders(String message) => {
  for (final match in RegExp(r'(?<![\w=])\{\s*(\w+)\s*[,}]').allMatches(message)) match[1]!,
};

void main() {
  final template = arb('pt');
  final names = template.keys.where((name) => !name.startsWith('@')).toList();

  test('each of Portuguese\'s messages says what it is, and declares the placeholders it uses', () {
    for (final name in names) {
      final about = template['@$name'] as Map<String, Object?>?;

      expect(about?['description'], isA<String>(), reason: name);

      final declared = (about?['placeholders'] as Map<String, Object?>?)?.keys.toSet() ?? {};

      expect(placeholders(template[name]! as String), declared, reason: name);
    }
  });

  for (final language in ['en', 'es']) {
    test('$language has every message, and none other, with the same placeholders', () {
      final translation = arb(language);

      expect(translation['@@locale'], language);
      expect(translation.keys.where((name) => !name.startsWith('@')).toList(), names);

      for (final name in names) {
        final message = translation[name]! as String;

        expect(message.trim(), isNotEmpty, reason: name);
        expect(placeholders(message), placeholders(template[name]! as String), reason: name);
      }
    });
  }
}
