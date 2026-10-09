import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:segue/ui/playlist_menu.dart';
import 'package:segue/ui/playlist_page.dart';
import 'package:segue/ui/playlists_view.dart';
import 'package:segue/ui/themed_icon.dart';

import 'fakes.dart';
import 'side_rail.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The songs of the library: two of an album, Toys in the Attic, and one of another.
const songs = {
  's1': {
    'id': 's1',
    'title': 'Walk This Way',
    'artist': 'Aerosmith',
    'artistId': 'ar1',
    'album': 'Toys in the Attic',
    'albumId': 'a1',
    'duration': 220,
  },
  's2': {
    'id': 's2',
    'title': 'Sweet Emotion',
    'artist': 'Aerosmith',
    'artistId': 'ar1',
    'album': 'Toys in the Attic',
    'albumId': 'a1',
    'duration': 274,
  },
  's9': {
    'id': 's9',
    'title': 'Dream Police',
    'artist': 'Cheap Trick',
    'artistId': 'ar2',
    'album': 'Dream Police',
    'albumId': 'a9',
    'duration': 226,
  },
};

/// A playlist on the [Library]'s server.
class ServerPlaylist {
  ServerPlaylist(this.name, this.songs, {this.owner = 'a'});

  String name;
  final List<String> songs;

  /// Its user's name: the app's ('a'), or another's.
  final String owner;
}

/// A Navidrome-like server whose playlists change as the app asks. At first, by id: Road trip (p1), the user's, with
/// Sweet Emotion and Dream Police; chill (p2), another user's, read-only; and Empty (p3), the user's. [playlists] false,
/// none. [asked] gets the endpoints asked for.
class Library {
  Library({bool playlists = true}) {
    if (playlists) {
      this.playlists.addAll({
        'p1': ServerPlaylist('Road trip', ['s2', 's9']),
        'p2': ServerPlaylist('chill', ['s1', 's2', 's9'], owner: 'b'),
        'p3': ServerPlaylist('Empty', []),
      });
    }
  }

  final playlists = <String, ServerPlaylist>{};
  final asked = <String>[];

  /// Whether it refuses to change any playlist.
  bool refuses = false;

  /// The playlist's songs' ids, by its name.
  List<String> songsOf(String name) => playlists.values.firstWhere((playlist) => playlist.name == name).songs;

  Map<String, Object?> _playlist(String id, {bool withSongs = false}) {
    final playlist = playlists[id]!;
    return {
      'id': id,
      'name': playlist.name,
      'songCount': playlist.songs.length,
      'owner': playlist.owner,
      'readonly': playlist.owner != 'a',
      if (withSongs) 'entry': [for (final song in playlist.songs) songs[song]],
    };
  }

  http.Response answer(http.Request request) {
    final endpoint = request.url.pathSegments.last;
    final params = request.method == 'POST'
        ? Uri(query: request.body).queryParametersAll
        : request.url.queryParametersAll;
    String? param(String name) => params[name]?.single;
    asked.add(endpoint);

    if (refuses && const {'createPlaylist.view', 'updatePlaylist.view', 'deletePlaylist.view'}.contains(endpoint)) {
      return subsonic({
        'status': 'failed',
        'error': {'code': 50, 'message': 'not allowed'},
      });
    }

    switch (endpoint) {
      case 'getPlaylists.view':
        return subsonic({
          'playlists': {
            'playlist': [for (final id in playlists.keys) _playlist(id)],
          },
        });
      case 'getPlaylist.view':
        return subsonic({'playlist': _playlist(param('id')!, withSongs: true)});
      case 'createPlaylist.view':
        final id = param('playlistId') ?? 'p${playlists.length + 1}';
        final ids = params['songId'] ?? const [];
        playlists.update(
          id,
          (playlist) => playlist
            ..songs.clear()
            ..songs.addAll(ids),
          ifAbsent: () => ServerPlaylist(param('name')!, [...ids]),
        );
        return subsonic({'playlist': _playlist(id, withSongs: true)});
      case 'updatePlaylist.view':
        final playlist = playlists[param('playlistId')]!;
        final removed = [for (final index in params['songIndexToRemove'] ?? const <String>[]) int.parse(index)]..sort();

        for (final index in removed.reversed) {
          playlist.songs.removeAt(index);
        }

        playlist.songs.addAll(params['songIdToAdd'] ?? const []);
        playlist.name = param('name') ?? playlist.name;
        return subsonic({});
      case 'deletePlaylist.view':
        playlists.remove(param('id'));
        return subsonic({});
      case 'getAlbumList2.view':
        return subsonic({
          'albumList2': {
            'album': [
              {'id': 'a1', 'name': 'Toys in the Attic', 'artist': 'Aerosmith', 'artistId': 'ar1'},
            ],
          },
        });
      case 'getAlbum.view':
        return subsonic({
          'album': {
            'id': 'a1',
            'name': 'Toys in the Attic',
            'artist': 'Aerosmith',
            'artistId': 'ar1',
            'song': [songs['s1'], songs['s2']],
          },
        });
      default:
        return http.Response('', 404);
    }
  }
}

/// The home page on a screen of [size], over the [library]'s server; returns its player.
Future<PlayerController> pumpHome(WidgetTester tester, Size size, {Library? library}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final server = library ?? Library();
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server.answer(request)),
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

/// Goes to the playlists, on a phone ([size] narrow) by the bar at the bottom.
Future<void> openPlaylists(WidgetTester tester, {Size size = const Size(1000, 700)}) async {
  await tester.tap(
    size.width < 600
        ? find.descendant(of: find.byType(NavigationBar), matching: find.text('Playlists'))
        : find.byTooltip('Playlists'),
  );
  await tester.pumpAndSettle();
}

/// Opens the playlist named [name], from the playlists.
Future<void> openPlaylist(WidgetTester tester, String name, {Size size = const Size(1000, 700)}) async {
  await openPlaylists(tester, size: size);
  await tester.tap(tile(name));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The dialog's field, where a playlist's name is typed.
Finder get nameField => find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

/// The song [title]'s menu: its button.
Finder songMenu(String title) => find.descendant(of: tile(title), matching: find.byTooltip('Mais opções'));

/// A menu's item, or a dialog's option or button, that says [text]: over the page, last.
Finder item(String text) => find.text(text).last;

/// The titles of the songs on the playlist's page, from the top.
List<String> titles(WidgetTester tester) {
  final titles = {for (final song in songs.values) song['title']! as String};
  final tiles = [
    for (final element in find.descendant(of: find.byType(PlaylistPage), matching: find.byType(ListTile)).evaluate())
      if (((element.widget as ListTile).title as Text?)?.data case final title? when titles.contains(title))
        (title, (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (title, _) in tiles) title];
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
    expect(find.text('3 faixas'), findsOneWidget);
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
    await pumpHome(tester, const Size(1000, 700), library: Library(playlists: false));
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
      final library = Library();
      final asked = library.asked;
      await pumpHome(tester, size, library: library);
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

  testWidgets('"Nova playlist", over the list, makes one named in a dialog, which then shows by name', (tester) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylists(tester);
    expect(tester.getRect(tile('Nova playlist')).bottom, lessThanOrEqualTo(tester.getRect(tile('chill')).top));

    await tap(tester, tile('Nova playlist'));
    final create = find.widgetWithText(TextButton, 'Criar');
    expect(tester.widget<TextButton>(create).onPressed, isNull, reason: 'not without a name');
    await tester.enterText(nameField, '  Bus  ');
    await tester.pump();
    await tap(tester, create);
    expect(library.songsOf('Bus'), isEmpty);
    expect(tester.getRect(tile('Bus')).bottom, lessThanOrEqualTo(tester.getRect(tile('chill')).top), reason: 'by name');
    expect(find.descendant(of: tile('Bus'), matching: find.text('0 faixas')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song\'s menu adds it at the end of a playlist the user can change, picked in a dialog', (
    tester,
  ) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylist(tester, 'Road trip');
    // From an album's page, over the playlist's, which shows it once back.
    await tap(tester, find.byTooltip('Início').first);
    await tap(tester, find.text('Toys in the Attic').first);
    await tap(tester, songMenu('Walk This Way'));
    await tap(tester, item('Adicionar à playlist'));
    expect(find.text('Nova playlist'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('chill'), findsNothing, reason: 'another user\'s');

    await tap(tester, item('Road trip'));
    expect(find.text('Adicionada a Road trip'), findsOneWidget);
    expect(library.songsOf('Road trip'), ['s2', 's9', 's1']);

    await openPlaylist(tester, 'Road trip');
    expect(titles(tester), ['Sweet Emotion', 'Dream Police', 'Walk This Way']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the album\'s button adds all its songs, also to a new playlist, named in a dialog', (tester) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await tap(tester, find.text('Toys in the Attic').first);
    await tap(tester, find.byTooltip('Adicionar'));
    await tap(tester, item('Adicionar à playlist'));
    await tap(tester, item('Nova playlist'));
    await tester.enterText(nameField, 'Aerosmith');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('2 faixas adicionadas a Aerosmith'), findsOneWidget);
    expect(library.songsOf('Aerosmith'), ['s1', 's2']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the menu key, or Shift+F10, on a song opens its menu, whose button takes no focus', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await tap(tester, find.text('Toys in the Attic').first);
    final menu = find.ancestor(of: songMenu('Walk This Way'), matching: find.byType(IconButton));
    expect(
      Focus.of(tester.element(find.descendant(of: menu, matching: find.byType(ThemedIcon)))).canRequestFocus,
      isFalse,
    );

    Focus.of(tester.element(find.text('Walk This Way'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Adicionar à playlist'), findsOneWidget);
    expect(find.text('Remover da playlist'), findsNothing, reason: 'an album\'s song');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Adicionar à playlist'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Adicionar à playlist'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a playlist\'s page, a song\'s menu takes it out', (tester) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylist(tester, 'Road trip');
    await tap(tester, songMenu('Sweet Emotion'));
    await tap(tester, item('Remover da playlist'));
    expect(titles(tester), ['Dream Police']);
    expect(find.text('1 faixa, 3 min'), findsOneWidget);
    expect(library.songsOf('Road trip'), ['s9']);

    await tap(tester, find.byTooltip('Voltar'));
    expect(find.descendant(of: tile('Road trip'), matching: find.text('1 faixa')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with the mouse, a song dragged up the playlist moves there', (tester) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylist(tester, 'Road trip');
    final height = tester.getSize(tile('Dream Police')).height;
    final gesture = await tester.startGesture(tester.getCenter(tile('Dream Police')), kind: PointerDeviceKind.mouse);

    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, -height / 4));
      await tester.pump(const Duration(milliseconds: 50));
    }

    await gesture.up();
    await tester.pumpAndSettle();
    expect(titles(tester), ['Dream Police', 'Sweet Emotion']);
    expect(library.songsOf('Road trip'), ['s9', 's2']);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on a phone, a song held a moment, then dragged, moves; dragged at once, the list scrolls', (
    tester,
  ) async {
    final library = Library();
    await pumpHome(tester, const Size(360, 640), library: library);
    await openPlaylist(tester, 'Road trip', size: const Size(360, 640));
    final height = tester.getSize(tile('Dream Police')).height;

    await tester.drag(tile('Dream Police'), Offset(0, -height * 1.5));
    await tester.pumpAndSettle();
    expect(titles(tester), ['Sweet Emotion', 'Dream Police'], reason: 'not held');

    final gesture = await tester.startGesture(tester.getCenter(tile('Dream Police')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));

    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, -height / 4));
      await tester.pump(const Duration(milliseconds: 50));
    }

    await gesture.up();
    await tester.pumpAndSettle();
    expect(titles(tester), ['Dream Police', 'Sweet Emotion']);
    expect(library.songsOf('Road trip'), ['s9', 's2']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song\'s artist is a link', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await openPlaylist(tester, 'Road trip');
    expect(find.descendant(of: tile('Dream Police'), matching: find.byTooltip('Abrir o artista')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a song\'s artist is plain text: only the player links them', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    await openPlaylist(tester, 'Road trip', size: const Size(360, 640));
    expect(find.descendant(of: tile('Dream Police'), matching: find.text('Cheap Trick')), findsOneWidget);
    expect(find.descendant(of: tile('Dream Police'), matching: find.byTooltip('Abrir o artista')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the playlist\'s menu lines up with the songs\' menus, and its play button\'s edge is 16 from the '
    'screen\'s, also on a touch screen, whose buttons have room around them',
    variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.linux}),
    (tester) async {
      await pumpHome(tester, const Size(360, 640));
      await openPlaylist(tester, 'Road trip', size: const Size(360, 640));
      final menus = find.byTooltip('Mais opções');
      expect(menus, findsNWidgets(3), reason: 'the playlist\'s and its two songs\'');

      for (var i = 1; i < 3; i++) {
        expect(tester.getCenter(menus.at(i)).dx, moreOrLessEquals(tester.getCenter(menus.first).dx), reason: '$i');
      }

      expect(tester.getRect(find.byTooltip('Tocar a playlist')).right, 360 - 16);
      expect(
        tester.getRect(find.byTooltip('Tocar a playlist')).left,
        greaterThan(tester.getRect(menus.first).right),
        reason: 'after the menu, apart',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the playlist\'s menu renames it, in a dialog with its name', (tester) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylist(tester, 'Road trip');
    // The playlist's, above the songs'.
    await tap(tester, find.byTooltip('Mais opções').first);
    await tap(tester, item('Renomear a playlist'));
    expect(find.descendant(of: nameField, matching: find.text('Road trip')), findsOneWidget);
    final rename = find.widgetWithText(TextButton, 'Renomear');
    expect(tester.widget<TextButton>(rename).onPressed, isNull, reason: 'the same name');

    await tester.enterText(nameField, 'Night drive');
    await tester.pump();
    await tap(tester, rename);
    expect(find.descendant(of: find.byType(PlaylistPage), matching: find.text('Night drive')), findsOneWidget);
    expect(library.playlists['p1']!.name, 'Night drive');

    await tap(tester, find.byTooltip('Voltar'));
    expect(tile('Night drive'), findsOneWidget);
    expect(tile('Road trip'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the playlist\'s menu deletes it, once asked, and its page closes', (tester) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylist(tester, 'Road trip');
    await tap(tester, find.byTooltip('Mais opções').first);
    await tap(tester, item('Excluir a playlist'));
    expect(find.text('Excluir “Road trip”?'), findsOneWidget);

    await tap(tester, item('Cancelar'));
    expect(library.playlists, contains('p1'));

    await tap(tester, find.byTooltip('Mais opções').first);
    await tap(tester, item('Excluir a playlist'));
    await tap(tester, item('Excluir'));
    expect(library.playlists, isNot(contains('p1')));
    expect(find.byType(PlaylistPage), findsNothing);
    expect(tile('Road trip'), findsNothing);
    expect(tile('Empty'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('another user\'s playlist\'s menu only plays it next or adds it to the queue, and its songs neither come '
      'out nor move', (tester) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylist(tester, 'chill');
    final page = find.byType(PlaylistPage);
    expect(
      find.descendant(of: page, matching: find.byTooltip('Mais opções')),
      findsNWidgets(4),
      reason: 'the playlist\'s and the songs\'',
    );
    expect(find.descendant(of: page, matching: find.byType(ReorderableDragStartListener)), findsNothing);

    await tap(tester, find.byTooltip('Mais opções').first);
    expect(find.text('Tocar a seguir'), findsOneWidget);
    expect(find.text('Adicionar à fila'), findsOneWidget);
    expect(find.text('Renomear a playlist'), findsNothing);
    expect(find.text('Excluir a playlist'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tap(tester, songMenu('Sweet Emotion'));
    expect(find.text('Adicionar à playlist'), findsOneWidget);
    expect(find.text('Remover da playlist'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a change the server refuses says so, and the page shows the playlist as the server has it', (
    tester,
  ) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylist(tester, 'Road trip');
    library.refuses = true;
    await tap(tester, songMenu('Sweet Emotion'));
    await tap(tester, item('Remover da playlist'));
    expect(find.text('Não consegui alterar a playlist: not allowed'), findsOneWidget);
    expect(titles(tester), ['Sweet Emotion', 'Dream Police']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('held, a playlist in the list opens its menu where it was pressed, which renames it', (tester) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylists(tester);
    // Nearer the left edge, which the menu grows away from.
    final pressed = tester.getCenter(tile('Road trip')) - const Offset(200, 0);
    await tester.longPressAt(pressed);
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byType(PopupMenuItem<PlaylistAction>).first);
    expect(menu.left, moreOrLessEquals(pressed.dx, epsilon: 1), reason: 'from where it was pressed');
    expect(menu.top, inInclusiveRange(pressed.dy, pressed.dy + 16));

    await tap(tester, item('Renomear a playlist'));
    await tester.enterText(nameField, 'Night drive');
    await tester.pump();
    await tap(tester, find.widgetWithText(TextButton, 'Renomear'));
    expect(library.playlists['p1']!.name, 'Night drive');
    expect(tile('Night drive'), findsOneWidget);
    expect(tile('Road trip'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('held with the mouse, a playlist in the list opens its menu, which deletes it, once asked', (
    tester,
  ) async {
    final library = Library();
    await pumpHome(tester, const Size(1000, 700), library: library);
    await openPlaylists(tester);
    await tester.longPress(tile('Road trip'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tap(tester, item('Excluir a playlist'));
    expect(find.text('Excluir “Road trip”?'), findsOneWidget);
    await tap(tester, item('Excluir'));
    expect(library.playlists, isNot(contains('p1')));
    expect(tile('Road trip'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('another user\'s playlist, held, opens a menu that only plays it next or adds it to the queue; an empty '
      'one of theirs would open none', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await openPlaylists(tester);
    await tester.longPress(tile('chill'));
    await tester.pumpAndSettle();
    expect(find.text('Tocar a seguir'), findsOneWidget);
    expect(find.text('Renomear a playlist'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // The user's empty one: only what changes it.
    await tester.longPress(tile('Empty'));
    await tester.pumpAndSettle();
    expect(find.text('Renomear a playlist'), findsOneWidget);
    expect(find.text('Tocar a seguir'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a playlist\'s menu plays its songs next, or adds them to the queue: on its page, as it shows them; in '
      'the list, as the server has them', (tester) async {
    final library = Library();
    final player = await pumpHome(tester, const Size(1000, 700), library: library);
    List<String> queue() => [for (final song in player.queue) song.id];

    await openPlaylist(tester, 'chill');
    await tap(tester, tile('Dream Police'));
    expect(queue(), ['s1', 's2', 's9']);
    expect(player.current?.id, 's9');

    await tap(tester, find.byTooltip('Mais opções').first);
    await tap(tester, item('Tocar a seguir'));
    expect(queue(), ['s1', 's2', 's9', 's1', 's2', 's9']);
    expect(player.current?.id, 's9', reason: 'the song that played plays on');
    expect(find.text('3 faixas vão tocar a seguir'), findsOneWidget);

    await tap(tester, find.byTooltip('Voltar'));
    await tester.longPress(tile('Road trip'));
    await tester.pumpAndSettle();
    await tap(tester, item('Adicionar à fila'));
    expect(queue(), ['s1', 's2', 's9', 's1', 's2', 's9', 's2', 's9']);
    expect(player.current?.id, 's9');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the menu key, or Shift+F10, on a playlist in the list opens its menu, over it', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    await openPlaylists(tester);
    Focus.of(tester.element(find.text('Road trip'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Excluir a playlist'), findsOneWidget);
    expect(
      tester.getRect(find.byType(PopupMenuItem<PlaylistAction>).first).top,
      inInclusiveRange(tester.getRect(tile('Road trip')).top, tester.getRect(tile('Road trip')).bottom),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Excluir a playlist'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
