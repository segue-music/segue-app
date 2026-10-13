import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/home_cache.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/mixes.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/server/reachability.dart';
import 'package:segue/server/server.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/home/home_view.dart';
import 'package:segue/ui/widgets/spinner.dart';

import 'fakes.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A library whose most played albums, and whose every other list of albums, are [albums]: of rock of the 1970s and
/// jazz of the 1950s, the genres and decades of its mixes, whose songs are two by Aerosmith, whom the server has a
/// picture of. It answers once [answer] completes, where there is one; [asked] gets the endpoints asked for.
SubsonicApi library({List<String> albums = const ['Toys in the Attic'], List<String>? asked, Future<void>? answer}) =>
    SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        final endpoint = request.url.pathSegments.last;
        asked?.add(endpoint);
        await answer;

        return switch (endpoint) {
          'getAlbumList2.view' => subsonic({
            'albumList2': {
              'album': [
                for (final (i, name) in albums.indexed)
                  {
                    'id': 'a$i',
                    'name': name,
                    'artist': 'Aerosmith',
                    'genre': i.isEven ? 'Rock' : 'Jazz',
                    'year': i.isEven ? 1975 : 1959,
                    'playCount': 20 - i,
                  },
              ],
            },
          }),
          'getRandomSongs.view' => subsonic({
            'randomSongs': {
              'song': [
                {'id': 's1', 'title': 'Sweet Emotion', 'artist': 'Aerosmith', 'artistId': 'r1', 'albumId': 'a0'},
                {'id': 's2', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'artistId': 'r1', 'albumId': 'a0'},
              ],
            },
          }),
          'getArtist.view' => subsonic({
            'artist': {'id': 'r1', 'name': 'Aerosmith', 'coverArt': 'ar-r1'},
          }),
          _ => http.Response('', 404),
        };
      }),
    );

const toys = Album(id: 'a1', name: 'Toys in the Attic', artist: 'Aerosmith', year: 1975);
const pump = Album(id: 'a2', name: 'Pump', artist: 'Aerosmith', year: 1989);

/// What [mixes] are of: a genre by its name, a decade by its first year.
List<Object> about(List<Mix> mixes) => [
  for (final mix in mixes)
    switch (mix) {
      GenreMix(:final genre) => genre.name,
      DecadeMix(:final decade) => decade,
    },
];

/// [names] of the albums [albums].
List<String> names(List<Album>? albums) => [for (final album in albums ?? const <Album>[]) album.name];

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('segue-home');
    file = File('${directory.path}/home.json');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('a row\'s albums are kept for the next time; listed again the same, those shown stay', () async {
    final first = await HomeCache.open(file);
    expect(first.albums(AlbumOrder.latest), isNull);
    final albums = [toys, pump];
    expect(await first.keepAlbums(AlbumOrder.latest, Future.value(albums)), same(albums));
    await first.idle;

    final second = await HomeCache.open(file);
    final kept = second.albums(AlbumOrder.latest);
    expect(names(kept), ['Toys in the Attic', 'Pump']);
    expect(kept!.first.year, 1975);
    expect(await second.keepAlbums(AlbumOrder.latest, Future.value([toys, pump]), shown: kept), same(kept));

    final other = [pump];
    expect(await second.keepAlbums(AlbumOrder.latest, Future.value(other), shown: kept), same(other));
    await second.idle;
    expect(names((await HomeCache.open(file)).albums(AlbumOrder.latest)), ['Pump']);
  });

  test('out of reach, the albums the downloads give aren\'t kept', () async {
    final reachability = Reachability(
      () async => throw const SocketException('no route to host'),
      retry: const Duration(hours: 1),
    );
    addTearDown(reachability.dispose);
    await reachability.check();
    final cache = await HomeCache.open(file, reachability: reachability);
    await cache.keepAlbums(AlbumOrder.latest, Future.value([toys]));
    await cache.idle;
    expect((await HomeCache.open(file)).albums(AlbumOrder.latest), isNull);
  });

  test('a file that can\'t be read keeps nothing', () async {
    file.writeAsStringSync('{"albums": {"latest": [{"name": 3}]}');
    expect((await HomeCache.open(file)).albums(AlbumOrder.latest), isNull);
  });

  test(
    'the first time, the mixes are new ones, kept for the next, which shows them at once, with their first songs and '
    'pictures, and picks others for the one after',
    () async {
      final first = await HomeCache.open(file);
      final shown = first.mixes(library());
      expect(shown.keptMixes, isNull);
      final mixes = about(await shown.mixes);
      await first.idle;

      final asked = <String>[];
      final second = await HomeCache.open(file);
      final kept = second.mixes(library(asked: asked));
      expect(about(kept.keptMixes!), mixes);
      final mix = kept.keptMixes!.first;
      expect([for (final song in kept.keptFirstSongs(mix)!) song.title], ['Sweet Emotion', 'Walk This Way']);
      expect(kept.keptPicture(mix)?.artist.coverArt, 'ar-r1');
      expect(about(second.mixes(library()).keptMixes!), mixes, reason: 'the same all the session');
      await second.idle;
      expect(asked, containsAll(['getAlbumList2.view', 'getRandomSongs.view']), reason: 'the next ones picked');

      expect((await HomeCache.open(file)).mixes(library()).keptMixes, isNotNull);
    },
  );

  test('out of reach, the next time\'s mixes aren\'t picked', () async {
    final reachability = Reachability(
      () async => throw const SocketException('no route to host'),
      retry: const Duration(hours: 1),
    );
    addTearDown(reachability.dispose);
    await reachability.check();
    final asked = <String>[];
    final cache = await HomeCache.open(file, reachability: reachability);
    cache.mixes(library(asked: asked));
    await cache.idle;
    expect(file.existsSync(), isFalse);
  });

  testWidgets('as the app opens, the home shows what it showed the time before at once, rather than spinners, and what '
      'comes anew as it comes', (tester) async {
    final cache = (await tester.runAsync(() async {
      final first = await HomeCache.open(file);

      for (final order in AlbumOrder.values) {
        await first.keepAlbums(order, Future.value([toys]));
      }

      await first.mixes(library()).mixes;
      await first.idle;

      return HomeCache.open(file);
    }))!;
    final answer = Completer<void>();
    final api = library(albums: ['Night in the Ruts'], answer: answer.future);
    final player = PlayerController(FakeEngine(), api);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
      homeCache: cache,
    );
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => ServicesScope(services: services, child: child!),
        home: const Scaffold(body: HomeView()),
      ),
    );
    expect(find.byType(Spinner), findsNothing);
    expect(find.text('Toys in the Attic'), findsNWidgets(3), reason: 'in each row');
    expect(find.text('Rock'), findsOneWidget, reason: 'the mixes');
    expect(find.text('Aerosmith'), findsWidgets, reason: 'their artists');

    answer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Night in the Ruts'), findsNWidgets(3));
    expect(find.text('Toys in the Attic'), findsNothing);
    expect(find.text('Rock'), findsOneWidget, reason: 'the mixes the same until the home loads again');
    cache.close();
  });
}
