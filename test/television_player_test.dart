import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/ui/player/player_page.dart';
import 'package:segue/ui/player/lyrics_view.dart';
import 'package:segue/ui/player/player_controls.dart';
import 'package:segue/ui/player/television_player.dart';
import 'package:segue/ui/widgets/themed_icon.dart';

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

  testWidgets('on a TV, with the controls hidden, what plays moves slowly about its place, a few pixels in minutes, '
      'on the screen\'s whole pixels, and is back in it as they come', (tester) async {
    await pumpFullHdHome(tester);
    await openTvPlayer(tester);

    final place = tester.getRect(playerCover);
    final slider = tester.getRect(find.byType(Slider));

    await tester.pump(TelevisionControls.idle);
    await tester.pumpAndSettle();
    expect(controlsShown(), isFalse);

    final moves = <Offset>[];

    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(seconds: 6));

      final moved = tester.getRect(playerCover).topLeft - place.topLeft;

      moves.add(moved);
      expect(tester.getRect(find.byType(Slider)).topLeft - slider.topLeft, moved, reason: 'all of it together');
    }

    expect(moves.map((move) => move.dx.abs()).reduce(max), inInclusiveRange(10, 12));
    expect(moves.map((move) => move.dy.abs()).reduce(max), inInclusiveRange(6, 8));

    for (final (i, move) in moves.indexed.skip(1)) {
      expect((move - moves[i - 1]).distance, lessThan(2), reason: 'slowly');
      expect(
        [move.dx * 2, move.dy * 2],
        [(move.dx * 2).roundToDouble(), (move.dy * 2).roundToDouble()],
        reason: 'on whole pixels: two to each of its own',
      );
    }

    await press(tester, LogicalKeyboardKey.select);
    expect(controlsShown(), isTrue);
    expect(tester.getRect(playerCover), place);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, the player keeps the screen on while the music plays on another device too, which the home '
      'leaves as the system has it', (tester) async {
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
    await pumpFullHdHome(tester, followingAnotherDevice: true);
    await tester.pump();
    expect(keptOn, isEmpty, reason: 'the home leaves it as the system has it');

    await openTvPlayer(tester);
    expect(keptOn, [true]);
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

  testWidgets('on a TV following another device, where it plays shows beside the controls, clear of the cover, on a '
      'pill, and stays as they go, the words alone then, lined up with the time played', (tester) async {
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

    final pill = find.ancestor(of: playingOn, matching: find.byType(DecoratedBox)).first;
    double pillAlpha() => (tester.widget<DecoratedBox>(pill).decoration as BoxDecoration).color!.a;
    expect(pillAlpha(), 1);

    await tester.pump(TelevisionControls.idle);
    await tester.pumpAndSettle();
    expect(controlsShown(), isFalse);
    expect(playingOn, findsOneWidget);
    expect(
      find.ancestor(of: playingOn, matching: find.byType(AnimatedOpacity)),
      findsNothing,
      reason: 'not fading',
    );
    expect(pillAlpha(), 0);

    final played = find.descendant(of: find.byType(SeekSlider), matching: find.byType(Text)).first;

    expect(
      tester.getRect(find.descendant(of: pill, matching: find.byType(ThemedIcon))).left,
      tester.getRect(played).left,
    );

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(controlsShown(), isTrue);
    expect(pillAlpha(), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a TV, a title too long for the cover\'s width goes on two lines, which the cover gives its room to: the '
    'album still shows whole, above the slider',
    (tester) async {
      await pumpBar(
        tester,
        size: const Size(960, 540),
        television: true,
        client: tvPlaying(
          const QueueItem(
            id: 's1',
            title: 'We R All Gonna Die (Live at the Arena, Remastered)',
            artist: "Mother's Cake",
            album: 'We R All Gonna Die',
            durationMs: 128000,
          ),
        ),
      );
      await openPlayer(tester);

      final title = tester.getRect(onPage(find.text('We R All Gonna Die (Live at the Arena, Remastered)')));
      final albumText = onPage(find.text('We R All Gonna Die'));
      final album = tester.getRect(albumText);
      // The room the player has, above the slider, which cuts off what goes past it.
      final room = tester.getRect(find.ancestor(of: albumText, matching: find.byType(Scrollable)).first);

      expect(
        title.height,
        greaterThan(tester.getRect(onPage(find.text("Mother's Cake"))).height * 1.5),
        reason: 'two lines',
      );
      expect(album.bottom, lessThanOrEqualTo(room.bottom), reason: 'whole');
      expect(tester.getRect(playerCover).top, greaterThanOrEqualTo(room.top));
      await tester.pumpWidget(const SizedBox());
    },
  );

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
