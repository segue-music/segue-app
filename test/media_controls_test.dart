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
}
