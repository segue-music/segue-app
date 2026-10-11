import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/media_controls.dart';
import 'package:segue/player/player.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/server/models.dart';
import 'package:segue/subsonic/api.dart';

import 'fakes.dart';
import 'music_library.dart';

/// A hub client that sees the device tv play, which the app then follows.
SegueClient tvPlaying() {
  final client = SegueClient(
    url: Uri.parse('ws://unused'),
    auth: const Auth.subsonic(username: 'a', token: 't', salt: 's'),
    device: const DeviceInfo(id: 'me', name: 'me', client: 'test', api: Api.subsonic, roles: [], capabilities: []),
  );
  client.devices['tv'] = Device(
    info: const DeviceInfo(
      id: 'tv',
      name: 'tv',
      client: 'test',
      api: Api.subsonic,
      roles: [Role.player],
      capabilities: CommandAction.values,
    ),
    online: true,
    state: StampedState(
      status: PlaybackStatus.playing,
      positionMs: 0,
      at: DateTime.now().millisecondsSinceEpoch,
      index: 0,
      queue: const [QueueItem(id: 's4', title: 'So What', artist: 'Miles Davis')],
    ),
  );

  return client;
}

List<String> titles(PlayerController player) => [for (final song in player.queue) song.title];

const songs = [
  Song(id: 's1', title: 'Dream On', artist: 'Aerosmith', duration: Duration(minutes: 4)),
  Song(id: 's2', title: 'Other', artist: 'Someone', duration: Duration(minutes: 3)),
];

void main() {
  test("the system controls show this device's playback and command it", () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
      client: MockClient((_) async => http.Response('', 404)),
    );
    final player = PlayerController(FakeEngine(), api);
    final controls = MediaControls()..attach(ConnectController(player: player), api);
    expect(controls.mediaItem.value, isNull);

    await player.playQueue(songs, position: const Duration(seconds: 30));
    expect(controls.mediaItem.value?.title, 'Dream On');
    expect(controls.mediaItem.value?.artist, 'Aerosmith');
    expect(controls.mediaItem.value?.duration, const Duration(minutes: 4));
    expect(controls.playbackState.value.playing, isTrue);
    expect(controls.playbackState.value.updatePosition.inSeconds, 30);

    await controls.pause();
    expect(player.playing, isFalse);
    expect(controls.playbackState.value.playing, isFalse);
    await controls.play();
    expect(player.playing, isTrue);
    await controls.skipToNext();
    expect(controls.mediaItem.value?.title, 'Other');
    await controls.seek(const Duration(seconds: 90));
    expect(player.position.inSeconds, greaterThanOrEqualTo(90));

    controls.attach(null, null); // signing out
    expect(controls.mediaItem.value, isNull);
  });

  test('a song on another device says which, in the app\'s language, and again as it changes', () {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
      client: MockClient((_) async => http.Response('', 404)),
    );
    final client = SegueClient(
      url: Uri.parse('ws://unused'),
      auth: const Auth.subsonic(username: 'a', token: 't', salt: 's'),
      device: const DeviceInfo(id: 'me', name: 'me', client: 'test', api: Api.subsonic, roles: [], capabilities: []),
    );
    client.devices['tv'] = Device(
      info: const DeviceInfo(
        id: 'tv',
        name: 'tv',
        client: 'test',
        api: Api.subsonic,
        roles: [Role.player],
        capabilities: [],
      ),
      online: true,
      state: StampedState(
        status: PlaybackStatus.playing,
        positionMs: 0,
        at: DateTime.now().millisecondsSinceEpoch,
        index: 0,
        queue: const [QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith')],
      ),
    );
    final connect = ConnectController(player: PlayerController(FakeEngine(), api), client: client);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    client.notifyListeners(); // as when the TV's state arrives
    final controls = MediaControls()..attach(connect, api);
    expect(controls.mediaItem.value?.artist, 'Aerosmith', reason: 'without the app\'s words yet');

    controls.strings = lookupAppLocalizations(const Locale('pt'));
    expect(controls.mediaItem.value?.artist, 'Aerosmith (em tv)');

    controls.strings = lookupAppLocalizations(const Locale('en'));
    expect(controls.mediaItem.value?.artist, 'Aerosmith (on tv)');
    controls.attach(null, null);
  });

  test('the app swiped out of the recent apps, it closes', () async {
    final controls = MediaControls();
    var closed = 0;
    await controls.onTaskRemoved(); // with nothing to end it yet
    controls.close = () async => closed++;
    await controls.onTaskRemoved();
    expect(closed, 1);
  });

  test('closed, a play opens the app again, and plays the music it brings back', () async {
    final controls = MediaControls();
    var opened = 0;
    controls.open = () => opened++;
    await controls.play();
    expect(opened, 1);

    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
      client: MockClient((_) async => http.Response('', 404)),
    );
    final connect = ConnectController(player: PlayerController(FakeEngine(), api));
    controls.attach(connect, null);
    expect(connect.playRestoredBy, isNotNull);
    controls.attach(null, null);
  });

  group('in the car (Android Auto)', () {
    test('what the car asks for before the app has a session waits for it, the app closed opening for it', () async {
      final controls = MediaControls();
      var opened = 0;
      controls.open = () => opened++;
      final tabs = controls.getChildren(AudioService.browsableRootId);
      await pumpEventQueue();
      expect(opened, 1);

      final api = musicLibrary();
      controls.attach(ConnectController(player: PlayerController(FakeEngine(), api)), api);
      expect((await tabs).map((tab) => tab.title), ['Home', 'Playlists', 'Albums', 'Artists'], reason: 'English first');
      controls.strings = lookupAppLocalizations(const Locale('pt'));
      expect((await controls.getChildren(AudioService.browsableRootId)).map((tab) => tab.title), [
        'Início',
        'Playlists',
        'Álbuns',
        'Artistas',
      ], reason: 'in the app\'s words, once it has them');
      controls.attach(null, null);
    });

    test('the car is told that what it opened changed, as the session or the language does, and asks again', () async {
      final controls = MediaControls();
      final told = <Map<String, dynamic>>[];
      controls.subscribeToChildren(AudioService.browsableRootId).listen(told.add);
      final api = musicLibrary();
      controls.attach(ConnectController(player: PlayerController(FakeEngine(), api)), api);
      await pumpEventQueue();
      expect(told, hasLength(1));
      controls.strings = lookupAppLocalizations(const Locale('pt'));
      await pumpEventQueue();
      expect(told, hasLength(2));
      controls.attach(null, null);
      await pumpEventQueue();
      expect(told, hasLength(3));
    });

    test(
      'what the car picks plays here, whose sound the car\'s is, also where the app controls another device',
      () async {
        final api = musicLibrary();
        final client = tvPlaying();
        final player = PlayerController(FakeEngine(), api);
        final connect = ConnectController(player: player, client: client);
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        client.notifyListeners(); // as when the TV's state arrives
        expect(connect.activeId, 'tv');

        final controls = MediaControls()..attach(connect, api);
        final albums = await controls.getChildren('albums');
        final songs = await controls.getChildren(albums.last.id);
        await controls.playFromMediaId(songs.last.id);
        expect(titles(player), ['Sweet Emotion', 'Walk This Way']);
        expect(player.current?.title, 'Walk This Way');
        expect(player.playing, isTrue);
        expect(connect.activeId, isNull, reason: 'the app follows this device');
        controls.attach(null, null);
      },
    );

    test('said to the car, what it finds plays here; nothing said, the music the app has, or else any; and what it '
        'doesn\'t find, it says', () async {
      final api = musicLibrary();
      final player = PlayerController(FakeEngine(), api);
      final controls = MediaControls()..attach(ConnectController(player: player), api);
      controls.strings = lookupAppLocalizations(const Locale('pt'));

      await controls.playFromSearch('');
      expect(player.queue, hasLength(4), reason: 'songs at random');
      expect(player.playing, isTrue);
      await controls.playFromSearch('pump');
      expect(titles(player), ['Love in an Elevator']);
      await player.pause();
      await controls.playFromSearch('');
      expect(titles(player), ['Love in an Elevator'], reason: 'the music it had, on');
      expect(player.playing, isTrue);

      await controls.playFromSearch('zzz');
      expect(controls.playbackState.value.processingState, AudioProcessingState.error);
      expect(controls.playbackState.value.errorMessage, 'Nada encontrado.');
      expect(titles(player), ['Love in an Elevator'], reason: 'as it was');
      controls.attach(null, null);
    });

    test('the car shows a stretch of the queue around the current track, and plays the track picked in it', () async {
      final api = musicLibrary();
      final player = PlayerController(FakeEngine(), api);
      await player.playQueue([for (var i = 0; i < 150; i++) Song(id: 's$i', title: 'Song $i')], index: 50, play: false);
      final controls = MediaControls()..attach(ConnectController(player: player), api);
      expect(controls.queue.value.first.title, 'Song 40');
      expect(controls.queue.value.last.title, 'Song 149');
      expect(controls.playbackState.value.queueIndex, 10);

      await controls.skipToQueueItem(15);
      expect(player.index, 55);
      expect(controls.queue.value.first.title, 'Song 45', reason: 'around it again');
      expect(controls.playbackState.value.queueIndex, 10);
      controls.attach(null, null);
      expect(controls.queue.value, isEmpty);
    });

    test(
      'the music to resume is the song that played last, which plays on, known also once the app has closed',
      () async {
        final api = musicLibrary();
        final player = PlayerController(FakeEngine(), api);
        final controls = MediaControls()..attach(ConnectController(player: player), api);
        await player.playQueue(songs, play: false);
        final recent = await controls.getChildren(AudioService.recentRootId);
        expect(recent.single.title, 'Dream On');
        expect(recent.single.playable, isTrue);

        await controls.playFromMediaId(recent.single.id);
        expect(player.playing, isTrue);
        controls.attach(null, null); // closed
        expect((await controls.getChildren(AudioService.recentRootId)).single.title, 'Dream On');
      },
    );
  });
}
