import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/equalizer_choice.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/ui/app/shortcuts.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/settings/equalizer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// The equalizer's page, on a phone tall enough for the whole of it, set as [settings]; [television] as on a TV.
Future<EqualizerChoice> pumpPage(
  WidgetTester tester, {
  EqualizerSettings settings = const EqualizerSettings(),
  bool television = false,
}) async {
  final choice = EqualizerChoice(settings);
  addTearDown(choice.dispose);
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: segueTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => DirectionalNavigation(enabled: television, child: child!),
      home: EqualizerPage(choice: choice),
    ),
  );

  return choice;
}

/// The band at [frequency].
Finder band(int frequency) =>
    find.byWidgetPredicate((widget) => widget is EqualizerBand && widget.frequency == frequency);

/// Where on [frequency]'s band its slider is at [gain] dB: 7.5 pixels a dB, from +12 dB, 40 pixels under its top (its
/// room, its gain over it, the room over the track), down.
Offset at(WidgetTester tester, int frequency, int gain) {
  final rect = tester.getRect(band(frequency));

  return Offset(rect.center.dx, rect.top + 40 + (maxBandGain - gain) * 7.5);
}

/// What [frequency]'s band shows over its slider.
String shown(WidgetTester tester, int frequency) =>
    tester.widgetList<Text>(find.descendant(of: band(frequency), matching: find.byType(Text))).first.data!;

/// The band that has the focus, by its frequency; null for none.
int? focusedBand() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EqualizerBand>()?.frequency;

void main() {
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  setUp(() => SharedPreferencesAsync().clear());

  testWidgets('off, the curve shows and nothing in it can be picked, until the switch turns it on', (tester) async {
    final choice = await pumpPage(tester, settings: const EqualizerSettings(preset: EqualizerPreset.rock));
    expect(
      [for (final frequency in equalizerFrequencies) shown(tester, frequency)],
      ['+5', '+5', '+4', '+3', '+1', '−1', '+1', '+3', '+4', '+5'],
    );
    expect(find.text('16k'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pop'));
    await tester.tapAt(at(tester, 1000, 12));
    await tester.pump();
    expect(choice.value, const EqualizerSettings(preset: EqualizerPreset.rock));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(choice.value.on, isTrue);
    expect((await EqualizerChoice.load()).value.on, isTrue, reason: 'kept');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pop'));
    await tester.pump();
    expect(choice.value.preset, EqualizerPreset.pop);
    expect(shown(tester, 1000), '+5');
  });

  testWidgets('a tap on a band moves it there, in whole dB, and makes the curve shown the user\'s own', (tester) async {
    final choice = await pumpPage(tester, settings: const EqualizerSettings(on: true, preset: EqualizerPreset.rock));
    await tester.tapAt(at(tester, 1000, 12));
    await tester.pump();
    expect(choice.value.preset, EqualizerPreset.custom);
    expect(choice.value.gains, [5, 5, 4, 3, 1, 12, 1, 3, 4, 5]);
    expect(shown(tester, 1000), '+12');
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Personalizado')).selected,
      isTrue,
      reason: 'the chip of the user\'s own',
    );

    await tester.tapAt(at(tester, 63, -3) + const Offset(0, 2));
    await tester.pump();
    expect(choice.value.gains.take(2), [5, -3]);
  });

  testWidgets('a double tap takes a band back to 0 dB; two taps further apart, in time or on the band, don\'t', (
    tester,
  ) async {
    final choice = await pumpPage(tester, settings: const EqualizerSettings(on: true, preset: EqualizerPreset.rock));
    await tester.tapAt(at(tester, 31, 6));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tapAt(at(tester, 31, 6) + const Offset(3, 4));
    await tester.pump();
    expect(choice.value.gains.first, 0);
    expect(choice.value.preset, EqualizerPreset.custom);

    await tester.tapAt(at(tester, 31, 6));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(at(tester, 31, 6));
    await tester.pump();
    expect(choice.value.gains.first, 6, reason: 'too far apart in time');

    await tester.tapAt(at(tester, 31, 12));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tapAt(at(tester, 31, -12));
    await tester.pump();
    expect(choice.value.gains.first, -12, reason: 'too far apart on the band');
  });

  testWidgets('a drag moves a band, up and down', (tester) async {
    final choice = await pumpPage(tester, settings: const EqualizerSettings(on: true));
    final drag = await tester.startGesture(at(tester, 250, 0));
    await drag.moveBy(const Offset(0, 30));
    await drag.moveBy(const Offset(0, 15));
    await tester.pump();
    expect(shown(tester, 250), '−6');
    await drag.moveBy(const Offset(0, -90));
    await drag.up();
    await tester.pump();
    expect(choice.value.gains[3], 6);
    expect(choice.value.gains.where((gain) => gain != 0), [6], reason: 'only that band');
  });

  testWidgets('with the keyboard, up and down move a band, and left and right go to the one beside it', (tester) async {
    final choice = await pumpPage(tester, settings: const EqualizerSettings(on: true));

    for (var i = 0; i < 30 && focusedBand() == null; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(focusedBand(), 31);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(choice.value.gains.first, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedBand(), 63);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(choice.value.gains.take(2), [2, -1]);
  });

  testWidgets('on a TV, up and down go on to the chips, until the center button takes the band, and again lets it go', (
    tester,
  ) async {
    final choice = await pumpPage(tester, settings: const EqualizerSettings(on: true), television: true);

    for (var i = 0; i < 30 && focusedBand() == null; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedBand(), 63);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(choice.value.gains[1], 2);
    expect(focusedBand(), 63, reason: 'still there');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(choice.value.gains[1], 2, reason: 'let go');
    expect(focusedBand(), isNull);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ChoiceChip>(), isNotNull);
  });

  testWidgets('a screen reader says each band\'s frequency and gain, and moves it', (tester) async {
    final semantics = tester.ensureSemantics();
    final choice = await pumpPage(tester, settings: const EqualizerSettings(on: true, preset: EqualizerPreset.vocal));
    expect(
      tester.getSemantics(band(1000)),
      matchesSemantics(
        isSlider: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        label: '1 kHz',
        value: '+4 dB',
        increasedValue: '+5 dB',
        decreasedValue: '+3 dB',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
      ),
    );
    expect(tester.getSemantics(band(31)), isSemantics(label: '31 Hz', value: '−2 dB', isSlider: true));

    tester.semantics.decrease(find.semantics.byLabel('1 kHz'));
    await tester.pump();
    expect(choice.value.gains[5], 3);
    semantics.dispose();
  });
}
