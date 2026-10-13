import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/player/idle_player.dart';
import 'package:segue/ui/player/player_page.dart';
import 'package:segue/ui/player/queue_page.dart';

import 'directional_navigation_test.dart' show pumpFullHdHome;

/// Whether the screen is kept on, as the app last asked Android ([KeepScreenOn]).
bool? keptOn;

/// What the app asks Android of the screen, as [keptOn] says.
void watchScreen() {
  const channel = MethodChannel('segue/device');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  keptOn = null;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'keepScreenOn') {
      keptOn = call.arguments as bool;
    }

    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// A key, and the frame after it: with the music playing, the side rail's equalizer moves on and on, which
/// pumpAndSettle would wait for.
Future<void> pressOnce(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

/// As long as the player takes to slide in, and a little more.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('on a TV playing, the full-screen player comes as the remote is left alone a while, a key starting the '
      'wait over, and the screen stays on meanwhile', (tester) async {
    watchScreen();
    final player = await pumpFullHdHome(tester);
    await player.play();
    await tester.pump();
    expect(keptOn, isTrue, reason: 'for the player to come before the screen saver');

    await tester.pump(IdlePlayer.after - const Duration(seconds: 10));
    await pressOnce(tester, LogicalKeyboardKey.arrowDown);
    await tester.pump(IdlePlayer.after - const Duration(seconds: 10));
    expect(find.byType(PlayerPage), findsNothing, reason: 'the key started the wait over');

    await tester.pump(const Duration(seconds: 10));
    await settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(keptOn, isTrue);

    // Left alone again, it stays as it is.
    await tester.pump(IdlePlayer.after * 2);
    await settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);

    await player.pause();
    await tester.pump();
    expect(keptOn, isFalse, reason: 'paused, the TV goes to its screen saver as the system has it');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, paused, or playing on another device, nothing comes, and the screen goes off as the system has '
      'it', (tester) async {
    watchScreen();
    await pumpFullHdHome(tester);
    await tester.pump(IdlePlayer.after * 2);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(keptOn, isNull);
    await tester.pumpWidget(const SizedBox());

    // The music on a laptop, which the TV's app follows.
    await pumpFullHdHome(tester, followingAnotherDevice: true);
    await tester.pump(IdlePlayer.after * 2);
    await settle(tester);
    expect(find.byType(PlayerPage), findsNothing);
    expect(keptOn, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a computer, nothing comes', (tester) async {
    watchScreen();
    final player = await pumpFullHdHome(tester, television: false);
    await player.play();
    await tester.pump(IdlePlayer.after * 2);
    await settle(tester);
    expect(find.byType(PlayerPage), findsNothing);
    expect(keptOn, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, with the queue open over the player, the player comes back, rather than another over it', (
    tester,
  ) async {
    final player = await pumpFullHdHome(tester);
    await player.play();
    await tester.tap(find.byTooltip('Tocando agora'));
    await settle(tester);
    await tester.tap(find.byTooltip('Fila'));
    await settle(tester);
    expect(find.byType(QueuePage), findsOneWidget);

    await tester.pump(IdlePlayer.after);
    await settle(tester);
    expect(find.byType(QueuePage), findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, with the keyboard up, as someone types on it, the player waits for it to go', (tester) async {
    final player = await pumpFullHdHome(tester);
    await player.play();
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pump();
    await tester.pump(IdlePlayer.after);
    await settle(tester);
    expect(find.byType(PlayerPage), findsNothing);

    tester.view.resetViewInsets();
    await tester.pump();
    await tester.pump(IdlePlayer.after);
    await settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
