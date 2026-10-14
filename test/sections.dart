import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/l10n/app_localizations.dart';

/// Opens the library's [section] (albums, artists, genres or playlists, by its name in [strings], Portuguese's unless
/// given): on a wide screen from the side rail; on a phone from the bar at the bottom, the albums, the artists and the
/// playlists as the library's tabs, and the genres in the search, before something is searched.
Future<void> openSection(WidgetTester tester, String section, {AppLocalizations? strings}) async {
  final words = strings ?? lookupAppLocalizations(const Locale('pt'));
  final bar = find.byType(NavigationBar);

  if (bar.evaluate().isEmpty) {
    await tester.tap(find.byTooltip(section));
  } else if (section == words.genres) {
    await tester.tap(find.descendant(of: bar, matching: find.text(words.search)));
  } else {
    await tester.tap(find.descendant(of: bar, matching: find.text(words.library)));
    await tester.pumpAndSettle();
    await tapLibraryTab(tester, section);
  }

  await tester.pumpAndSettle();
}

/// On a phone, taps the library's tab [name], in the top bar, where they scroll sideways when they don't fit: as with
/// the tests' font, whose letters are all as wide as tall.
Future<void> tapLibraryTab(WidgetTester tester, String name) async {
  final tab = find.descendant(of: find.byType(TabBar), matching: find.text(name));

  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}
