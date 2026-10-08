import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/now_playing_bar.dart';
import 'package:segue/ui/playlist_page.dart';
import 'package:segue/ui/playlists_view.dart';

import 'fakes.dart';
import 'side_rail.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

const roadTrip = {'id': 'p1', 'name': 'Road trip', 'songCount': 2, 'coverArt': 'pl-p1'};

/// A server with three playlists, out of order: Road trip, with two songs from two albums, Chill and an empty one.
/// [playlists] none, it has none. [asked] gets the endpoints asked for.
http.Response server(http.Request request, {bool playlists = true, List<String>? asked}) {
  final query = request.url.queryParameters;
  asked?.add(request.url.pathSegments.last);
  return switch (request.url.pathSegments.last) {
    'getPlaylists.view' => subsonic({
      'playlists': {
        'playlist': [
          if (playlists) ...[
            roadTrip,
            {'id': 'p2', 'name': 'chill', 'songCount': 12},
            {'id': 'p3', 'name': 'Empty', 'songCount': 0},
          ],
        ],
      },
    }),
    'getPlaylist.view' when query['id'] == 'p1' => subsonic({
      'playlist': {
        ...roadTrip,
        'entry': [
          {
            'id': 's2',
            'title': 'Sweet Emotion',
            'artist': 'Aerosmith',
            'artistId': 'ar1',
            'album': 'Toys in the Attic',
            'albumId': 'a1',
            'duration': 274,
          },
          {
            'id': 's9',
            'title': 'Dream Police',
            'artist': 'Cheap Trick',
            'artistId': 'ar2',
            'album': 'Dream Police',
            'albumId': 'a9',
            'duration': 226,
          },
        ],
      },
    }),
    'getPlaylist.view' => subsonic({
      'playlist': {'id': 'p3', 'name': 'Empty', 'songCount': 0},
    }),
    'getAlbumList2.view' => subsonic({
      'albumList2': {'album': <Object>[]},
    }),
    _ => http.Response('', 404),
  };
}

/// The home page on a screen of [size], over the [server], which tells [asked] what it's asked for; returns its player.
Future<PlayerController> pumpHome(WidgetTester tester, Size size, {bool playlists = true, List<String>? asked}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request, playlists: playlists, asked: asked)),
  );
  final player = PlayerController(FakeEngine(), api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pumpAndSettle();
  return player;
}

Finder tile(String name) => find.widgetWithText(ListTile, name);

void main() {
  testWidgets('the side rail goes to the playlists, by name, each with its number of songs, and one opens its page', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Playlists'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Playlists'), findsOneWidget);

    final [chill, empty, roadTrip] = [
      for (final name in ['chill', 'Empty', 'Road trip']) tester.getRect(tile(name)),
    ];
    expect(empty.top, greaterThanOrEqualTo(chill.bottom), reason: 'by name, whatever the case');
    expect(roadTrip.top, greaterThanOrEqualTo(empty.bottom));
    expect(find.text('12 faixas'), findsOneWidget);
    expect(find.text('2 faixas'), findsOneWidget);

    await tester.tap(tile('Road trip'));
    await tester.pumpAndSettle();
    final page = find.byType(PlaylistPage);
    expect(find.descendant(of: page, matching: find.text('Road trip')), findsOneWidget);
    expect(find.descendant(of: page, matching: find.text('Playlist')), findsOneWidget);
    expect(find.text('2 faixas, 8 min'), findsOneWidget);

    final [sweetEmotion, dreamPolice] = [
      for (final title in ['Sweet Emotion', 'Dream Police']) tester.getRect(tile(title)),
    ];
    expect(dreamPolice.top, greaterThanOrEqualTo(sweetEmotion.bottom), reason: 'in the playlist\'s order');
    expect(find.descendant(of: tile('Dream Police'), matching: find.text('Cheap Trick')), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Playlists'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('a playlist plays from the song picked, or from its first with its button, the songs in its order', (
    tester,
  ) async {
    final player = await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(tile('Road trip'));
    await tester.pumpAndSettle();

    await tester.tap(tile('Dream Police'));
    await tester.pumpAndSettle();
    expect([for (final song in player.queue) song.id], ['s2', 's9']);
    expect(player.current?.id, 's9');
    expect(tester.widget<ListTile>(tile('Dream Police')).selected, isTrue, reason: 'the current song stands out');

    await tester.tap(find.byTooltip('Tocar a playlist').first);
    await tester.pumpAndSettle();
    expect(player.current?.id, 's2');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an empty playlist says so, and can\'t be played', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(tile('Empty'));
    await tester.pumpAndSettle();
    expect(find.text('Essa playlist está vazia.'), findsOneWidget);
    expect(find.textContaining('0 faixas'), findsNothing, reason: 'nor how long its songs last');
    final play = find.ancestor(of: find.byTooltip('Tocar a playlist'), matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(play).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with no playlists, the section says so', (tester) async {
    await pumpHome(tester, const Size(1000, 700), playlists: false);
    await tester.tap(find.byTooltip('Playlists'));
    await tester.pumpAndSettle();
    expect(find.text('Ainda não há playlists.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (device, kind, size, platform) in [
    ('a finger, on a phone', PointerDeviceKind.touch, const Size(360, 640), TargetPlatform.android),
    ('the mouse, on a computer', PointerDeviceKind.mouse, const Size(1000, 700), TargetPlatform.linux),
  ]) {
    testWidgets('dragged down from its top by $device, the playlists come again, also fewer than fill the screen', (
      tester,
    ) async {
      final asked = <String>[];
      await pumpHome(tester, size, asked: asked);
      await tester.tap(
        size.width < 600
            ? find.descendant(of: find.byType(NavigationBar), matching: find.text('Playlists'))
            : find.byTooltip('Playlists'),
      );
      await tester.pumpAndSettle();
      expect(asked.where((endpoint) => endpoint == 'getPlaylists.view'), hasLength(1));

      final list = find.descendant(of: find.byType(PlaylistsView), matching: find.byType(Scrollable));
      await tester.dragFrom(tester.getTopLeft(list) + const Offset(300, 20), const Offset(0, 300), kind: kind);
      await tester.pumpAndSettle();
      expect(asked.where((endpoint) => endpoint == 'getPlaylists.view'), hasLength(2));
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('on a phone, the playlists are in the bar at the bottom, which stays under a playlist\'s page', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 640));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Playlists')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Playlists')), findsOneWidget);

    await tester.tap(tile('Road trip'));
    await tester.pumpAndSettle();
    final page = find.byType(PlaylistPage);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Road trip')), findsOneWidget);
    expect(find.text('Sweet Emotion'), findsOneWidget);
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    expect(find.descendant(of: page, matching: find.byType(NowPlayingBar)), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
