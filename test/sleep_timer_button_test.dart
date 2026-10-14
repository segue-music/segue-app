import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/services.dart';
import 'package:segue/ui/player/now_playing_bar.dart';
import 'package:segue/ui/player/player_page.dart';
import 'package:segue/ui/widgets/themed_icon.dart';

import 'player_page_test.dart' show onPage, openPlayer, pumpBar, tvPlaying;

/// The sleep timer's button, by its tooltip, which says its state.
Finder button(String tooltip) => find.byTooltip(tooltip);

/// In the timer's sheet, the line that says [text].
Finder line(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(ListTile, text));

/// Opens the timer's sheet from its button, which [tooltip] names, and picks the line that says [text].
Future<void> pick(WidgetTester tester, String tooltip, String text) async {
  await tester.tap(button(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(line(text));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsNothing, reason: 'a pick closes the sheet');
}

void main() {
  testWidgets('on a wide screen, the bar\'s moon opens the sleep timer\'s sheet, whose while picked shows on it, until '
      'it\'s turned off', (tester) async {
    await pumpBar(tester, size: const Size(1000, 700), sleepTimer: true);

    final bar = find.byType(NowPlayingBar);

    expect(find.descendant(of: bar, matching: button('Timer de sono')), findsOneWidget);

    await tester.tap(button('Timer de sono'));
    await tester.pumpAndSettle();

    for (final text in ['5 minutos', '15 minutos', '30 minutos', '45 minutos', '1 hora', 'Fim desta música']) {
      expect(line(text), findsOneWidget, reason: text);
    }

    expect(line('Desligar o timer'), findsNothing, reason: 'off');
    await tester.tap(line('15 minutos'));
    await tester.pumpAndSettle();

    final on = button('A música pausa em 15 minutos');

    expect(on, findsOneWidget);
    expect(
      find.descendant(of: on, matching: find.text('15')),
      findsOneWidget,
      reason: 'the minutes left, on it',
    );

    final moon = tester.widget<ThemedIcon>(find.descendant(of: on, matching: find.byType(ThemedIcon)));

    expect(moon.icon, HugeIcons.strokeRoundedMoon02);
    expect(moon.color, Theme.of(tester.element(bar)).colorScheme.primary, reason: 'tinted, on');

    await tester.tap(on);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('A música pausa em 15 minutos')),
      findsOne,
    );
    await tester.tap(line('Desligar o timer'));
    await tester.pumpAndSettle();
    expect(button('Timer de sono'), findsOneWidget);
    expect(find.descendant(of: button('Timer de sono'), matching: find.text('15')), findsNothing);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('the song\'s end, picked, shows as picked, with no minutes', (tester) async {
    await pumpBar(tester, size: const Size(1000, 700), sleepTimer: true);
    await pick(tester, 'Timer de sono', 'Fim desta música');

    final on = button('A música pausa quando a atual acabar');

    expect(on, findsOneWidget);
    expect(find.descendant(of: on, matching: find.byType(Text)), findsNothing);

    await tester.tap(on);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(line('Fim desta música')).selected, isTrue);
    await tester.tap(line('Desligar o timer'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the moon is in the full-screen player\'s top right corner, and not in the bar', (
    tester,
  ) async {
    await pumpBar(tester, sleepTimer: true);
    expect(button('Timer de sono'), findsNothing, reason: 'the bar has no room');

    await openPlayer(tester);

    final moon = onPage(button('Timer de sono'));

    expect(moon, findsOneWidget);

    final appBar = tester.getRect(onPage(find.byType(AppBar)));

    expect(tester.getRect(moon).right, moreOrLessEquals(appBar.right, epsilon: 8));
    expect(tester.getRect(moon).center.dy, moreOrLessEquals(appBar.center.dy, epsilon: 1));

    await pick(tester, 'Timer de sono', '30 minutos');
    expect(onPage(button('A música pausa em 30 minutos')), findsOneWidget);
    ServicesScope.of(tester.element(find.byType(PlayerPage))).sleepTimer!.cancel();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('while another device plays, there is no moon: the timer pauses this device\'s player', (tester) async {
    await pumpBar(
      tester,
      size: const Size(1000, 700),
      sleepTimer: true,
      client: tvPlaying(const QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', album: 'Aerosmith')),
    );
    expect(find.text('Dream On'), findsOneWidget);
    expect(button('Timer de sono'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
