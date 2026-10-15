// The app's Segue client and ConnectController against the real (Go) hub. Needs the hub binary, from
// the segue repository (go build -o segue-hub ./cmd/segue-hub in its hub/): its path in
// SEGUE_HUB_BIN, or a clone of segue next to this one. Without it, these tests are skipped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/jellyfin/api.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/media_controls.dart';
import 'package:segue/player/player.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

final hubBin = Platform.environment['SEGUE_HUB_BIN'] ?? '../segue/hub/segue-hub';

const songs = [
  Song(id: '5QFKvMsJrd57QE2Le2dKKo', title: 'Dream On', artist: 'Aerosmith', duration: Duration(seconds: 268)),
  Song(id: '7N42dgm5tFLK9N8MT7fHC7', title: 'Other', duration: Duration(seconds: 200)),
];

/// Three songs, which the fake engine shuffles into another order, the current one first.
const three = [...songs, Song(id: '1qqqqqqqqqqqqqqqqqqqqq', title: 'Third', duration: Duration(seconds: 150))];
const unshuffled = ['Dream On', 'Other', 'Third'];

/// The titles of [player]'s queue, in its play order.
List<String> titles(PlayerController player) => [for (final song in player.queue) song.title];

late Process hub;
late Uri hubUrl;
int users = 0;

/// One app: a fake engine, the player, the hub client and the Connect controller.
class App {
  App(String user, this.name, {Uri? url})
    : engine = FakeEngine(),
      client = SegueClient(
        url: url ?? hubUrl,
        auth: Auth.subsonic(username: user, token: '-', salt: '-'),
        device: DeviceInfo(
          id: name,
          name: name,
          client: 'test',
          api: Api.subsonic,
          roles: Role.values,
          capabilities: CommandAction.values,
        ),
      ) {
    player = PlayerController(
      engine,
      SubsonicApi(Uri.parse('https://music.test'), SubsonicCredentials(username: user, token: '-', salt: '-')),
    );
    connect = ConnectController(player: player, client: client);
  }

  final String name;
  final FakeEngine engine;
  final SegueClient client;
  late final PlayerController player;
  late final ConnectController connect;

  Future<App> start() async {
    await client.connect();
    addTearDown(client.close);

    return this;
  }
}

Future<void> until(bool Function() condition, String what, {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);

  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $what');
    }

    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Starts a hub that takes any device (SEGUE_AUTH=none), on [port] (0: any free one), keeping the last playbacks in
/// [state] if there is one, and returns it with its WebSocket's URL.
Future<(Process, Uri)> startHub({int port = 0, String? state}) async {
  final process = await Process.start(
    hubBin,
    [],
    environment: {'SEGUE_AUTH': 'none', 'SEGUE_LISTEN': '127.0.0.1:$port', 'SEGUE_STATE': ?state},
  );
  final listening = Completer<Uri>();

  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final match = RegExp(r'msg="hub listening" url=http://(\S+)').firstMatch(line);

    if (match != null && !listening.isCompleted) {
      listening.complete(Uri.parse('ws://${match[1]}/v1/ws'));
    }
  });
  unawaited(process.stderr.drain<void>());

  return (process, await listening.future.timeout(const Duration(seconds: 10)));
}

/// A port no one listens on now.
Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;

  await socket.close();

  return port;
}

/// A proxy in front of the hub, as an app finds one where the connection behind it died: once [silence] is called,
/// nothing gets through the connections it has, and nothing closes them. Those that come after go through.
Future<({Uri url, void Function() silence})> proxyToHub() async {
  final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>[];
  final silencers = <void Function()>[];

  addTearDown(() async {
    await proxy.close();

    for (final socket in sockets) {
      socket.destroy();
    }
  });
  proxy.listen((app) async {
    final toHub = await Socket.connect(hubUrl.host, hubUrl.port);
    var silent = false;

    sockets.addAll([app, toHub]);
    silencers.add(() => silent = true);
    app.listen((data) {
      if (!silent) {
        toHub.add(data);
      }
    }, onDone: toHub.destroy);
    toHub.listen((data) {
      if (!silent) {
        app.add(data);
      }
    }, onDone: app.destroy);
  });

  return (
    url: Uri.parse('ws://127.0.0.1:${proxy.port}/v1/ws'),
    silence: () {
      for (final silence in silencers) {
        silence();
      }
    },
  );
}

void main() {
  if (!File(hubBin).existsSync()) {
    test('against the hub', () {}, skip: 'needs the hub binary, $hubBin');
    return;
  }

  setUpAll(() async {
    final (process, url) = await startHub();

    hub = process;
    hubUrl = url;
  });
  tearDownAll(() async {
    hub.kill();
    await hub.exitCode;
  });

  String newUser() => 'user${++users}';

  test('a refused hello is a final HubClosed', () async {
    final client = SegueClient(
      url: hubUrl,
      auth: Auth.subsonic(username: newUser(), token: '-', salt: '-'),
      device: const DeviceInfo(id: 'x', name: '', client: 'test', api: Api.subsonic, roles: [], capabilities: []),
    );

    await expectLater(
      client.connect(),
      throwsA(
        isA<HubClosed>().having((e) => e.code, 'code', CloseCode.badHello).having((e) => e.isFinal, 'isFinal', true),
      ),
    );
  });

  test('a copy kicked out by another with the same device id stays out', () async {
    final user = newUser();
    final first = App(user, 'laptop');

    unawaited(first.client.start());
    addTearDown(first.client.close);
    await until(() => first.client.status == HubStatus.connected, 'the first copy');

    final second = await App(user, 'laptop').start();

    await until(() => first.client.status == HubStatus.rejected, 'the first copy to give up');
    expect(first.client.lastClose?.code, CloseCode.replaced);
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // longer than the backoff
    expect(second.client.status, HubStatus.connected);
  });

  test('sees what another device plays, on the hub clock', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs, position: const Duration(seconds: 10));
    await until(() => phone.client.devices['laptop']?.state?.current != null, 'the laptop state');
    expect(phone.client.devices['laptop']!.state!.current!.title, 'Dream On');
    expect(phone.client.positionMs('laptop'), greaterThanOrEqualTo(10000));
  });

  test('an app with nothing playing shows, and controls, what plays on another device', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs);
    await until(() => phone.connect.nowPlaying?.device == 'laptop', 'the phone to follow the laptop');
    expect(phone.connect.nowPlaying?.title, 'Dream On');
    expect(phone.connect.nowPlaying?.playing, isTrue);
    expect(phone.connect.playingId, 'laptop');
    expect((await phone.connect.toggle()).ok, isTrue);
    expect(laptop.player.playing, isFalse);
    await until(() => phone.connect.nowPlaying?.playing == false, 'the phone to see the pause');
    expect(phone.connect.nowPlaying?.device, 'laptop', reason: 'a paused device stays on the bar');
  });

  test('when another device starts playing, every app follows it', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await phone.player.playQueue(songs);
    await until(() => laptop.connect.nowPlaying?.device == 'phone', 'the laptop to follow the phone');
    await phone.player.toggle();
    await laptop.player.playQueue(songs, index: 1);
    expect(laptop.connect.nowPlaying?.device, isNull, reason: 'the laptop plays itself');
    await until(() => phone.connect.nowPlaying?.device == 'laptop', 'the phone to follow the laptop');
    expect(phone.connect.nowPlaying?.title, 'Other');
  });

  test('reopening the app brings back the last playback, paused where it was', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();

    await laptop.player.playQueue(songs, index: 1, position: const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 100)); // the report reaches the hub
    await laptop.client.close();

    final reopened = await App(user, 'laptop').start();

    await until(() => reopened.player.queue.isNotEmpty, 'the queue to come back');
    expect(reopened.player.index, 1);
    expect(reopened.player.playing, isFalse);
    expect(reopened.player.position.inMilliseconds, inInclusiveRange(30000, 31000));
    expect(reopened.connect.nowPlaying?.title, 'Other');
    expect(reopened.connect.nowPlaying?.device, isNull);
  });

  test('a play pressed as the app opens, before it has any music, plays the last playback as it comes back', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();

    await laptop.player.playQueue(songs, index: 1, position: const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 100)); // the report reaches the hub
    await laptop.client.close();

    // The media controls take it before the app has signed in, as a headphone's button that woke the app up.
    final controls = MediaControls();

    addTearDown(() => controls.attach(null, null));
    await controls.play();

    final reopened = App(user, 'laptop');

    controls.attach(reopened.connect, null);
    await reopened.start();
    await until(() => reopened.player.playing, 'the last playback to play');
    expect(reopened.player.index, 1);
    expect(reopened.player.position.inSeconds, greaterThanOrEqualTo(30));
  });

  test('a play pressed too long before the last playback comes back leaves it paused', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();

    await laptop.player.playQueue(songs);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await laptop.client.close();

    final reopened = App(user, 'laptop')..connect.playRestoredBy = DateTime.now().subtract(const Duration(seconds: 1));

    await reopened.start();
    await until(() => reopened.player.queue.isNotEmpty, 'the queue to come back');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(reopened.player.playing, isFalse);
  });

  test('a play pressed as the app opens leaves the last playback as it is on the device it is on', () async {
    final user = newUser();
    final tv = await App(user, 'tv').start();

    await tv.player.playQueue(songs);
    await tv.player.toggle();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final phone = App(user, 'phone')..connect.playRestoredBy = DateTime.now().add(const Duration(seconds: 8));

    await phone.start();
    await until(() => phone.connect.nowPlaying?.device == 'tv', 'the phone to show the TV');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(tv.player.playing, isFalse);
    expect(phone.player.queue, isEmpty);
  });

  test('another device opening after the last one closed continues it there', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();

    await laptop.player.playQueue(songs);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await laptop.client.close();

    final phone = await App(user, 'phone').start();

    await until(() => phone.player.queue.isNotEmpty, 'the queue on the phone');
    expect(phone.player.current?.title, 'Dream On');
    expect(phone.player.playing, isFalse);
  });

  test('an app opened after another one that just opened shows the music on its own', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();

    await laptop.player.playQueue(songs);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await laptop.client.close();

    // The laptop opens again and loads it, with nobody pressing anything; then the phone opens.
    final again = await App(user, 'laptop').start();

    await until(() => again.player.queue.isNotEmpty, 'the music on the laptop');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final phone = await App(user, 'phone').start();

    await until(() => phone.player.queue.isNotEmpty, 'the music on the phone');
    expect(phone.connect.nowPlaying?.device, isNull);
    expect(again.connect.nowPlaying?.device, isNull);
  });

  test('opening while the last device is on and paused shows that device', () async {
    final user = newUser();
    final tv = await App(user, 'tv').start();

    await tv.player.playQueue(songs);
    await tv.player.toggle();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final phone = await App(user, 'phone').start();

    await until(() => phone.connect.nowPlaying?.device == 'tv', 'the phone to show the TV');
    expect(phone.connect.nowPlaying?.playing, isFalse);
    expect(phone.player.queue, isEmpty);
  });

  test('apps opened after the last one closed, with nothing played, each show it on their own', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();

    await laptop.player.playQueue(songs);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await laptop.client.close(); // closed while playing

    final desktop = await App(user, 'desktop').start();

    await until(() => desktop.player.queue.isNotEmpty, 'the queue on the desktop');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final again = await App(user, 'laptop').start();

    await until(() => again.player.queue.isNotEmpty, 'the queue on the laptop');
    expect(again.player.playing, isFalse);
    expect(again.connect.nowPlaying?.device, isNull);
    // The desktop doesn't follow the laptop that came back: it was playing when it closed, not now.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(desktop.connect.activeId, isNull);
    expect(desktop.connect.nowPlaying?.device, isNull);
  });

  test('when the device it follows closes, its music stays here, paused where it got to', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs, index: 1, position: const Duration(seconds: 30));
    await until(() => phone.connect.nowPlaying?.device == 'laptop', 'the phone to follow the laptop');
    await laptop.client.close();
    await until(() => phone.player.queue.isNotEmpty, 'the music on the phone');
    expect(phone.connect.activeId, isNull);
    expect(phone.connect.devices, isEmpty);
    expect(phone.connect.nowPlaying?.device, isNull);
    expect(phone.connect.nowPlaying?.title, 'Other');
    expect(phone.player.playing, isFalse);
    expect(phone.player.position.inMilliseconds, greaterThanOrEqualTo(30000));

    // Keeping it isn't playing it: the laptop, opened again, still has the last playback, and
    // shows it on its own, as the phone does.
    final again = await App(user, 'laptop').start();

    await until(() => again.player.queue.isNotEmpty, 'the music back on the laptop');
    expect(again.connect.nowPlaying?.device, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(phone.connect.nowPlaying?.device, isNull);
  });

  test('when the hub restarts and the device it follows does not come back, its music stays here, paused', () async {
    final user = newUser();
    final folder = await Directory.systemTemp.createTemp('segue');
    final state = '${folder.path}/last.json';
    final port = await freePort();
    final (first, url) = await startHub(port: port, state: state);
    final laptop = App(user, 'laptop', url: url);
    // Connected once, with no reconnecting: it won't come back.
    final phone = await App(user, 'phone', url: url).start();

    addTearDown(() => folder.delete(recursive: true));
    addTearDown(first.kill);
    unawaited(laptop.client.start());
    addTearDown(laptop.client.close);
    await until(() => laptop.client.status == HubStatus.connected, 'the laptop connected');
    await phone.player.playQueue(songs, index: 1, position: const Duration(seconds: 30));
    await phone.player.toggle();
    await until(
      () => laptop.connect.activeId == 'phone' && laptop.connect.nowPlaying?.playing == false,
      'the laptop to follow the phone, paused',
    );

    // The hub shuts down, telling the devices (1001), and comes back: the phone isn't in its list any more.
    first.kill();
    await first.exitCode;

    final (second, _) = await startHub(port: port, state: state);

    addTearDown(second.kill);
    await until(() => laptop.player.queue.isNotEmpty, 'the music on the laptop', timeout: const Duration(seconds: 10));
    expect(laptop.client.lastClose?.code, CloseCode.goingAway);
    expect(laptop.connect.activeId, isNull);
    expect(laptop.connect.nowPlaying?.title, 'Other');
    expect(laptop.player.playing, isFalse);
    expect(
      laptop.player.position.inMilliseconds,
      phone.player.position.inMilliseconds,
      reason: 'where the phone paused, as it reported it, in ms',
    );
  });

  test('when the hub restarts and the device it follows, playing, does not come back, its music stays here where it '
      'had got to', () async {
    final user = newUser();
    final folder = await Directory.systemTemp.createTemp('segue');
    final state = '${folder.path}/last.json';
    final port = await freePort();
    final (first, url) = await startHub(port: port, state: state);
    final laptop = App(user, 'laptop', url: url);
    final phone = await App(user, 'phone', url: url).start();

    addTearDown(() => folder.delete(recursive: true));
    addTearDown(first.kill);
    unawaited(laptop.client.start());
    addTearDown(laptop.client.close);
    await until(() => laptop.client.status == HubStatus.connected, 'the laptop connected');
    await phone.player.playQueue(songs, index: 1, position: const Duration(seconds: 30));
    await until(() => laptop.connect.nowPlaying?.playing ?? false, 'the laptop to follow the phone, playing');
    // No report meanwhile: the phone only reports a change.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    first.kill();
    await first.exitCode;

    final (second, _) = await startHub(port: port, state: state);

    addTearDown(second.kill);
    await until(() => laptop.player.queue.isNotEmpty, 'the music on the laptop', timeout: const Duration(seconds: 10));
    expect(laptop.player.position.inMilliseconds, greaterThanOrEqualTo(30500));
  });

  test('a play for a device out of reach fails, and its music comes here, for the next play to play it', () async {
    final user = newUser();
    final proxy = await proxyToHub();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone', url: proxy.url).start();

    await phone.player.playQueue(songs, index: 1, position: const Duration(seconds: 30));
    await phone.player.toggle();
    await until(
      () => laptop.connect.activeId == 'phone' && laptop.connect.nowPlaying?.playing == false,
      'the laptop to follow the phone, paused',
    );

    // Airplane mode: the phone's connection goes silent, and nothing closes it. The hub, which pings the phone with
    // the command, finds it gone within 5 s.
    proxy.silence();

    expect((await laptop.connect.play()).error, 'offline');
    await until(() => laptop.player.queue.isNotEmpty, 'the music on the laptop');
    expect(laptop.connect.activeId, isNull);
    expect(laptop.connect.nowPlaying?.title, 'Other');
    expect(laptop.player.playing, isFalse);
    expect((await laptop.connect.play()).ok, isTrue);
    expect(laptop.player.playing, isTrue);
  });

  test('a request with no answer takes the connection for dead, and makes it again', () async {
    final proxy = await proxyToHub();
    final client = SegueClient(
      url: proxy.url,
      auth: Auth.subsonic(username: newUser(), token: '-', salt: '-'),
      device: const DeviceInfo(
        id: 'laptop',
        name: 'laptop',
        client: 'test',
        api: Api.subsonic,
        roles: [Role.controller],
        capabilities: [],
      ),
      answerTimeout: const Duration(milliseconds: 300),
    );

    unawaited(client.start());
    addTearDown(client.close);
    await until(() => client.status == HubStatus.connected, 'connected');

    proxy.silence();

    // Nothing says the connection died, and the app pings nothing: the command finds out.
    final result = await client.command('tv', const Command(CommandAction.play));

    expect(result.error, 'closed');
    await until(
      () => client.status != HubStatus.connected,
      'the dead connection closed',
      timeout: const Duration(seconds: 10),
    );
    await until(() => client.status == HubStatus.connected, 'connected again', timeout: const Duration(seconds: 5));
  });

  test('when the device it follows comes back and plays, the music kept here goes', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();
    final tv = await App(user, 'tv').start();

    await laptop.player.playQueue(songs, index: 1);
    await until(() => phone.connect.playingId == 'laptop' && tv.connect.playingId == 'laptop', 'the others to follow');
    await laptop.client.close();
    await until(() => phone.player.queue.isNotEmpty && tv.player.queue.isNotEmpty, 'the music kept on the others');

    final again = await App(user, 'laptop').start();

    await until(() => again.player.queue.isNotEmpty, 'the music back on the laptop');
    await again.player.play();
    await until(() => phone.player.queue.isEmpty && tv.player.queue.isEmpty, 'the others to let go of it');
    expect(phone.connect.nowPlaying?.device, 'laptop');
    expect(phone.connect.nowPlaying?.playing, isTrue);
    // Listed on the laptop as left, not as paused with the music it plays.
    await until(
      () => [
        for (final id in ['phone', 'tv']) again.client.devices[id]?.state?.status,
      ].every((status) => status == PlaybackStatus.stopped),
      'the laptop to see the others stopped',
    );
  });

  test('when another device starts playing, one paused with music of its own lets go of it', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await phone.player.playQueue(songs);
    await phone.player.pause();
    await until(
      () => laptop.client.devices['phone']?.state?.status == PlaybackStatus.paused,
      'the laptop to see the phone paused',
    );
    await laptop.player.playQueue(songs, index: 1);
    await until(() => phone.player.queue.isEmpty, 'the phone to let go of its music');
    expect(phone.connect.nowPlaying?.device, 'laptop');
    await until(
      () => laptop.client.devices['phone']?.state?.status == PlaybackStatus.stopped,
      'the laptop to see the phone stopped',
    );
  });

  test('repeat and shuffle go to the device it controls, and show from its state', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs);
    await until(() => phone.connect.nowPlaying?.device == 'laptop', 'the phone to follow the laptop');
    expect(phone.connect.nowPlaying?.canRepeat, isTrue);
    expect(phone.connect.nowPlaying?.canShuffle, isTrue);
    expect((await phone.connect.setRepeat(Repeat.all)).ok, isTrue);
    expect(laptop.player.repeat, Repeat.all);
    await until(() => phone.connect.nowPlaying?.repeat == Repeat.all, 'the phone to show the repeat');
    expect((await phone.connect.setShuffle(true)).ok, isTrue);
    expect(laptop.player.shuffle, isTrue);
    await until(() => phone.connect.nowPlaying?.shuffle ?? false, 'the phone to show the shuffle');
    expect(phone.player.repeat, Repeat.off, reason: 'not the phone\'s own player');
  });

  test('the queue shown is that of the device it controls, and a tap on a track plays it there', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs);
    await until(() => phone.connect.nowPlaying?.device == 'laptop', 'the phone to follow the laptop');
    expect(phone.connect.queue.tracks.map((track) => track.title), ['Dream On', 'Other']);
    expect(phone.connect.queue.index, 0);
    expect(phone.connect.nowPlaying?.canJump, isTrue);
    await laptop.player.pause();
    expect((await phone.connect.jump(1)).ok, isTrue);
    expect(laptop.player.current?.title, 'Other');
    expect(laptop.player.playing, isTrue);
    await until(() => phone.connect.queue.index == 1, 'the phone to see the new track');
    expect(phone.player.queue, isEmpty, reason: 'not the phone\'s own player');
  });

  test('songs played next, or added, go to the queue of the device it controls', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs);
    await until(() => phone.connect.nowPlaying?.device == 'laptop', 'the phone to follow the laptop');
    expect(phone.connect.canAddToQueue, isTrue);
    const added = [Song(id: '4QFKvMsJrd57QE2Le2dKKo', title: 'Added')];
    expect((await phone.connect.addToQueue(added, next: true)).ok, isTrue);
    expect((await phone.connect.addToQueue(added, next: false)).ok, isTrue);
    expect(laptop.player.queue.map((song) => song.title), ['Dream On', 'Added', 'Other', 'Added']);
    expect(laptop.player.current?.title, 'Dream On');
    expect(laptop.player.playing, isTrue);
    await until(() => phone.connect.queue.tracks.length == 4, 'the phone to see the songs added');
    expect(phone.player.queue, isEmpty, reason: 'not the phone\'s own player');
  });

  test('starting to play on one device stops the others: no other is left paused with the music', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs);
    await until(() => phone.connect.playingId == 'laptop', 'the phone to see the laptop playing');
    await phone.player.playQueue(songs, index: 1);
    await until(() => laptop.player.queue.isEmpty, 'the laptop to stop');
    expect(laptop.player.status, PlaybackStatus.stopped);
    await until(
      () => phone.client.devices['laptop']?.state?.status == PlaybackStatus.stopped,
      'the phone to see the laptop stopped, not paused',
    );
    expect(phone.player.playing, isTrue);
    await until(() => laptop.connect.nowPlaying?.device == 'phone', 'the laptop to follow the phone');
  });

  test('the system controls of an app that follows another device command that device', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();
    // In Portuguese, as the app's widget under MaterialApp gives them.
    final controls = MediaControls()
      ..strings = lookupAppLocalizations(const Locale('pt'))
      ..attach(phone.connect, null);

    addTearDown(() => controls.attach(null, null));
    await laptop.player.playQueue(songs);
    await until(() => controls.mediaItem.value?.artist == 'Aerosmith (em laptop)', 'the phone to show the laptop');
    expect(controls.mediaItem.value?.title, 'Dream On');
    await controls.pause();
    expect(laptop.player.playing, isFalse);
    await controls.play();
    expect(laptop.player.playing, isTrue);
  });

  test('a controller moves and removes the tracks in the queue of the device it controls', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs);
    await until(() => phone.connect.nowPlaying?.device == 'laptop', 'the phone to follow the laptop');
    expect(phone.connect.canEditQueue, isTrue);
    expect((await phone.connect.moveInQueue(1, 0)).ok, isTrue);
    await until(() => phone.connect.queue.tracks.first.title == 'Other', 'the queue moved on the phone');
    expect(laptop.player.queue.map((song) => song.title), ['Other', 'Dream On']);
    expect(laptop.player.current?.title, 'Dream On');
    expect(phone.connect.queue.index, 1);
    expect(phone.connect.nowPlaying?.title, 'Dream On');

    expect((await phone.connect.removeFromQueue(1)).error, 'current track');
    expect((await phone.connect.removeFromQueue(0)).ok, isTrue);
    await until(() => phone.connect.queue.tracks.length == 1, 'the track out of the queue on the phone');
    expect(laptop.player.queue.map((song) => song.title), ['Dream On']);
    expect(laptop.player.playing, isTrue);
  });

  test('a device that follows another sees its track change', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs);
    await until(() => phone.connect.nowPlaying?.title == 'Dream On', 'the phone to show the first track');
    await laptop.player.next();
    await until(() => phone.connect.nowPlaying?.title == 'Other', 'the phone to show the next track');
    expect(phone.connect.nowPlaying!.position.inSeconds, lessThan(2));
  });

  test('the Connect flow: control another device, then move the music here', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs, index: 1, position: const Duration(seconds: 30));
    await until(() => phone.client.devices['laptop']?.state?.current != null, 'the laptop queue');

    // Pick the laptop: nothing plays on the phone, so nothing moves; the phone now controls it.
    expect((await phone.connect.switchTo('laptop')).ok, isTrue);
    expect(phone.connect.nowPlaying?.device, 'laptop');
    expect(phone.connect.nowPlaying?.title, 'Other');
    expect((await phone.connect.toggle()).ok, isTrue);
    expect(laptop.player.playing, isFalse);
    expect((await phone.connect.toggle()).ok, isTrue);
    expect(laptop.player.playing, isTrue);
    expect((await phone.connect.next()).error, 'no such track', reason: "the laptop's own error comes back");

    // Pick this phone again: the music moves here, at the laptop's position, and the laptop stops:
    // idle, not paused with music that now plays here.
    expect((await phone.connect.switchTo(null)).ok, isTrue);
    expect(phone.player.queue.map((song) => song.id), songs.map((song) => song.id));
    expect(phone.player.index, 1);
    expect(phone.player.playing, isTrue);
    expect(phone.player.position.inMilliseconds, greaterThanOrEqualTo(30000));
    expect(laptop.player.queue, isEmpty);
    expect(laptop.player.status, PlaybackStatus.stopped);
    await until(
      () => phone.client.devices['laptop']?.state?.status == PlaybackStatus.stopped,
      'the phone to see the laptop stopped, not paused',
    );
    expect(phone.connect.nowPlaying?.device, isNull);
  });

  test('a transfer that names no source moves the last playback from the device that plays it', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(songs, index: 1, position: const Duration(seconds: 30));
    await until(() => phone.client.devices['laptop']?.state?.status == PlaybackStatus.playing, 'the laptop playing');

    expect((await phone.client.transfer(null, 'phone')).ok, isTrue);
    expect(phone.player.queue.map((song) => song.id), songs.map((song) => song.id));
    expect(phone.player.index, 1);
    expect(phone.player.playing, isTrue);
    expect(phone.player.position.inMilliseconds, greaterThanOrEqualTo(30000));
    expect(laptop.player.status, PlaybackStatus.stopped);
  });

  test('the music moved here plays on repeating as it did, shuffled in the same order, which shuffle going off takes '
      'back here too', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await laptop.player.playQueue(three, index: 1);
    await laptop.player.setRepeat(Repeat.all);
    await laptop.player.setShuffle(true);

    final shuffled = titles(laptop.player);

    expect(shuffled, isNot(unshuffled), reason: 'the fake\'s shuffle');
    await until(() => phone.client.devices['laptop']?.state?.order != null, 'the laptop\'s order');

    expect((await phone.connect.switchTo(null)).ok, isTrue);
    expect(titles(phone.player), shuffled);
    expect(phone.player.current?.title, 'Other');
    expect((phone.player.shuffle, phone.player.repeat), (true, Repeat.all));
    await phone.player.setShuffle(false);
    expect(titles(phone.player), unshuffled);
    expect(phone.player.current?.title, 'Other');
  });

  test('the last playback comes back in its modes, shuffled in the same order', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();

    await laptop.player.playQueue(three, index: 1);
    await laptop.player.setRepeat(Repeat.one);
    await laptop.player.setShuffle(true);

    final shuffled = titles(laptop.player);

    await Future<void>.delayed(const Duration(milliseconds: 100)); // the report reaches the hub
    await laptop.client.close();

    final reopened = await App(user, 'laptop').start();

    await until(() => listEquals(titles(reopened.player), shuffled), 'the queue to come back, shuffled as it was');
    expect((reopened.player.shuffle, reopened.player.repeat), (true, Repeat.one));
    await reopened.player.setShuffle(false);
    expect(titles(reopened.player), unshuffled);
  });

  test('playing an album while another device is picked plays it there', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await until(() => phone.client.devices.containsKey('laptop'), 'the laptop');
    await phone.connect.switchTo('laptop');
    expect((await phone.connect.playSongs(songs, 0)).ok, isTrue);
    expect(laptop.player.current?.title, 'Dream On');
    expect(laptop.player.playing, isTrue);
    expect(phone.player.queue, isEmpty);
  });

  test(
    'as the queue ends on the device the app controls, the app controls this one again, where a play goes',
    () async {
      final user = newUser();
      final laptop = await App(user, 'laptop').start();
      final phone = await App(user, 'phone').start();

      await until(() => phone.client.devices.containsKey('laptop'), 'the laptop');
      await phone.connect.switchTo('laptop');
      expect((await phone.connect.playSongs(songs, 0)).ok, isTrue);
      await until(() => phone.connect.nowPlaying?.title == 'Dream On', 'the laptop\'s song on the phone');

      await laptop.player.stop();
      await until(() => phone.connect.activeId == null, 'the phone controlling itself');
      expect(phone.connect.nowPlaying, isNull);
      expect((await phone.connect.playSongs(songs, 0)).ok, isTrue);
      expect(phone.player.current?.title, 'Dream On');
      expect(laptop.player.queue, isEmpty);
    },
  );

  test('the log says the connection coming and going: closed by the hub, with its code, as another copy takes the '
      'device\'s place, and left as the app closes it', () async {
    final user = newUser();
    final messages = <String>[];
    final subscription = Logger.root.onRecord
        .where((record) => record.loggerName == 'SegueClient')
        .listen((record) => messages.add(record.message));
    final first = App(user, 'laptop');
    final second = App(user, 'laptop');

    addTearDown(subscription.cancel);
    addTearDown(first.client.close);
    addTearDown(second.client.close);
    unawaited(first.client.start());
    await until(() => first.client.status == HubStatus.connected, 'the first copy');
    unawaited(second.client.start());
    await until(() => first.client.status == HubStatus.rejected, 'the first copy to give up');
    await until(() => second.client.status == HubStatus.connected, 'the second copy');
    await second.client.close();
    await until(() => messages.length == 4, 'the second copy to leave');
    expect(
      messages,
      unorderedMatches([
        'connected to $hubUrl',
        'connected to $hubUrl',
        startsWith('disconnected from $hubUrl: ${CloseCode.replaced}'),
        'left $hubUrl',
      ]),
    );
    expect(messages.last, 'left $hubUrl');
  });

  test(
    'the log says once that the hub is out of reach, after a connection ends too, until it connects again',
    () async {
      final user = newUser();
      final port = await freePort();
      final (first, url) = await startHub(port: port);
      final laptop = App(user, 'laptop', url: url);
      final messages = <String>[];
      final subscription = Logger.root.onRecord
          .where((record) => record.loggerName == 'SegueClient')
          .listen((record) => messages.add(record.message));

      addTearDown(subscription.cancel);
      addTearDown(first.kill);
      unawaited(laptop.client.start());
      addTearDown(laptop.client.close);
      await until(() => laptop.client.status == HubStatus.connected, 'the laptop connected');
      first.kill();
      await first.exitCode;
      // Tried again 1 s and 3 s after, failing both times.
      await Future<void>.delayed(const Duration(milliseconds: 3500));

      final (second, _) = await startHub(port: port);

      addTearDown(second.kill);
      await until(
        () => laptop.client.status == HubStatus.connected,
        'the laptop connected again',
        timeout: const Duration(seconds: 10),
      );
      expect(messages, [
        'connected to $url',
        startsWith('disconnected from $url: ${CloseCode.goingAway}'),
        'no connection to $url',
        'connected to $url',
      ]);
    },
  );

  test('a command that fails, on another device or on this one, is in the log of both', () async {
    final user = newUser();
    final said = <String>[];
    final subscription = Logger.root.onRecord.listen(
      (record) => said.add('${record.loggerName}: ${record.message}${record.error == null ? '' : ': ${record.error}'}'),
    );

    addTearDown(subscription.cancel);
    await App(user, 'laptop').start();

    final phone = await App(user, 'phone').start();

    await until(() => phone.connect.devices.any((d) => d.id == 'laptop'), 'the laptop');
    await phone.connect.switchTo('laptop');
    // No queue there, nor here.
    expect((await phone.connect.jump(5)).ok, isFalse);
    await phone.connect.switchTo(null);
    expect((await phone.connect.jump(5)).ok, isFalse);
    expect(said, [
      'SegueClient: jump from phone failed: no such track',
      'SegueClient: jump on laptop failed: no such track',
      'ConnectController: jump failed: no such track',
    ]);
  });

  test('a closed app leaves the list of devices to play on', () async {
    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final phone = await App(user, 'phone').start();

    await until(() => phone.connect.devices.any((d) => d.id == 'laptop'), 'the laptop');
    await laptop.client.close();
    await until(() => phone.client.devices['laptop']?.online == false, 'the laptop to go offline');
    expect(phone.connect.devices, isEmpty);
  });

  test('a Jellyfin sign-in joins as a Jellyfin device, and gets queues in Jellyfin ids', () async {
    // With SEGUE_AUTH=none the hub takes every Jellyfin device as the user "dev", and it translates
    // between Navidrome's two kinds of ids.
    final laptop = await App('dev', 'laptop').start();
    final engine = FakeEngine();
    final tv = await Services.start(
      Session(
        server: Uri.parse('https://music.test/jellyfin'),
        credentials: const JellyfinCredentials(username: 'dev', userId: 'u1', token: 't1'),
        deviceId: 'tv',
        deviceName: 'tv',
        hub: hubUrl.replace(scheme: 'http', path: ''),
      ),
      engine: engine,
    );

    addTearDown(tv.dispose);
    await until(() => laptop.connect.devices.any((d) => d.id == 'tv'), 'the tv');
    expect(laptop.client.devices['tv']!.info.api, Api.jellyfin);
    expect((await laptop.connect.switchTo('tv')).ok, isTrue);
    expect((await laptop.connect.playSongs(songs, 0)).ok, isTrue);
    const guids = ['c032d12530e3c18d843d13651f9689ac', 'ffffffffffffffffffffffffffffffff'];
    expect(tv.player.queue.map((song) => song.id), guids);
    expect(engine.tracks.first.path, '/jellyfin/Audio/${guids.first}/stream');
    // What the tv reports reaches the laptop in Subsonic ids.
    await until(() => laptop.connect.queue.tracks.length == 2, 'the tv\'s queue on the laptop');
    expect(laptop.connect.queue.tracks.map((track) => track.id), songs.map((song) => song.id));
  });

  test('a hub not found as the app opens, the media server answering (the network blinking), is the one found next to '
      'it before, which the app connects to', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    // A media server that answers its ping, with no hub found next to it this time.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    addTearDown(server.close);
    server.listen((request) {
      if (request.uri.path.endsWith('/ping.view')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"subsonic-response": {"status": "ok", "version": "1.16.1"}}');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }

      request.response.close();
    });

    final url = Uri.parse('http://127.0.0.1:${server.port}/');

    await Session.rememberFoundHub(url, hubUrl);

    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final tv = await Services.start(
      Session(
        server: url,
        credentials: SubsonicCredentials(username: user, token: '-', salt: '-'),
        deviceId: 'tv',
        deviceName: 'tv',
      ),
      engine: FakeEngine(),
    );

    addTearDown(tv.dispose);
    expect(tv.reachability?.value, isTrue, reason: 'the server in reach');
    await until(() => laptop.connect.devices.any((d) => d.id == 'tv'), 'the tv');
  });

  test(
    'the app opens without waiting for a media server that doesn\'t answer, on the hub found next to it before',
    () async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      // A media server that takes requests and leaves them waiting, as one out of reach may for minutes.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      addTearDown(() => server.close(force: true));
      server.listen((_) {});

      final url = Uri.parse('http://127.0.0.1:${server.port}/');

      await Session.rememberFoundHub(url, hubUrl);

      final user = newUser();
      final laptop = await App(user, 'laptop').start();
      final tv = await Services.start(
        Session(
          server: url,
          credentials: SubsonicCredentials(username: user, token: '-', salt: '-'),
          deviceId: 'tv',
          deviceName: 'tv',
        ),
        engine: FakeEngine(),
      ).timeout(const Duration(seconds: 1));

      addTearDown(tv.dispose);
      await until(() => laptop.connect.devices.any((d) => d.id == 'tv'), 'the tv');
    },
  );

  test('a hub found elsewhere than the one found before is where the app connects, and is kept', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final server = Uri.parse('https://music.test/');

    // Where nothing answers any more.
    await Session.rememberFoundHub(server, Uri.parse('ws://127.0.0.1:1/connect/v1/ws'));

    final user = newUser();
    final laptop = await App(user, 'laptop').start();
    final tv = await Services.start(
      Session(
        server: server,
        credentials: SubsonicCredentials(username: user, token: '-', salt: '-'),
        deviceId: 'tv',
        deviceName: 'tv',
        hub: hubUrl.replace(scheme: 'http', path: ''),
      ),
      engine: FakeEngine(),
    );

    addTearDown(tv.dispose);
    await until(() => laptop.connect.devices.any((d) => d.id == 'tv'), 'the tv');
    expect(await Session.foundHub(server), tv.connect.client!.url);
  });
}
