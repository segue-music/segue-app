import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/libmpv_licenses.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/settings/licenses_page.dart';

/// [licenses] in place of those Flutter gathers, until the test ends.
void useLicenses(List<LicenseEntry> licenses) {
  LicenseRegistry.reset();
  LicenseRegistry.addLicense(() => Stream.fromIterable(licenses));
  addTearDown(LicenseRegistry.reset);
}

/// [page] in the app's theme and in Portuguese, under a button, for the focus to go to from it.
Future<void> pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      theme: segueTheme(Brightness.light),
      home: Column(
        children: [
          TextButton(onPressed: () {}, child: const Text('above')),
          Expanded(child: page),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The names of the libraries whose licenses Flutter gathers, and the paragraphs of each.
Future<List<(List<String>, List<String>)>> gathered() async => [
  await for (final license in LicenseRegistry.licenses)
    (license.packages.toList(), [for (final paragraph in license.paragraphs) paragraph.text]),
];

void main() {
  testWidgets('the licenses are a package a line, by name whatever its case, with how many it has; one picked opens '
      'them, a line between them, their titles centered', (tester) async {
    useLicenses(const [
      LicenseEntryWithLineBreaks(['segue'], 'MIT License\n\nCopyright (c) the authors'),
      LicenseEntryWithLineBreaks(['Mbed TLS'], '                 Apache License\n\nLicensed under the Apache License'),
      LicenseEntryWithLineBreaks(['async', 'collection'], 'Copyright 2015, the Dart project authors.'),
      LicenseEntryWithLineBreaks(['async'], 'Another license of async.'),
    ]);
    await pumpPage(tester, const LicensesPage());
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Licenças')), findsOneWidget);
    final names = ['async', 'collection', 'Mbed TLS', 'segue'];
    final tops = [for (final name in names) tester.getTopLeft(find.text(name)).dy];
    expect([...tops]..sort(), tops, reason: 'in this order, top to bottom');
    expect(find.descendant(of: find.widgetWithText(ListTile, 'async'), matching: find.text('2 licenças')), findsOne);
    expect(find.descendant(of: find.widgetWithText(ListTile, 'segue'), matching: find.text('1 licença')), findsOne);

    await tester.tap(find.text('async'));
    await tester.pumpAndSettle();
    expect(find.byType(PackageLicensesPage), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('async')), findsOneWidget);
    expect(find.text('Copyright 2015, the Dart project authors.'), findsOneWidget, reason: 'the one it shares too');
    expect(find.text('Another license of async.'), findsOneWidget);
    expect(find.descendant(of: find.byType(PackageLicensesPage), matching: find.byType(Divider)), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mbed TLS'));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Apache License'));
    expect(title.textAlign, TextAlign.center);
    expect(title.style?.fontWeight, FontWeight.bold);
    expect(tester.widget<Text>(find.text('Licensed under the Apache License')).textAlign, isNot(TextAlign.center));
  });

  testWidgets('up and down scroll a package\'s licenses, which have nothing to focus, and at their ends go on, to what '
      'is around the page', (tester) async {
    final long = [for (var i = 0; i < 200; i++) 'Paragraph $i'].join('\n\n');
    await pumpPage(
      tester,
      PackageLicensesPage('long', [
        LicenseEntryWithLineBreaks(const ['long'], long),
      ]),
    );
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    bool aboveFocused() => Focus.of(tester.element(find.text('above'))).hasPrimaryFocus;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(position.viewportDimension / 2), reason: 'most of a screen down');
    expect(aboveFocused(), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(position.pixels, 0, reason: 'back to the top');
    expect(aboveFocused(), isFalse, reason: 'the up that scrolled stays in the page');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(aboveFocused(), isTrue, reason: 'from the top, up goes to what is above');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(aboveFocused(), isFalse, reason: 'and down back into the page');

    for (var i = 0; position.pixels < position.maxScrollExtent; i++) {
      expect(i, lessThan(100));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }

    expect(find.text('Paragraph 199'), findsOneWidget, reason: 'down to the end');
  });

  group('libmpv\'s licenses', () {
    setUp(LicenseRegistry.reset);

    testWidgets('are those of the libraries media_kit brings, each its notice, then the texts of its licenses', (
      tester,
    ) async {
      addLibmpvLicenses();
      final licenses = (await tester.runAsync(gathered))!;
      expect(
        [for (final (packages, _) in licenses) packages],
        [
          ['mpv'],
          ['FFmpeg'],
          ['Mbed TLS'],
        ],
      );
      final [(_, mpv), (_, ffmpeg), (_, mbedtls)] = licenses;
      expect(mpv.first, 'mpv (libmpv), which plays the music: https://mpv.io');
      expect(mpv.where((text) => text == 'GNU LESSER GENERAL PUBLIC LICENSE'), hasLength(1), reason: 'version 2.1');
      expect(mpv, contains('Version 2.1, February 1999'));
      expect(ffmpeg.first, startsWith('FFmpeg '));
      expect(ffmpeg.where((text) => text == 'GNU LESSER GENERAL PUBLIC LICENSE'), hasLength(2), reason: '2.1 and 3');
      expect(ffmpeg, contains('GNU GENERAL PUBLIC LICENSE'), reason: 'which version 3 of the Lesser builds on');
      expect(mbedtls.first, startsWith('Mbed TLS, '));
      expect(mbedtls, contains(startsWith('Apache License Version 2.0')));
    });

    testWidgets('are none on Linux, where the app plays with the system\'s libmpv', (tester) async {
      addLibmpvLicenses();
      expect(await tester.runAsync(gathered), isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
