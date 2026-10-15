import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/player/player.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/player/volume_control.dart';
import 'package:segue/ui/widgets/themed_icon.dart';
import 'package:segue/volume_choice.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'computer.dart';
import 'fakes.dart';
import 'player_page_test.dart' show credentials, pumpBar;

/// A hub client that sees the device tv play a song at [volume], taking setVolume where [canSetVolume], and answers
/// every command at once, keeping it ([sent]).
class TvClient extends SegueClient {
  TvClient({int volume = 40, bool canSetVolume = true})
    : super(
        url: Uri.parse('ws://unused'),
        auth: const Auth.subsonic(username: 'a', token: 't', salt: 's'),
        device: const DeviceInfo(id: 'me', name: 'me', client: 'test', api: Api.subsonic, roles: [], capabilities: []),
      ) {
    devices['tv'] = Device(
      info: DeviceInfo(
        id: 'tv',
        name: 'Sala de estar',
        client: 'test',
        api: Api.subsonic,
        roles: const [Role.player],
        capabilities: [
          for (final action in CommandAction.values)
            if (canSetVolume || action != CommandAction.setVolume) action,
        ],
      ),
      online: true,
      state: StampedState(
        status: PlaybackStatus.playing,
        positionMs: 61000,
        at: DateTime.now().millisecondsSinceEpoch,
        index: 0,
        volume: volume,
        queue: const [QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', durationMs: 268000)],
      ),
    );
  }

  final sent = <Command>[];

  @override
  Future<Result> command(String target, Command command) async {
    sent.add(command);

    return const Result(ok: true);
  }

  /// The volumes sent.
  List<int?> get volumes => [for (final command in sent) command.volume];

  /// As the TV reports its [volume].
  void reportVolume(int volume) {
    final device = devices['tv']!;
    devices['tv'] = Device(
      info: device.info,
      online: true,
      state: device.state!.merge(
        StampedState(status: PlaybackStatus.playing, positionMs: 61000, at: device.state!.at, volume: volume),
      ),
    );
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    notifyListeners();
  }
}

final volumeControl = find.byType(VolumeControl);
final volumeButton = find.descendant(of: volumeControl, matching: find.byType(IconButton));
final volumeSlider = find.descendant(of: volumeControl, matching: find.byType(Slider));

double sliderValue(WidgetTester tester) => tester.widget<Slider>(volumeSlider).value;

/// Where [value], from 0 to 100, is on the upright volume slider's track, inside its padding, from its bottom.
Offset onTrack(WidgetTester tester, double value) {
  final slider = tester.getRect(volumeSlider);

  return Offset(slider.center.dx, slider.bottom - 14 - (slider.height - 28) * value / 100);
}

/// Lets [time] go by, a frame every 50 ms, as the slider's animations need: a single long pump gives them one frame, at
/// its end.
Future<void> wait(WidgetTester tester, Duration time) async {
  for (var waited = Duration.zero; waited < time; waited += const Duration(milliseconds: 50)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A mouse over [finder]'s center, which opens the slider over the volume's button, all the way.
Future<TestGesture> mouseOver(WidgetTester tester, Finder finder) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);

  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump();
  await wait(tester, const Duration(milliseconds: 300));

  return mouse;
}

/// The slider's box over the volume's button, its opacity and its size.
(double, Size) popup(WidgetTester tester) {
  final material = find.ancestor(of: volumeSlider, matching: find.byType(Material)).first;
  final opacity = find.ancestor(of: material, matching: find.byType(Opacity)).first;

  return (tester.widget<Opacity>(opacity).opacity, tester.getSize(material));
}

/// Drags the open volume slider with [mouse] from [from] (just inside the track's ends, which are the edges of the
/// slider's own box, outside it) through [through], from 0 to 100; letting go at the last.
Future<void> drag(WidgetTester tester, TestGesture mouse, double from, List<double> through) async {
  await mouse.down(onTrack(tester, from));
  await tester.pump();

  for (final value in through) {
    await mouse.moveTo(onTrack(tester, value));
    await tester.pump();
  }

  await mouse.up();
  await tester.pump();
}

/// A notch of the mouse's wheel over [at], up (louder) or down.
Future<void> scroll(WidgetTester tester, Offset at, {required bool up}) async {
  final mouse = TestPointer(2, PointerDeviceKind.mouse);

  await tester.sendEventToBinding(mouse.hover(at));
  await tester.sendEventToBinding(mouse.scroll(Offset(0, up ? -20 : 20)));
  await tester.pump();
}

void main() {
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  setUp(() => SharedPreferencesAsync().clear());

  testWidgets('on a computer, the bar ends in the volume\'s button, after the devices, which says what it does; the '
      'pointer over it opens the slider over it, which stays while the pointer is on either, and closes a moment after '
      'it leaves them', (tester) async {
    final semantics = tester.ensureSemantics();

    await pumpBar(tester, size: const Size(960, 540), sleepTimer: true);

    final button = tester.getRect(volumeButton);

    expect(button.left, greaterThanOrEqualTo(tester.getRect(find.byTooltip('Aparelhos')).right));
    expect(button.right, lessThanOrEqualTo(960));
    expect(find.bySemanticsLabel('Silenciar'), findsOneWidget);
    expect(volumeSlider, findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);

    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(volumeButton));
    await tester.pump();
    await wait(tester, const Duration(milliseconds: 100));

    // Growing out of the button, as it shows.
    final (opening, growing) = popup(tester);

    expect(opening, inExclusiveRange(0, 1));
    expect(growing.height, inExclusiveRange(40, 140));
    expect(growing.width, 40);
    await wait(tester, const Duration(milliseconds: 200));
    expect(popup(tester), (1.0, const Size(40, 140)));

    final slider = tester.getRect(volumeSlider);

    expect(slider.bottom, lessThanOrEqualTo(button.top));
    expect(slider.center.dx, moreOrLessEquals(button.center.dx));
    expect(slider.height, greaterThan(100));
    expect(sliderValue(tester), 100);
    expect(
      find.descendant(of: volumeControl, matching: find.byType(Tooltip)),
      findsNothing,
      reason: 'over the slider',
    );

    await mouse.moveTo(slider.center);
    await wait(tester, const Duration(seconds: 1));
    expect(volumeSlider, findsOneWidget);
    await mouse.moveTo(const Offset(100, 100));
    await wait(tester, const Duration(milliseconds: 250));
    expect(popup(tester), (1.0, const Size(40, 140)), reason: 'a moment after');
    await wait(tester, const Duration(milliseconds: 150));

    // Going back into the button, as it fades.
    final (closing, shrinking) = popup(tester);

    expect(closing, inExclusiveRange(0, 1));
    expect(shrinking.height, inExclusiveRange(40, 140));
    await wait(tester, const Duration(milliseconds: 200));
    expect(volumeSlider, findsNothing);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  }, variant: computer);

  testWidgets('a phone, a tablet and a TV have their own buttons for the system\'s volume: none in the bar', (
    tester,
  ) async {
    await pumpBar(tester, size: const Size(1280, 700));
    expect(volumeControl, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('here, the volume follows the slider as it moves, which stays open while dragged; the button mutes it, '
      'and gives back the volume it had, the one before a drag down to none', (tester) async {
    final semantics = tester.ensureSemantics();
    final player = await pumpBar(tester, size: const Size(1280, 700));
    final mouse = await mouseOver(tester, volumeButton);

    await mouse.down(onTrack(tester, 99));
    await tester.pump();
    await mouse.moveTo(onTrack(tester, 70));
    await tester.pump();
    expect(player.volume, closeTo(70, 1), reason: 'as it moves');
    // Off the slider, still dragging.
    await mouse.moveTo(onTrack(tester, 50) + const Offset(60, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(volumeSlider, findsOneWidget);
    expect(player.volume, closeTo(50, 1));
    await mouse.up();
    await wait(tester, const Duration(milliseconds: 600));
    expect(volumeSlider, findsNothing, reason: 'let go away from it');

    final volume = player.volume;

    await tester.tap(volumeButton);
    await tester.pump();
    expect(player.volume, 0);
    expect(find.bySemanticsLabel('Ativar o som'), findsOneWidget);
    await tester.tap(volumeButton);
    await tester.pump();
    expect(player.volume, volume);

    await mouse.moveTo(tester.getCenter(volumeButton));
    await tester.pump();
    await wait(tester, const Duration(milliseconds: 300));
    await drag(tester, mouse, volume.toDouble(), [10, -10]);
    expect(player.volume, 0);
    await tester.tap(volumeButton);
    await tester.pump();
    expect(player.volume, volume, reason: 'not the last step on the way, 10');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox()); // stops the bar's timers
  }, variant: computer);

  testWidgets('a notch of the mouse\'s wheel, over the button or the slider, moves the volume by 5', (tester) async {
    final player = await pumpBar(tester, size: const Size(1280, 700));

    await scroll(tester, tester.getCenter(volumeButton), up: false);
    expect(player.volume, 95);
    await wait(tester, const Duration(milliseconds: 300));
    expect(popup(tester), (1.0, const Size(40, 140)), reason: 'the pointer over the button');
    await scroll(tester, tester.getCenter(volumeSlider), up: false);
    expect(player.volume, 90);
    await scroll(tester, tester.getCenter(volumeButton), up: true);
    expect(player.volume, 95);
    await scroll(tester, tester.getCenter(volumeButton), up: true);
    await scroll(tester, tester.getCenter(volumeButton), up: true);
    expect(player.volume, 100, reason: 'no louder than all of it');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  }, variant: computer);

  testWidgets('on another device, the slider shows its volume, which goes to it once, a moment after the slider '
      'stops', (tester) async {
    final client = TvClient();

    await pumpBar(tester, client: client, size: const Size(1280, 700));

    final mouse = await mouseOver(tester, volumeButton);

    expect(sliderValue(tester), 40);

    await mouse.down(onTrack(tester, 40));
    await tester.pump();
    await mouse.moveTo(onTrack(tester, 60));
    await tester.pump();
    await mouse.moveTo(onTrack(tester, 80));
    await tester.pump(const Duration(seconds: 1));
    expect(client.sent, isEmpty, reason: 'still dragging');
    await mouse.up();
    await tester.pump();
    expect(client.sent, isEmpty, reason: 'a moment after');
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.volumes, [closeTo(80, 1)]);
    expect(sliderValue(tester), closeTo(80, 1), reason: 'until the TV says it has it');
    client.reportVolume(80);
    await tester.pump(const Duration(seconds: 3));
    expect(sliderValue(tester), 80);

    client.sent.clear();
    await scroll(tester, tester.getCenter(volumeButton), up: false);
    await scroll(tester, tester.getCenter(volumeButton), up: false);
    expect(client.sent, isEmpty, reason: 'the wheel still moving');
    expect(sliderValue(tester), 70);
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.volumes, [70]);
    client.reportVolume(70);
    await tester.pump(const Duration(seconds: 3));

    client.sent.clear();
    await tester.tap(volumeButton);
    await tester.pump();
    expect(client.volumes, [0]);
    client.reportVolume(0);
    await tester.pump();
    await tester.tap(volumeButton);
    await tester.pump();
    expect(client.volumes, [0, 70]);
    await tester.pumpWidget(const SizedBox());
  }, variant: computer);

  testWidgets('the keyboard\'s focus on the button opens the slider, and its up and down arrows move the volume, which '
      'goes to another device once they stop', (tester) async {
    final client = TvClient();

    await pumpBar(tester, client: client, size: const Size(1280, 700));

    // The button's own, the nearest over its icon.
    final button = Focus.of(tester.element(find.descendant(of: volumeButton, matching: find.byType(ThemedIcon))));

    button.requestFocus();
    await tester.pump();
    await wait(tester, const Duration(milliseconds: 300));
    expect(popup(tester), (1.0, const Size(40, 140)));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(sliderValue(tester), 45);
    expect(client.sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.volumes, [45]);

    button.unfocus();
    await wait(tester, const Duration(milliseconds: 600));
    expect(volumeSlider, findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  }, variant: computer);

  testWidgets('on a device that takes no volume, it shows the device\'s, and moves nothing', (tester) async {
    final client = TvClient(volume: 30, canSetVolume: false);

    await pumpBar(tester, client: client, size: const Size(1280, 700));
    await mouseOver(tester, volumeButton);
    expect(sliderValue(tester), 30);
    expect(tester.widget<Slider>(volumeSlider).onChanged, isNull);
    expect(tester.widget<IconButton>(volumeButton).onPressed, isNull);
    await scroll(tester, tester.getCenter(volumeButton), up: false);
    expect(sliderValue(tester), 30);
    await tester.pump(const Duration(seconds: 1));
    expect(client.sent, isEmpty);
    await tester.pumpWidget(const SizedBox());
  }, variant: computer);

  test('the player starts at the volume kept, and keeps the one set, here or from another device, for the next '
      'launch; a fade\'s it doesn\'t', () async {
    expect((await VolumeChoice.load()).value, 100, reason: 'until one is set');

    final player = PlayerController(
      FakeEngine(),
      SubsonicApi(Uri.parse('https://music.test'), credentials),
      volume: VolumeChoice(40),
    );

    expect(player.volume, 40);

    await player.setVolume(70);
    expect((await VolumeChoice.load()).value, 70);
    await player.obey(const Command.setVolume(20));
    expect((await VolumeChoice.load()).value, 20);
    await player.setVolume(5, keep: false);
    expect(player.volume, 5);
    expect((await VolumeChoice.load()).value, 20);
  });
}
