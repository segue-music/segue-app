import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/favorites.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album_page.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/favorite_button.dart';
import 'package:segue/ui/favorite_songs_page.dart';
import 'package:segue/ui/now_playing_bar.dart';
import 'package:segue/ui/player_page.dart';
import 'package:segue/ui/playlists_view.dart';

import 'fakes.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A server whose starred songs and albums change as the app asks, at first the song s1 and the album a1, of the
/// library's two albums, a1 and a2, the first with the songs s1 and s2, of 3:35 each. While [held], it answers no change; with
/// [refuses], it refuses them; [down], it answers nothing.
class Starred {
  final songs = {'s1'};
  final albums = {'a1'};
  final changes = <String>[];
  Completer<void>? held;
  bool refuses = false;
  bool down = false;

  Future<http.Response> answer(http.Request request) async {
    final endpoint = request.url.pathSegments.last;
    final params = request.url.queryParameters;

    if (down) {
      return http.Response('', 502);
    }

    switch (endpoint) {
      case 'getStarred2.view':
        return subsonic({
          'starred2': {
            'album': [
              for (final id in albums) {'id': id, 'name': 'Album $id'},
            ],
            'song': [
              for (final id in songs) {'id': id, 'title': 'Song $id'},
            ],
          },
        });
      case 'getAlbum.view':
        return subsonic({
          'album': {
            'id': 'a1',
            'name': 'Album a1',
            'artist': 'Aerosmith',
            'artistId': 'ar1',
            'song': [
              for (final id in ['s1', 's2'])
                {'id': id, 'title': 'Song $id', 'artist': 'Aerosmith', 'artistId': 'ar1', 'duration': 215},
            ],
          },
        });
      case 'getAlbumList2.view':
        return subsonic({
          'albumList2': {
            'album': [
              for (final id in ['a1', 'a2']) {'id': id, 'name': 'Album $id'},
            ],
          },
        });
      case 'getPlaylists.view':
        return subsonic({'playlists': <String, Object?>{}});
      case 'star.view' || 'unstar.view':
        await held?.future;
        changes.add('$endpoint ${params['id'] ?? params['albumId']}');

        if (refuses) {
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'failed',
                'error': {'code': 50, 'message': 'not allowed'},
              },
            }),
            200,
          );
        }

        final ids = params.containsKey('albumId') ? albums : songs;
        final id = params['id'] ?? params['albumId']!;
        endpoint == 'star.view' ? ids.add(id) : ids.remove(id);
        return subsonic({});
      default:
        return http.Response('', 404);
    }
  }
}

Favorites favoritesOf(Starred server) => Favorites(
  SubsonicApi(
    Uri.parse('https://music.test'),
    const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
    client: MockClient(server.answer),
  ),
);

void main() {
  test('none until they come; then the server\'s', () async {
    final favorites = favoritesOf(Starred());
    expect(favorites.loaded, isFalse);
    expect(favorites.contains(FavoriteKind.song, 's1'), isFalse);
    await favorites.load();
    expect(favorites.loaded, isTrue);
    expect(favorites.contains(FavoriteKind.song, 's1'), isTrue);
    expect(favorites.contains(FavoriteKind.album, 'a1'), isTrue);
    expect(favorites.contains(FavoriteKind.album, 's1'), isFalse, reason: 'a song\'s id isn\'t an album\'s');
    expect([for (final song in favorites.songs) song.id], ['s1']);
  });

  test('a change shows at once, goes to the server, and they load again once none is left', () async {
    final server = Starred()..held = Completer();
    final favorites = favoritesOf(server);
    await favorites.load();
    var told = 0;
    favorites.addListener(() => told++);
    final starring = favorites.set(FavoriteKind.song, 's2', favorite: true);
    final unstarring = favorites.set(FavoriteKind.song, 's1', favorite: false);
    expect(favorites.contains(FavoriteKind.song, 's2'), isTrue);
    expect(favorites.contains(FavoriteKind.song, 's1'), isFalse);
    expect(favorites.songs, isEmpty, reason: 'the one no longer a favorite gone, the new one not come yet');
    expect(told, 2);

    server.held!.complete();
    await (starring, unstarring).wait;
    expect(server.changes, ['star.view s2', 'unstar.view s1'], reason: 'in the order they came');
    await pumpEventQueue();
    expect([for (final song in favorites.songs) song.id], ['s2'], reason: 'loaded again');
  });

  test('a change the server refuses is undone, and its failure the caller\'s', () async {
    final server = Starred()..refuses = true;
    final favorites = favoritesOf(server);
    await favorites.load();
    final unstarring = favorites.set(FavoriteKind.album, 'a1', favorite: false);
    expect(favorites.contains(FavoriteKind.album, 'a1'), isFalse);
    await expectLater(unstarring, throwsA(anything));
    expect(favorites.contains(FavoriteKind.album, 'a1'), isTrue);
    expect([for (final album in favorites.albums) album.id], ['a1']);
  });

  test('a load that fails leaves them as they were', () async {
    final server = Starred();
    final favorites = favoritesOf(server);
    await favorites.load();
    server.down = true;
    await expectLater(favorites.load(), throwsA(anything));
    expect(favorites.loaded, isTrue);
    expect(favorites.contains(FavoriteKind.song, 's1'), isTrue);
  });

  group('in the app', () {
    late Starred server;
    late FakeEngine engine;
    late PlayerController player;

    setUp(() => server = Starred());

    /// [home] on a screen of [size], the favorites loaded, as the app's start loads them.
    Future<void> pump(WidgetTester tester, Widget home, {Size size = const Size(1000, 700)}) async {
      const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
      final api = SubsonicApi(Uri.parse('https://music.test'), credentials, client: MockClient(server.answer));
      engine = FakeEngine();
      player = PlayerController(engine, api);
      final services = Services(
        Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
        api,
        player,
        ConnectController(player: player),
      );
      await services.favorites.load();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('pt')],
          builder: (context, child) => ServicesScope(services: services, child: child!),
          home: home,
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder heart({required bool filled}) =>
        find.byTooltip(filled ? 'Remover dos favoritos' : 'Adicionar aos favoritos');

    /// The heart of the album's page, beside its play button, rather than one of its songs'.
    Finder albumHeart({required bool filled}) => find.descendant(
      of: find.byType(FavoriteButton),
      matching: heart(filled: filled),
    );

    /// The heart on the song [title]'s line, which is there while the song is a favorite.
    Finder songHeart(String title) =>
        find.descendant(of: find.widgetWithText(ListTile, title), matching: heart(filled: true));

    /// The song [title]'s menu: its button.
    Finder songMenu(String title) =>
        find.descendant(of: find.widgetWithText(ListTile, title), matching: find.byTooltip('Mais opções'));

    testWidgets('on an album\'s page, the heart beside its play button is filled while it is a favorite, and a tap '
        'makes it one, or no longer one', (tester) async {
      await pump(tester, const AlbumPage(Album(id: 'a1', name: 'Album a1')));
      expect(albumHeart(filled: true), findsOneWidget);
      final play = tester.getRect(find.byTooltip('Tocar o álbum'));
      expect(tester.getRect(albumHeart(filled: true)).center.dy, moreOrLessEquals(play.center.dy, epsilon: 1));

      await tester.tap(albumHeart(filled: true));
      await tester.pump();
      expect(albumHeart(filled: false), findsOneWidget, reason: 'at once');
      await tester.pumpAndSettle();
      expect(server.changes, ['unstar.view a1']);
      expect(server.albums, isEmpty);

      await tester.tap(albumHeart(filled: false));
      await tester.pumpAndSettle();
      expect(server.changes.last, 'star.view a1');
      expect(albumHeart(filled: true), findsOneWidget);
    });

    testWidgets('a song\'s menu makes it one of the favorites, and then no longer one', (tester) async {
      await pump(tester, const AlbumPage(Album(id: 'a1', name: 'Album a1')));
      await tester.tap(songMenu('Song s2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar aos favoritos'));
      await tester.pumpAndSettle();
      expect(server.changes, ['star.view s2']);

      await tester.tap(songMenu('Song s2'));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar aos favoritos'), findsNothing);
      await tester.tap(find.text('Remover dos favoritos'));
      await tester.pumpAndSettle();
      expect(server.changes.last, 'unstar.view s2');
    });

    for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
      testWidgets(
        'on $screen, a favorite song\'s line has a heart, filled, before its duration, which makes it no longer '
        'one; a song that isn\'t has none, until its menu makes it one',
        (tester) async {
          await pump(
            tester,
            const AlbumPage(Album(id: 'a1', name: 'Album a1')),
            size: size,
          );
          final (s1, s2) = (find.widgetWithText(ListTile, 'Song s1'), find.widgetWithText(ListTile, 'Song s2'));
          await tester.ensureVisible(s2);
          await tester.pumpAndSettle();
          expect(songHeart('Song s1'), findsOneWidget);
          expect(songHeart('Song s2'), findsNothing);
          final duration = tester.getRect(find.descendant(of: s1, matching: find.text('3:35')));
          expect(tester.getRect(songHeart('Song s1')).right, lessThanOrEqualTo(duration.left));
          expect(
            tester.getRect(find.descendant(of: s2, matching: find.text('3:35'))).right,
            duration.right,
            reason: 'the durations lined up, with a heart or without',
          );

          await tester.tap(songHeart('Song s1'));
          await tester.pump();
          expect(songHeart('Song s1'), findsNothing, reason: 'at once');
          await tester.pumpAndSettle();
          expect(server.changes, ['unstar.view s1']);

          await tester.tap(songMenu('Song s2'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Adicionar aos favoritos'));
          await tester.pumpAndSettle();
          expect(songHeart('Song s2'), findsOneWidget);
          expect(server.changes.last, 'star.view s2');
        },
      );
    }

    testWidgets('a change the server refuses says so, and the heart goes back', (tester) async {
      await pump(tester, const AlbumPage(Album(id: 'a1', name: 'Album a1')));
      server.refuses = true;
      await tester.tap(albumHeart(filled: true));
      await tester.pumpAndSettle();
      expect(find.textContaining('Não consegui alterar os favoritos'), findsOneWidget);
      expect(albumHeart(filled: true), findsOneWidget);
    });

    testWidgets('the favorite songs come first among the playlists, with how many they are, and open their page, which '
        'plays them and follows them', (tester) async {
      server.songs.add('s2');
      await pump(tester, const Scaffold(body: PlaylistsView()));
      final favorites = find.widgetWithText(ListTile, 'Músicas favoritas');
      expect(tester.getRect(favorites).top, greaterThan(tester.getRect(find.text('Nova playlist')).top));
      expect(find.descendant(of: favorites, matching: find.text('2 faixas')), findsOneWidget);

      await tester.tap(favorites);
      await tester.pumpAndSettle();
      expect(find.byType(FavoriteSongsPage), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Song s1'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Song s2'));
      await tester.pumpAndSettle();
      expect([for (final track in engine.tracks) track.queryParameters['id']], unorderedEquals(['s1', 's2']));
      expect(player.queue[player.index].id, 's2', reason: 'from the one picked');

      await tester.tap(songMenu('Song s1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover dos favoritos'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Song s1'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Song s2'), findsOneWidget);
    });

    testWidgets('with none, the favorite songs\' page says how to add one', (tester) async {
      server.songs.clear();
      await pump(tester, const FavoriteSongsPage());
      expect(find.textContaining('Nenhuma música favorita ainda'), findsOneWidget);
    });

    testWidgets('the albums tab\'s "Favoritos" shows the favorite albums alone, as they change', (tester) async {
      var shown = AlbumsShown.library;
      await pump(
        tester,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AlbumsView(
              shown: shown,
              onOrder: (_) => setState(() => shown = AlbumsShown.library),
              onShown: (picked) => setState(() => shown = picked),
            ),
          ),
        ),
      );
      expect(find.text('Album a2'), findsOneWidget);
      // After the orders', where the chips' line scrolls sideways.
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Favoritos'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Favoritos'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Favoritos')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Nome')).selected, isFalse);
      expect(find.text('Album a1'), findsOneWidget);
      expect(find.text('Album a2'), findsNothing);
    });

    testWidgets('on a wide screen the player bar has the heart of the song that plays', (tester) async {
      await pump(tester, const Scaffold(body: SizedBox.expand(), bottomNavigationBar: NowPlayingBar()));
      await player.playQueue(const [Song(id: 's1', title: 'Song s1')], play: false);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(NowPlayingBar), matching: heart(filled: true)), findsOneWidget);
    });

    testWidgets('on a phone the full-screen player has it at the end of the title\'s line, which stays in the middle', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(body: SizedBox.expand(), bottomNavigationBar: NowPlayingBar()),
        size: const Size(360, 640),
      );
      await player.playQueue(const [Song(id: 's2', title: 'Song s2')], play: false);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(NowPlayingBar), matching: heart(filled: false)), findsNothing);
      await tester.tap(find.byType(NowPlayingBar));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      final title = tester.getRect(find.descendant(of: find.byType(PlayerPage), matching: find.text('Song s2')).first);
      final button = tester.getRect(heart(filled: false));
      expect(button.center.dy, moreOrLessEquals(title.center.dy, epsilon: 1), reason: 'on the title\'s line');
      expect(button.left, greaterThanOrEqualTo(title.right - 1), reason: 'after the title');
      expect(title.center.dx, moreOrLessEquals(180, epsilon: 1), reason: 'the title in the middle');

      await tester.tap(heart(filled: false));
      await tester.pumpAndSettle();
      expect(server.changes, ['star.view s2']);
    });
  });
}
