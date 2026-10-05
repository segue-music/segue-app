import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/home_page.dart';

import 'fakes.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A server whose genres come out of order, one of them only on songs. Rock has two albums, one of them
/// among the most played, with one of hard rock; Blues has one, never played. [asked] gets the queries
/// of the album lists asked for.
http.Response server(http.Request request, List<Map<String, String>> asked) {
  final path = request.url.path;
  final query = request.url.queryParameters;

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

  if (path.endsWith('getAlbumList2.view')) {
    asked.add(query);
    return subsonic({
      'albumList2': {
        'album': [
          if (query['type'] == 'byGenre' && query['genre'] == 'Rock') ...[
            {'id': 'a1', 'name': 'Rocks', 'artist': 'Aerosmith'},
            {'id': 'a2', 'name': 'Toys in the Attic', 'artist': 'Aerosmith'},
          ],
          if (query['type'] == 'byGenre' && query['genre'] == 'Blues')
            {'id': 'b1', 'name': 'Honky Tonk Blues', 'artist': 'Aerosmith'},
          if (query['type'] == 'frequent') ...[
            {
              'id': 'a3',
              'name': 'Pump',
              'artist': 'Aerosmith',
              'genres': [
                {'name': 'hard rock'},
              ],
            },
            {
              'id': 'a2',
              'name': 'Toys in the Attic',
              'artist': 'Aerosmith',
              'genres': [
                {'name': 'Rock'},
              ],
            },
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

/// The home page on a screen of [size]; returns the queries of the album lists asked for.
Future<List<Map<String, String>>> pumpHome(WidgetTester tester, Size size) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final asked = <Map<String, String>>[];
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request, asked)),
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
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pumpAndSettle();
  return asked;
}

Finder title(String text) => find.descendant(of: find.byType(AppBar), matching: find.text(text));

void main() {
  testWidgets('the side rail goes to the genres, by name, each with its number of albums, and a genre shows its '
      'albums', (tester) async {
    final asked = await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    expect(title('Gêneros'), findsOneWidget);

    final [blues, hardRock, rock] = [
      for (final name in ['Blues', 'hard rock', 'Rock']) tester.getRect(find.text(name)),
    ];
    expect(hardRock.top, greaterThan(blues.bottom), reason: 'by name, whatever the case');
    expect(rock.top, greaterThan(hardRock.bottom));
    expect(find.text('1 álbum'), findsOneWidget);
    expect(find.text('3 álbuns'), findsOneWidget);
    expect(find.text('2 álbuns'), findsOneWidget);
    expect(find.text('Spoken'), findsNothing, reason: 'a genre with no albums leads nowhere');

    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    expect(title('Rock'), findsOneWidget);
    expect(find.text('Rocks'), findsOneWidget);
    expect(find.text('Toys in the Attic'), findsWidgets);
    expect(asked, contains(allOf(containsPair('type', 'byGenre'), containsPair('offset', '0'))));

    await tester.tap(find.text('Toys in the Attic').last);
    await tester.pumpAndSettle();
    expect(find.text('Walk This Way'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(title('Gêneros'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('a genre\'s page starts with a row of its most played albums, above all of them', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rock'));
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

  testWidgets('a genre with nothing played has no row of the most played, just its albums', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blues'));
    await tester.pumpAndSettle();
    expect(find.text('Honky Tonk Blues'), findsOneWidget);
    expect(find.text('Mais tocados'), findsNothing);
    expect(find.text('Álbuns'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the genres are in the bar at the bottom', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Gêneros')));
    await tester.pumpAndSettle();
    expect(title('Gêneros'), findsOneWidget);
    expect(find.text('hard rock'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
