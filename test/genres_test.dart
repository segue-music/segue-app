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
/// among the most played (with [played]), with one of hard rock, played less; Blues has one, never
/// played. [asked] gets the queries of the album lists asked for.
http.Response server(http.Request request, List<Map<String, String>> asked, {bool played = true}) {
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
Future<List<Map<String, String>>> pumpHome(WidgetTester tester, Size size, {bool played = true}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final asked = <Map<String, String>>[];
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server(request, asked, played: played)),
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

/// A genre in the list of them all.
Finder tile(String name) => find.widgetWithText(ListTile, name);

/// A genre among the most listened to.
Finder button(String name) => find.widgetWithText(FilledButton, name);

void main() {
  testWidgets('the side rail goes to the genres, by name, each with its number of albums, and a genre shows its '
      'albums', (tester) async {
    final asked = await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();
    expect(title('Gêneros'), findsOneWidget);

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

  testWidgets('the genres start with those the user listens to most, the most first, each opening its page', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    await tester.tap(find.byTooltip('Gêneros'));
    await tester.pumpAndSettle();

    final heading = tester.getRect(find.text('Mais ouvidos'));
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
    expect(find.text('Mais ouvidos'), findsNothing);
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

    final mostPlayed = tester.getRect(find.text('Mais ouvidos'));
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
    await tester.tap(tile('Blues'));
    await tester.pumpAndSettle();
    expect(find.text('Honky Tonk Blues'), findsOneWidget);
    expect(find.text('Mais ouvidos'), findsNothing);
    expect(find.text('Álbuns'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the genres are in the bar at the bottom', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Gêneros')));
    await tester.pumpAndSettle();
    expect(title('Gêneros'), findsOneWidget);
    expect(tile('hard rock'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
