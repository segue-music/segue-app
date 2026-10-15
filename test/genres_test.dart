import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album/albums_view.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/genre/genre_page.dart';
import 'package:segue/ui/genre/genres_view.dart';
import 'package:segue/ui/player/now_playing_bar.dart';

import 'fakes.dart';
import 'sections.dart';
import 'side_rail.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A server whose genres come out of order, one of them only on songs. Rock has two albums, one of them
/// among the most played (with [played]), with one of hard rock, played less; Blues has one, never
/// played. Its songs at random are two of Rock's, and none of another genre. With [rockAlbums], Rock has that many,
/// more of its own after those two, a page at a time. [asked] gets the queries of the album lists asked for, and of the
/// songs at random.
http.Response server(http.Request request, List<Map<String, String>> asked, {bool played = true, int rockAlbums = 2}) {
  final path = request.url.path;

  if (path.endsWith('getGenres.view')) {
    return subsonic({
      'genres': {
        'genre': [
          {'value': 'Rock', 'songCount': 20, 'albumCount': 2},
          {'value': 'Spoken', 'songCount': 3, 'albumCount': 0},
          {'value': 'Blues', 'songCount': 9, 'albumCount': 1},
          {'value': 'hard rock', 'songCount': 30, 'albumCount': 3},
        ],
      },
    });
  }

  final query = request.url.queryParameters;

  if (path.endsWith('getAlbumList2.view')) {
    asked.add(query);
    return subsonic({
      'albumList2': {
        'album': [
          if (query['type'] == 'byGenre' && query['genre'] == 'Rock')
            ...[
              {'id': 'a1', 'name': 'Rocks', 'artist': 'Aerosmith'},
              {'id': 'a2', 'name': 'Toys in the Attic', 'artist': 'Aerosmith'},
              for (var i = 2; i < rockAlbums; i++) {'id': 'r$i', 'name': 'Rock $i', 'artist': 'Aerosmith'},
            ].skip(int.parse(query['offset'] ?? '0')).take(int.parse(query['size'] ?? '500')),
          if (query['type'] == 'byGenre' && query['genre'] == 'Blues')
            {'id': 'b1', 'name': 'Honky Tonk Blues', 'artist': 'Aerosmith'},
          if (query['type'] == 'frequent' && played) ...[
            {
              'id': 'a3',
              'name': 'Pump',
              'artist': 'Aerosmith',
              'playCount': 4,
              'genres': [
                {'name': 'hard rock'},
              ],
            },
            {
              'id': 'a2',
              'name': 'Toys in the Attic',
              'artist': 'Aerosmith',
              'playCount': 9,
              'genres': [
                {'name': 'Rock'},
              ],
            },
          ],
        ],
      },
    });
  }

  if (path.endsWith('getRandomSongs.view')) {
    asked.add(query);
    return subsonic({
      'randomSongs': {
        'song': [
          if (query['genre'] == 'Rock') ...[
            {'id': 's2', 'title': 'Back in the Saddle', 'artist': 'Aerosmith', 'albumId': 'a1'},
            {'id': 's1', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'albumId': 'a2'},
          ],
        ],
      },
    });
  }

  if (path.endsWith('getAlbum.view')) {
    return subsonic({
      'album': {
        'id': 'a2',
        'name': 'Toys in the Attic',
        'artist': 'Aerosmith',
        'song': [
          {'id': 's1', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'duration': 220},
        ],
      },
    });
  }

  return http.Response('', 404);
}

/// The home page on a screen of [size], over the [server]; returns the queries of the album lists
/// asked for.
Future<List<Map<String, String>>> pumpHome(
  WidgetTester tester,
  Size size, {
  bool played = true,
  int rockAlbums = 2,
}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final asked = <Map<String, String>>[];
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request, asked, played: played, rockAlbums: rockAlbums)),
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

  return asked;
}

Finder title(String text) => find.descendant(of: find.byType(AppBar), matching: find.text(text));

/// A genre in the list of them all.
Finder tile(String name) => find.widgetWithText(ListTile, name);

/// A genre among the most listened to.
Finder button(String name) => find.widgetWithText(FilledButton, name);

void main() {
  testWidgets('a genre whose albums the server can\'t give says so, and nothing else fails unheard', (tester) async {
    const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
    // A server that has nothing of it any more.
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'failed',
              'error': {'code': 70, 'message': 'not found'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final player = PlayerController(FakeEngine(), api);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => ServicesScope(services: services, child: child!),
        home: const GenrePage(Genre(id: 'Gone', name: 'Gone')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Não consegui listar os álbuns'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the side rail goes to the genres, by name, each with its number of albums, and a genre shows its '
      'albums', (tester) async {
    final asked = await pumpHome(tester, const Size(1000, 700));

    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Gêneros'), findsOneWidget);

    final [blues, hardRock, rock] = [
      for (final name in ['Blues', 'hard rock', 'Rock']) tester.getRect(tile(name)),
    ];

    expect(hardRock.top, greaterThanOrEqualTo(blues.bottom), reason: 'by name, whatever the case');
    expect(rock.top, greaterThanOrEqualTo(hardRock.bottom));
    expect(find.text('1 álbum'), findsOneWidget);
    expect(find.text('3 álbuns'), findsOneWidget);
    expect(find.text('2 álbuns'), findsOneWidget);
    expect(find.text('Spoken'), findsNothing, reason: 'a genre with no albums leads nowhere');

    await tester.tap(tile('Rock'));
    await tester.pumpAndSettle();
    expect(title('Rock'), findsOneWidget);
    expect(find.text('Rocks'), findsOneWidget);
    expect(find.text('Toys in the Attic'), findsWidgets);
    expect(asked, contains(allOf(containsPair('type', 'byGenre'), containsPair('offset', '0'))));

    // In the grid, under the button that plays a mix and the row of the most played.
    await tester.ensureVisible(find.text('Toys in the Attic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toys in the Attic').last);
    await tester.pumpAndSettle();
    expect(find.text('Walk This Way'), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Gêneros'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('the genres start with those the user listens to most, the most first, each opening its page', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();

    final heading = tester.getRect(find.text('Mais tocados'));
    final rock = tester.getRect(button('Rock'));
    final hardRock = tester.getRect(button('hard rock'));
    final all = tester.getRect(find.text('Todos os gêneros'));

    expect(rock.top, greaterThan(heading.bottom));
    expect(hardRock.top, rock.top);
    expect(hardRock.left, greaterThan(rock.right), reason: 'Rock, played more, first');
    expect(all.top, greaterThan(rock.bottom));
    expect(tester.getRect(tile('Blues')).top, greaterThan(all.bottom));
    expect(button('Blues'), findsNothing, reason: 'never played');

    await tester.tap(button('hard rock'));
    await tester.pumpAndSettle();
    expect(title('hard rock'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('before anything has played, the genres are just the list of them all', (tester) async {
    await pumpHome(tester, const Size(1000, 700), played: false);
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    expect(tile('Blues'), findsOneWidget);
    expect(find.text('Mais tocados'), findsNothing);
    expect(find.text('Todos os gêneros'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a genre\'s page starts with a row of its most played albums, above all of them', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    await tester.tap(tile('Rock'));
    await tester.pumpAndSettle();

    final row = find.byWidgetPredicate((widget) => widget is ListView && widget.scrollDirection == Axis.horizontal);

    expect(find.descendant(of: row, matching: find.text('Toys in the Attic')), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Pump')),
      findsNothing,
      reason: 'another genre\'s',
    );
    expect(
      find.descendant(of: row, matching: find.text('Rocks')),
      findsNothing,
      reason: 'never played',
    );

    final mostPlayed = tester.getRect(find.text('Mais tocados'));
    final all = tester.getRect(find.text('Álbuns'));

    expect(tester.getRect(row).top, greaterThan(mostPlayed.bottom));
    expect(all.top, greaterThan(tester.getRect(row).bottom));
    expect(tester.getRect(find.text('Rocks')).top, greaterThan(all.bottom));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a genre with more albums than a page asks for the next as its grid nears its end, not as its row of '
      'the most played lays out', (tester) async {
    final asked = await pumpHome(tester, const Size(1000, 700), rockAlbums: 450);

    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    asked.clear();
    await tester.tap(tile('Rock'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final query in asked)
          if (query['type'] == 'byGenre') query['offset'],
      ],
      ['0'],
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a genre\'s page starts with a button that plays a mix of its songs, at random', (tester) async {
    final asked = await pumpHome(tester, const Size(1000, 700));

    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    await tester.tap(tile('Rock'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Tocar um mix')).bottom,
      lessThan(tester.getRect(find.text('Mais tocados')).top),
      reason: 'above the most played',
    );

    await tester.tap(find.text('Tocar um mix'));
    await tester.pumpAndSettle();

    final player = ServicesScope.of(tester.element(find.byType(GenrePage))).player;

    expect([for (final song in player.queue) song.title], ['Back in the Saddle', 'Walk This Way']);
    expect(player.playing, isTrue);
    expect(asked.last, allOf(containsPair('genre', 'Rock'), containsPair('size', '100')));
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('a genre with nothing played has no row of the most played, just its albums', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    await tester.tap(tile('Blues'));
    await tester.pumpAndSettle();
    expect(find.text('Honky Tonk Blues'), findsOneWidget);
    expect(find.text('Mais tocados'), findsNothing);
    expect(find.text('Álbuns'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dragged down from its top, the genres come again', (tester) async {
    final asked = await pumpHome(tester, const Size(360, 640));

    await openSection(tester, 'Gêneros');

    // The genres' most played come from the 500 most played albums, as the home's mixes do, which the home's row of
    // the most played isn't.
    int mostPlayed() => asked.where((query) => query['type'] == 'frequent' && query['size'] == '500').length;

    final before = mostPlayed();
    final list = find.descendant(of: find.byType(GenresView), matching: find.byType(Scrollable));

    await tester.dragFrom(tester.getTopLeft(list) + const Offset(100, 20), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(mostPlayed(), before + 1);
    expect(tile('Blues'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the genres are in the search, until something is searched, in the bar at the bottom, which '
      'stays under a genre\'s page', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Buscar')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(SearchBar)), findsOneWidget);
    expect(tile('hard rock'), findsOneWidget);

    await tester.tap(tile('hard rock'));
    await tester.pumpAndSettle();

    final page = find.byType(GenrePage);

    await ServicesScope.of(tester.element(page)).player.playQueue(const [Song(id: 's1', title: 'Dream Police')]);
    await tester.pumpAndSettle();

    // Under the home's bars, which stay; the albums go on behind them, and end clear of them.
    final grid = find.descendant(of: page, matching: find.byType(AlbumGrid));

    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    expect(find.descendant(of: page, matching: find.byType(NowPlayingBar)), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.getRect(grid).bottom, 640);
    expect(MediaQuery.paddingOf(tester.element(grid)).bottom, 640 - tester.getRect(find.byType(NowPlayingBar)).top);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timer
  });
}
