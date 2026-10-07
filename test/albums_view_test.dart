import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album_page.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/artist_page.dart';
import 'package:segue/ui/cover.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/now_playing_bar.dart';

import 'fakes.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The home page over a library of [count] albums, "Album 000" on, each by an artist of its own,
/// "Artist 000" (id "ar000") on, opened on the albums tab. By name they come in that order; latest
/// added or released, the other way around; and none has played. An artist's page has one album,
/// "Only by" their id. The server fails the page at [failing] once. The screen is [size]. Returns the album lists
/// the tab asks for: their type, offset and size.
Future<List<String>> pumpAlbums(
  WidgetTester tester, {
  required int count,
  int? failing,
  Size size = const Size(1000, 700),
}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final names = [for (var i = 0; i < count; i++) 'Album ${'$i'.padLeft(3, '0')}'];
  final asked = <String>[];
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      final query = request.url.queryParameters;

      if (request.url.path.endsWith('getArtist.view')) {
        final id = query['id']!;
        return subsonic({
          'artist': {
            'id': id,
            'name': 'Artist ${id.substring(2)}',
            'album': [
              {'id': 'only-$id', 'name': 'Only by $id'},
            ],
          },
        });
      }

      if (!request.url.path.endsWith('getAlbumList2.view')) {
        return http.Response('', 404);
      }

      asked.add('${query['type']} ${query['offset']} ${query['size']}');
      final offset = int.parse(query['offset']!);

      if (offset == failing && query['type'] == 'alphabeticalByName') {
        failing = null;
        return http.Response('', 500);
      }

      final inOrder = switch (query['type']) {
        'alphabeticalByName' => names,
        'newest' || 'byYear' => names.reversed,
        _ => const <String>[],
      };
      final page = inOrder.skip(offset).take(int.parse(query['size']!));
      return subsonic({
        'albumList2': {
          'album': [
            for (final name in page)
              {
                'id': name,
                'name': name,
                'artist': name.replaceFirst('Album', 'Artist'),
                'artistId': name.replaceFirst('Album ', 'ar'),
              },
          ],
        },
      });
    }),
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
  asked.clear(); // the home's rows
  // The side rail's, or on a phone the bottom bar's.
  await tester.tap(find.byTooltip('Álbuns'));
  await tester.pumpAndSettle();
  return asked;
}

/// The chip of the albums tab that picks the order [label] names.
Finder order(String label) => find.widgetWithText(ChoiceChip, label);

/// Whether [label]'s order is the one picked.
bool picked(WidgetTester tester, String label) => tester.widget<ChoiceChip>(order(label)).selected;

/// Scrolls the albums down as far as they go, [times] times.
Future<void> scrollToEnd(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.drag(find.byType(AlbumGrid), const Offset(0, -100000));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('the albums tab lists them by name, or as picked: the latest released, the most played or the latest '
      'added', (tester) async {
    final asked = await pumpAlbums(tester, count: 3);
    expect(picked(tester, 'Nome'), isTrue);
    expect(picked(tester, 'Adicionados recentemente'), isFalse);

    await tester.tap(order('Adicionados recentemente'));
    await tester.pumpAndSettle();
    expect(asked.last, 'newest 0 200');
    expect(picked(tester, 'Adicionados recentemente'), isTrue);
    expect(picked(tester, 'Nome'), isFalse);
    expect(tester.getRect(find.text('Album 001')).left, greaterThan(tester.getRect(find.text('Album 002')).left));

    await tester.tap(order('Lançamentos'));
    await tester.pumpAndSettle();
    expect(asked.last, 'byYear 0 200');

    await tester.tap(order('Mais tocados'));
    await tester.pumpAndSettle();
    expect(asked.last, 'frequent 0 200');
    expect(find.text('Os álbuns que você mais ouvir aparecem aqui.'), findsOneWidget, reason: 'nothing has played');

    await tester.tap(order('Nome'));
    await tester.pumpAndSettle();
    expect(asked.last, 'alphabeticalByName 0 200');
    expect(tester.getRect(find.text('Album 002')).left, greaterThan(tester.getRect(find.text('Album 001')).left));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the order chips start at the left, lined up with the albums', (tester) async {
    await pumpAlbums(tester, count: 3);
    expect(tester.getRect(order('Nome')).left, tester.getRect(find.text('Album 000')).left);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an album has room inside, around its cover, where the tint shows; its cover is 16 from the next', (
    tester,
  ) async {
    await pumpAlbums(tester, count: 3);
    Rect tile(String name) => tester.getRect(find.ancestor(of: find.text(name), matching: find.byType(AlbumTile)));
    Rect cover(String name) => tester.getRect(
      find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(AlbumTile)),
        matching: find.byType(Cover),
      ),
    );

    final (album, next) = ('Album 000', 'Album 001');
    expect(cover(album).left - tile(album).left, 8);
    expect(cover(album).top - tile(album).top, 8);
    expect(tile(album).right - cover(album).right, 8);
    expect(cover(next).left - cover(album).right, moreOrLessEquals(16));
    expect(cover(album).left, moreOrLessEquals(tester.getRect(order('Nome')).left), reason: 'lined up with the chips');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the order chips keep some room between them and the albums, also as these scroll', (tester) async {
    await pumpAlbums(tester, count: 300);
    double gap() => tester.getRect(find.byType(AlbumGrid)).top - tester.getRect(order('Nome')).bottom;

    expect(gap(), greaterThanOrEqualTo(12));
    await tester.drag(find.byType(AlbumGrid), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(gap(), greaterThanOrEqualTo(12), reason: 'the grid\'s own room above scrolls away with it');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an empty library says so', (tester) async {
    await pumpAlbums(tester, count: 0);
    expect(find.text('A biblioteca está vazia.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the albums tab lists them by name', (tester) async {
    final asked = await pumpAlbums(tester, count: 3);
    expect(asked, ['alphabeticalByName 0 200']);
    final first = tester.getRect(find.text('Album 000'));
    final second = tester.getRect(find.text('Album 001'));
    expect(second.left, greaterThan(first.left));
    expect(second.top, first.top);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('an album\'s artist opens their page, and the rest of the album opens it', (tester) async {
    await pumpAlbums(tester, count: 3);
    expect(find.byTooltip('Abrir o artista'), findsNWidgets(3));
    await tester.tap(find.text('Artist 001'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.text('Only by ar001'), findsOneWidget, reason: 'the page of the album\'s artist, by their id');
    expect(find.byTooltip('Abrir o artista'), findsNothing, reason: 'their albums show the year, not them again');
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Album 001'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.byType(ArtistPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scrolling down brings the next albums, until there are no more', (tester) async {
    final asked = await pumpAlbums(tester, count: 450);
    expect(find.text('Album 449'), findsNothing);
    await scrollToEnd(tester, times: 4);
    expect(find.text('Album 449'), findsOneWidget);
    expect(asked, ['alphabeticalByName 0 200', 'alphabeticalByName 200 200', 'alphabeticalByName 400 200']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the albums go on behind the bars at the bottom, showing through the gap between them, and '
      'end clear of them', (tester) async {
    await pumpAlbums(tester, count: 30, size: const Size(360, 640));
    final player = ServicesScope.of(tester.element(find.byType(HomePage))).player;
    await player.playQueue(const [Song(id: 's1', title: 'Dream On')]);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(AlbumGrid)).bottom, 640);

    await scrollToEnd(tester);
    final last = find.ancestor(of: find.text('Album 029'), matching: find.byType(AlbumTile));
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(tester.getRect(find.byType(NowPlayingBar)).top));
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('a page the server fails says so at the end, and is asked for again from there', (tester) async {
    final asked = await pumpAlbums(tester, count: 300, failing: 200);
    await scrollToEnd(tester, times: 2); // the message comes under where the first stopped
    expect(find.textContaining('Não consegui listar mais álbuns'), findsOneWidget);
    expect(find.text('Album 199'), findsOneWidget);
    expect(asked, hasLength(2), reason: 'not asked for again by itself');

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);
    expect(find.text('Album 299'), findsOneWidget);
    expect(find.textContaining('Não consegui'), findsNothing);
    expect(asked.last, 'alphabeticalByName 200 200');
    await tester.pumpWidget(const SizedBox());
  });
}
