import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/ui/player/player_page.dart';
import 'package:segue/ui/player/lyrics_view.dart';
import 'package:segue/ui/player/player_controls.dart';
import 'package:segue/ui/player/television_player.dart';

import 'directional_navigation_test.dart' show focusedTip, press, pressUntil, pumpFullHdHome;
import 'player_page_test.dart' show onPage, openPlayer, playerCover, pumpBar, tvPlaying, verse, withLyrics;

/// The full-screen player on a TV, from the side rail.
Future<void> openTvPlayer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Tocando agora'));
  await tester.pumpAndSettle();
}

/// Whether the player's controls show: a button among them can be pressed.
bool controlsShown() => find.byTooltip('Próxima').hitTestable().evaluate().isNotEmpty;

void main() {
  testWidgets('on a TV, the full-screen player\'s controls show as it opens, play focused, and go after a while with '
      'no key pressed, the focus out of them; a key in between keeps them a while longer', (tester) async {
    await pumpFullHdHome(tester);
    await openTvPlayer(tester);
    expect(controlsShown(), isTrue);
    expect(focusedTip(), 'Tocar');

    await tester.pump(TelevisionControls.idle - const Duration(seconds: 1));
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Próxima');
    await tester.pump(TelevisionControls.idle - const Duration(seconds: 1));
    expect(controlsShown(), isTrue, reason: 'the key kept them');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controlsShown(), isFalse);
    expect(focusedTip(), isNull);
    expect(find.byType(Slider), findsOneWidget, reason: 'where the song is, still');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, with the controls hidden, the arrows and OK only bring them back, play focused, and do nothing '
      'else', (tester) async {
    final player = await pumpFullHdHome(tester);
    await openTvPlayer(tester);

    for (final key in [LogicalKeyboardKey.select, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown]) {
      await tester.pump(TelevisionControls.idle);
      await tester.pumpAndSettle();
      expect(controlsShown(), isFalse);

      await press(tester, key);
      expect(controlsShown(), isTrue, reason: '$key');
      expect(focusedTip(), 'Tocar', reason: '$key');
      expect(player.playing, isFalse, reason: '$key');
      expect(player.position, Duration.zero, reason: '$key');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, the remote\'s back hides the controls first, and only once they are hidden closes the player', (
    tester,
  ) async {
    await pumpFullHdHome(tester);
    await openTvPlayer(tester);

    // As the remote's back comes, a key the app may take; one it leaves goes to the system, which closes the page.
    Future<bool> back() =>
        tester.sendKeyEvent(LogicalKeyboardKey.goBack, platform: 'web', physicalKey: PhysicalKeyboardKey.browserBack);

    expect(await back(), isTrue);
    await tester.pumpAndSettle();
    expect(controlsShown(), isFalse);
    expect(find.byType(PlayerPage), findsOneWidget);

    expect(await back(), isFalse, reason: 'left to the system');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, the controls stay while something opened from them shows over the player', (tester) async {
    await pumpFullHdHome(tester);
    await openTvPlayer(tester);
    await pressUntil(tester, LogicalKeyboardKey.arrowRight, () => focusedTip() == 'Aparelhos');
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.pump(TelevisionControls.idle + const Duration(seconds: 1));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(controlsShown(), isTrue);
    expect(focusedTip(), 'Aparelhos');

    await tester.pump(TelevisionControls.idle);
    await tester.pumpAndSettle();
    expect(controlsShown(), isFalse, reason: 'and go a while after it closed');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, the screen stays on while the music plays, lyrics or not', (tester) async {
    const channel = MethodChannel('segue/device');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final keptOn = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'keepScreenOn') {
        keptOn.add(call.arguments);
      }

      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    // A song without lyrics, paused.
    final player = await pumpFullHdHome(tester);
    await openTvPlayer(tester);
    keptOn.clear();

    await player.play();
    await tester.pump();
    expect(keptOn, [true]);

    await player.pause();
    await tester.pump();
    expect(keptOn, [true, false]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV following another device, where it plays shows beside the controls, clear of the cover, and '
      'stays as they go', (tester) async {
    await pumpBar(
      tester,
      size: const Size(960, 540),
      television: true,
      client: tvPlaying(const QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', durationMs: 240000)),
    );
    await openPlayer(tester);
    final playingOn = find.text('Tocando em Sala de estar');
    expect(playingOn, findsOneWidget);
    expect(tester.getRect(playingOn).overlaps(tester.getRect(playerCover)), isFalse);

    await tester.pump(TelevisionControls.idle);
    await tester.pumpAndSettle();
    expect(controlsShown(), isFalse);
    expect(playingOn, findsOneWidget);
    expect(
      find.ancestor(of: playingOn, matching: find.byType(AnimatedOpacity)),
      findsNothing,
      reason: 'not fading',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, what plays lines up with the controls under it: the cover and where it plays start where the '
      'time played does, and the lyrics end where the song\'s length does', (tester) async {
    await pumpBar(
      tester,
      server: withLyrics(verse),
      size: const Size(960, 540),
      television: true,
      client: tvPlaying(const QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', durationMs: 240000)),
    );
    await openPlayer(tester);
    final times = find.descendant(of: find.byType(SeekSlider), matching: find.byType(Text));
    final played = tester.getRect(times.first);
    final length = tester.getRect(times.last);
    final playingOn = find.ancestor(of: find.text('Tocando em Sala de estar'), matching: find.byType(DecoratedBox));

    expect(tester.getRect(playerCover).left, played.left);
    expect(tester.getRect(playingOn.first).left, played.left);
    expect(tester.getRect(onPage(find.byType(LyricsView))).right, length.right);
    await tester.pumpWidget(const SizedBox());
  });
}
