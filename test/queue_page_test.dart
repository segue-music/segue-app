import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/autoplay_choice.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/player/now_playing_bar.dart';
import 'package:segue/ui/player/player_page.dart';
import 'package:segue/ui/player/queue_page.dart';
import 'package:segue/ui/widgets/cover.dart';
import 'package:segue/ui/widgets/directional_navigation.dart';
import 'package:segue/ui/widgets/equalizer.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';
import 'remote.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

const songs = [
  Song(id: 's1', title: 'One', artist: 'Aerosmith', duration: Duration(seconds: 180)),
  Song(id: 's2', title: 'Two', artist: 'Aerosmith', duration: Duration(seconds: 200)),
  Song(id: 's3', title: 'Three', artist: 'Aerosmith', duration: Duration(seconds: 220)),
  Song(id: 's4', title: 'Four', artist: 'Aerosmith', duration: Duration(seconds: 240)),
];

/// The player bar, under the navigator as in the app, with [songs] playing from the second one, or,
/// with [client], what its devices play. [television] as on a TV, which has no bar, but the home, whose side rail opens
/// the player. With [autoplay], the pages show its switch.
Future<PlayerController> pumpBar(
  WidgetTester tester, {
  SegueClient? client,
  Size size = const Size(360, 640),
  bool television = false,
  AutoplayChoice? autoplay,
}) async {
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((_) async => http.Response('', 404)),
  );
  final player = PlayerController(FakeEngine(), api);

  if (client == null) {
    await player.playQueue(songs, index: 1);
  }

  final connect = ConnectController(player: player, client: client);
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  client?.notifyListeners(); // as when another device's state arrives
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    connect,
    autoplay: autoplay,
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(
        services: services,
        child: DirectionalNavigation(enabled: television, child: child!),
      ),
      home: television
          ? HomePage(onSignOut: () {})
          : const Scaffold(body: SizedBox.expand(), bottomNavigationBar: NowPlayingBar()),
    ),
  );

  return player;
}

/// Opens the full-screen player, from the bar's song or, on a TV, the side rail, and the queue from it.
Future<void> openQueue(WidgetTester tester) async {
  final rail = find.byTooltip('Tocando agora');
  await tester.tap(
    rail.evaluate().isNotEmpty
        ? rail
        : find.descendant(of: find.byTooltip('Abrir o player'), matching: find.byType(Cover)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(PlayerPage), matching: find.byTooltip('Fila')));
  await tester.pumpAndSettle();
}

/// What [finder] finds in the queue itself, rather than in the bar under it. Each call looks afresh.
Finder inQueue(Finder finder) {
  Set<Element>? inside;

  return find.byElementPredicate((element) {
    inside ??= find
        .descendant(of: find.byType(QueuePage), matching: finder)
        .evaluate()
        .toSet()
        .difference(find.descendant(of: find.byType(NowPlayingBar), matching: finder).evaluate().toSet());

    return inside!.contains(element);
  });
}

ListTile tile(WidgetTester tester, String title) =>
    tester.widget<ListTile>(find.ancestor(of: inQueue(find.text(title)), matching: find.byType(ListTile)));

const me = DeviceInfo(id: 'me', name: 'me', client: 'test', api: Api.subsonic, roles: [], capabilities: []);

/// A hub client that never connects, with a TV that plays the track at [index] of its queue; or [client], with the TV in
/// it.
SegueClient clientWithTv({required List<CommandAction> capabilities, SegueClient? client, int index = 1}) {
  client ??= SegueClient(
    url: Uri.parse('ws://unused'),
    auth: const Auth.subsonic(username: 'a', token: 't', salt: 's'),
    device: me,
  );
  client.devices['tv'] = Device(
    info: DeviceInfo(
      id: 'tv',
      name: 'Sala de estar',
      client: 'test',
      api: Api.subsonic,
      roles: const [Role.player],
      capabilities: capabilities,
    ),
    online: true,
    state: StampedState(
      status: PlaybackStatus.playing,
      positionMs: 1000,
      at: DateTime.now().millisecondsSinceEpoch,
      index: index,
      queue: const [
        QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', durationMs: 268000),
        QueueItem(id: 's2', title: 'Walk This Way', artist: 'Aerosmith', durationMs: 220000),
        QueueItem(title: 'Untranslatable'),
      ],
    ),
  );

  return client;
}

/// A hub client whose commands wait for the test to answer them ([answer]).
class WaitingClient extends SegueClient {
  WaitingClient()
    : super(
        url: Uri.parse('ws://unused'),
        auth: const Auth.subsonic(username: 'a', token: 't', salt: 's'),
        device: me,
      );

  final sent = <Command>[];
  final answer = Completer<Result>();

  @override
  Future<Result> command(String target, Command command) {
    sent.add(command);

    return answer.future;
  }
}

/// The button of the menu of the track [title] in the queue.
Finder menuOf(String title) => find.descendant(
  of: find.ancestor(of: inQueue(find.text(title)), matching: find.byType(ListTile)),
  matching: find.byTooltip('Mais opções'),
);

/// Drags the track [title] in the queue by [rows] tracks, down or, below zero, up, as a finger does on a touch screen:
/// held a moment first.
Future<void> dragTrack(WidgetTester tester, String title, int rows) async {
  final line = find.ancestor(of: inQueue(find.text(title)), matching: find.byType(ListTile));
  final from = tester.getCenter(line);
  final height = tester.getSize(line).height;
  final gesture = await tester.startGesture(from);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));

  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(from + Offset(0, rows * height * i / 10));
    await tester.pump(const Duration(milliseconds: 16));
  }

  await gesture.up();
  await tester.pumpAndSettle();
}

/// Whether the track [title] in the queue has the focus.
bool focusedOn(WidgetTester tester, String title) =>
    Focus.of(tester.element(inQueue(find.text(title)))).hasPrimaryFocus;

/// The titles in the queue's list from the one on top down, out of sight too: those before it, above, aren't built until
/// the list scrolls up to them.
List<String> titlesFromTop(WidgetTester tester) {
  final list = find.descendant(of: find.byType(QueuePage), matching: find.byType(CustomScrollView));
  final lines = find.descendant(of: list, matching: find.byType(ListTile), skipOffstage: false).evaluate().toList()
    ..sort(
      (a, b) => (a.renderObject! as RenderBox)
          .localToGlobal(Offset.zero)
          .dy
          .compareTo((b.renderObject! as RenderBox).localToGlobal(Offset.zero).dy),
    );

  return [for (final line in lines) ((line.widget as ListTile).title! as Text).data!];
}

void main() {
  testWidgets('the full-screen player opens the queue: the current track on top, the next ones under it', (
    tester,
  ) async {
    await pumpBar(tester);
    await openQueue(tester);
    expect(find.byType(QueuePage), findsOneWidget);
    expect(inQueue(find.text('Fila')), findsOneWidget);

    for (final title in ['Two', 'Three', 'Four']) {
      expect(inQueue(find.text(title)), findsOneWidget, reason: title);
    }

    expect(tile(tester, 'Two').selected, isTrue, reason: 'the current track stands out');
    expect(tile(tester, 'Three').selected, isFalse);
    expect(inQueue(find.byType(Equalizer)), findsOneWidget, reason: 'it plays');
    expect(inQueue(find.text('3:20')), findsOneWidget, reason: 'how long it lasts');
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    expect(tester.getTopLeft(find.ancestor(of: inQueue(find.text('Two')), matching: find.byType(ListTile))).dy, top);

    // What played before is above it.
    expect(inQueue(find.text('One')), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(inQueue(find.text('One')), findsOneWidget);
    expect(tile(tester, 'One').selected, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QueuePage), findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the timers
  });

  testWidgets('over the queue, a header names its columns, lined up with the tracks, and stays as they scroll', (
    tester,
  ) async {
    await pumpBar(tester);
    await openQueue(tester);
    final title = inQueue(find.text('Título'));
    expect(tester.getRect(title).left, tester.getRect(inQueue(find.text('Two'))).left);
    expect(
      tester.getRect(inQueue(find.byTooltip('Duração'))).right,
      moreOrLessEquals(tester.getRect(inQueue(find.text('3:20'))).right, epsilon: 1),
    );
    final top = tester.getRect(title).top;

    // Down, to what played before, above the current track.
    await tester.drag(inQueue(find.byType(CustomScrollView)), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(tester.getRect(inQueue(find.text('Título'))).top, top);
    expect(
      tester.getRect(inQueue(find.text('One'))).top,
      greaterThan(tester.getRect(inQueue(find.text('Título'))).bottom),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap on a track in the queue plays it, from its start', (tester) async {
    final player = await pumpBar(tester);
    await player.pause();
    await openQueue(tester);
    await tester.tap(inQueue(find.text('Four')));
    await tester.pump();
    expect(player.current?.title, 'Four');
    expect(player.playing, isTrue);
    expect(player.position.inSeconds, 0);
    expect(tile(tester, 'Four').selected, isTrue);
    expect(tile(tester, 'Two').selected, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the queue is that of the device the app controls, wherever it plays', (tester) async {
    final player = await pumpBar(tester, client: clientWithTv(capabilities: CommandAction.values));
    await openQueue(tester);
    expect(inQueue(find.text('Fila em Sala de estar')), findsOneWidget);
    expect(inQueue(find.text('Walk This Way')), findsOneWidget);
    expect(inQueue(find.text('Untranslatable')), findsOneWidget, reason: 'shown, though it can\'t play here');
    expect(tile(tester, 'Walk This Way').selected, isTrue);
    expect(tile(tester, 'Untranslatable').onTap, isNotNull);
    expect(player.queue, isEmpty, reason: 'not this device\'s');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after the last track, this device\'s queue has the switch of autoplay, which turns it off and on; '
      'another device\'s, which goes on or not as that device has it, has none', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final autoplay = AutoplayChoice();
    addTearDown(autoplay.dispose);
    await pumpBar(tester, autoplay: autoplay);
    await openQueue(tester);
    final toggle = find.widgetWithText(SwitchListTile, 'Reprodução automática');
    await tester.scrollUntilVisible(
      toggle,
      100,
      scrollable: find.descendant(of: find.byType(QueuePage), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('Quando a fila acaba, músicas parecidas continuam tocando.'), findsOneWidget);
    expect(tester.getRect(toggle).top, greaterThan(tester.getRect(inQueue(find.text('Four'))).bottom));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue, reason: 'on, until turned off');

    await tester.tap(toggle);
    await tester.pump();
    expect(autoplay.value, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pump();
    expect(autoplay.value, isTrue);

    await pumpBar(
      tester,
      client: clientWithTv(capabilities: CommandAction.values),
      autoplay: autoplay,
    );
    await openQueue(tester);
    expect(inQueue(find.text('Walk This Way')), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a device that takes no jump, the queue shows but its tracks do nothing', (tester) async {
    await pumpBar(
      tester,
      client: clientWithTv(capabilities: [...CommandAction.values.where((a) => a != CommandAction.jump)]),
    );
    await openQueue(tester);
    expect(inQueue(find.text('Walk This Way')), findsOneWidget);
    expect(tile(tester, 'Untranslatable').onTap, isNull);
    expect(tile(tester, 'Walk This Way').onTap, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, the current track has the focus when the queue opens', (tester) async {
    await pumpBar(tester, size: const Size(1000, 600), television: true);
    await openQueue(tester);
    expect(Focus.of(tester.element(inQueue(find.text('Two')))).hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wide player bar opens the queue too; a phone-sized one has no room for it', (tester) async {
    await pumpBar(tester, size: const Size(1000, 600));
    await tester.tap(find.byTooltip('Fila'));
    await tester.pumpAndSettle();
    expect(find.byType(QueuePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await pumpBar(tester);
    expect(find.byTooltip('Fila'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  group('editing the queue', () {
    testWidgets('a track dragged in the queue goes there, the current one playing on', (tester) async {
      final player = await pumpBar(tester);
      await openQueue(tester);
      await dragTrack(tester, 'Four', -1);
      expect(player.queue.map((song) => song.title), ['One', 'Two', 'Four', 'Three']);
      expect(player.current?.title, 'Two');
      expect(player.playing, isTrue);
      expect(titlesFromTop(tester), ['Two', 'Four', 'Three']);
      expect(tile(tester, 'Two').selected, isTrue);

      // The current track itself.
      await dragTrack(tester, 'Two', 2);
      expect(player.queue.map((song) => song.title), ['One', 'Four', 'Three', 'Two']);
      expect(player.current?.title, 'Two');
      expect(tile(tester, 'Two').selected, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("a track moved on another device shows in its new place at once, until that device's queue comes", (
      tester,
    ) async {
      final client = clientWithTv(capabilities: CommandAction.values, client: WaitingClient()) as WaitingClient;
      await pumpBar(tester, client: client);
      await openQueue(tester);
      await dragTrack(tester, 'Untranslatable', -1);
      expect(client.sent.single.toJson(), {'action': 'moveInQueue', 'index': 2, 'to': 1});
      expect(titlesFromTop(tester), ['Untranslatable', 'Walk This Way']);
      expect(tile(tester, 'Walk This Way').selected, isTrue);

      // The TV's report, with the track where it went, and only then the result.
      final state = client.devices['tv']!.state!;
      client.devices['tv'] = Device(
        info: client.devices['tv']!.info,
        online: true,
        state: StampedState(
          status: state.status,
          positionMs: state.positionMs,
          at: state.at,
          index: 2,
          queue: [state.queue![0], state.queue![2], state.queue![1]],
        ),
      );
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      client.notifyListeners();
      await tester.pump();
      client.answer.complete(const Result(ok: true));
      await tester.pumpAndSettle();
      expect(titlesFromTop(tester), ['Untranslatable', 'Walk This Way']);
      expect(tile(tester, 'Walk This Way').selected, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a move the device fails puts the queue back as it was, and says why', (tester) async {
      await pumpBar(tester, client: clientWithTv(capabilities: CommandAction.values));
      await openQueue(tester);
      await dragTrack(tester, 'Untranslatable', -1);
      expect(titlesFromTop(tester), ['Walk This Way', 'Untranslatable']);
      expect(find.text('Sem conexão com o hub.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("a track's menu takes it out of the queue; the current one stays", (tester) async {
      final player = await pumpBar(tester);
      await openQueue(tester);
      await tester.tap(menuOf('Four'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover da fila'));
      await tester.pumpAndSettle();
      expect(player.queue.map((song) => song.title), ['One', 'Two', 'Three']);
      expect(titlesFromTop(tester), ['Two', 'Three']);
      expect(player.current?.title, 'Two');

      await tester.tap(menuOf('Two'));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar à playlist'), findsOneWidget);
      expect(find.text('Remover da fila'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on a TV, whose remote seldom has a menu key, OK held on a track opens its menu, nothing in it picked '
        'as OK is let go, and pressed, plays the track as it is let go', (tester) async {
      final player = await pumpBar(tester, size: const Size(1000, 600), television: true);
      await openQueue(tester);
      await pressOnRemote(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(kLongPressTimeout - const Duration(milliseconds: 100));
      expect(player.current?.title, 'Two', reason: 'not yet');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(player.current?.title, 'Three');
      expect(find.text('Mover'), findsNothing);

      // On Android the key repeats from when the system takes it as held.
      await pressOnRemote(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Mover'), findsOneWidget);
      expect(player.current?.title, 'Three');
      await pressOnRemote(tester, LogicalKeyboardKey.escape);
      expect(find.text('Mover'), findsNothing);
      expect(focusedOn(tester, 'Four'), isTrue);

      await holdOk(tester);
      expect(find.text('Mover'), findsOneWidget);
      expect(player.current?.title, 'Three');
      await pickByRemote(tester, 'Remover da fila');
      expect(player.queue.map((song) => song.title), ['One', 'Two', 'Three']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on a TV, which has no drag, a track moves by the remote: from its menu, up and down take it along, '
        'the focus on it, and OK leaves it there, the device moving it only then', (tester) async {
      final player = await pumpBar(tester, size: const Size(1000, 600), television: true);
      await openQueue(tester);
      expect(find.byType(SliverReorderableList), findsNothing);
      expect(focusedOn(tester, 'Two'), isTrue);

      await pressOnRemote(tester, LogicalKeyboardKey.contextMenu);
      await pickByRemote(tester, 'Mover');
      expect(moveHint, findsOneWidget);
      expect(focusedOn(tester, 'Two'), isTrue);
      await pressOnRemote(tester, LogicalKeyboardKey.arrowDown);
      await pressOnRemote(tester, LogicalKeyboardKey.arrowDown);
      expect(titlesFromTop(tester), ['Three', 'Four', 'Two']);
      expect(focusedOn(tester, 'Two'), isTrue);
      expect(tile(tester, 'Two').selected, isTrue, reason: 'the current track, wherever it goes');
      expect(player.queue.map((song) => song.title), ['One', 'Two', 'Three', 'Four'], reason: 'not yet');

      await pressOnRemote(tester, LogicalKeyboardKey.arrowDown);
      expect(titlesFromTop(tester), ['Three', 'Four', 'Two'], reason: 'the last already');
      await pressOnRemote(tester, LogicalKeyboardKey.arrowUp);
      expect(titlesFromTop(tester), ['Three', 'Two', 'Four']);
      await pressOnRemote(tester, LogicalKeyboardKey.select);
      expect(player.queue.map((song) => song.title), ['One', 'Three', 'Two', 'Four']);
      expect(player.current?.title, 'Two');
      expect(player.playing, isTrue);
      expect(titlesFromTop(tester), ['Three', 'Two', 'Four']);
      expect(focusedOn(tester, 'Two'), isTrue);
      expect(moveHint, findsNothing);

      // Up and down move the focus again.
      await pressOnRemote(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedOn(tester, 'Four'), isTrue);
      expect(titlesFromTop(tester), ['Three', 'Two', 'Four']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on a TV, Back, or Esc, puts the track moving back where it was, and the page stays', (tester) async {
      final player = await pumpBar(tester, size: const Size(1000, 600), television: true);
      await openQueue(tester);

      for (final back in [LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape]) {
        await pressOnRemote(tester, LogicalKeyboardKey.contextMenu);
        await pickByRemote(tester, 'Mover');
        await pressOnRemote(tester, LogicalKeyboardKey.arrowDown);
        expect(titlesFromTop(tester), ['Three', 'Two', 'Four']);
        await pressOnRemote(tester, back);
        expect(find.byType(QueuePage), findsOneWidget, reason: '$back');
        expect(titlesFromTop(tester), ['Two', 'Three', 'Four']);
        expect(focusedOn(tester, 'Two'), isTrue);
        expect(moveHint, findsNothing);
      }

      expect(player.queue.map((song) => song.title), ['One', 'Two', 'Three', 'Four']);

      // And the system's back, as Android's comes where the keys don't take it.
      await pressOnRemote(tester, LogicalKeyboardKey.contextMenu);
      await pickByRemote(tester, 'Mover');
      await pressOnRemote(tester, LogicalKeyboardKey.arrowDown);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QueuePage), findsOneWidget);
      expect(titlesFromTop(tester), ['Two', 'Three', 'Four']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only on a TV does a track\'s menu move it; elsewhere a drag does', (tester) async {
      await pumpBar(tester, size: const Size(1000, 600));
      await openQueue(tester);
      await tester.tap(menuOf('Three'));
      await tester.pumpAndSettle();
      expect(find.text('Remover da fila'), findsOneWidget);
      expect(find.text('Mover'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on a device that takes no moving or removing, its tracks neither move nor go out', (tester) async {
      await pumpBar(
        tester,
        client: clientWithTv(
          capabilities: [
            ...CommandAction.values.where(
              (action) => action != CommandAction.moveInQueue && action != CommandAction.removeFromQueue,
            ),
          ],
          index: 0,
        ),
      );
      await openQueue(tester);
      expect(find.byType(SliverReorderableList), findsNothing);
      await tester.tap(menuOf('Walk This Way'));
      await tester.pumpAndSettle();
      expect(find.text('Remover da fila'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
