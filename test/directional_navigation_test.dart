import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album/album_page.dart';
import 'package:segue/ui/album/albums_view.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/app/shortcuts.dart';
import 'package:segue/ui/app/television_screen.dart';
import 'package:segue/ui/home/home_chips.dart';
import 'package:segue/ui/home/home_view.dart';
import 'package:segue/ui/player/now_playing_bar.dart';
import 'package:segue/ui/player/player_page.dart';
import 'package:segue/ui/player/television_player.dart';
import 'package:segue/ui/widgets/text_link.dart';

import 'fakes.dart';

/// The player bar, with a song at 1:00, and the focus on its slider. A TV has none.
Future<PlayerController> pumpBarOnSlider(WidgetTester tester, {Widget body = const SizedBox.expand()}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((_) async => http.Response('', 404)),
  );
  final player = PlayerController(FakeEngine(), api);

  await player.playQueue(
    const [Song(id: 's1', title: 'Dream On', duration: Duration(minutes: 4))],
    position: const Duration(minutes: 1),
    play: false,
  );

  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  tester.view.physicalSize = const Size(1000, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: Scaffold(body: body, bottomNavigationBar: const NowPlayingBar()),
    ),
  );

  for (var i = 0; i < 100 && !sliderFocused(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }

  return player;
}

bool sliderFocused() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Slider>() != null;

/// The home page on a Full HD screen (1920 × 1080 pixels, two to each of its own), with more albums than fit, and a
/// song to play: a TV's, as Android gives it, or, with [television] false, a computer's, whose keyboard's arrows go
/// where the remote's would, and whose bar has the song, the grid building the next row past the bottom of the screen,
/// under it.
Future<PlayerController> pumpFullHdHome(
  WidgetTester tester, {
  bool television = true,
  bool followingAnotherDevice = false,
}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      // Any album opened: twenty tracks, more than fit.
      if (request.url.path.endsWith('getAlbum.view')) {
        final songs = [for (var i = 0; i < 20; i++) '{"id": "t$i", "title": "Track $i", "duration": 200}'].join(',');
        return http.Response(
          '{"subsonic-response": {"status": "ok", "album": {"id": "a0", "name": "Album 0", "song": [$songs]}}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (!request.url.path.endsWith('getAlbumList2.view')) {
        return http.Response('', 404);
      }

      final albums = [for (var i = 0; i < 30; i++) '{"id": "a$i", "name": "Album $i"}'].join(',');

      return http.Response(
        '{"subsonic-response": {"status": "ok", "albumList2": {"album": [$albums]}}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final player = PlayerController(FakeEngine(), api);

  await player.playQueue(const [Song(id: 's1', title: 'Dream On', duration: Duration(minutes: 4))], play: false);

  final client = followingAnotherDevice ? _anotherDevicePlaying() : null;
  final connect = ConnectController(player: player, client: client);

  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  client?.notifyListeners(); // as when the other device's state arrives

  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    connect,
  );
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(
        services: services,
        child: TelevisionScreen(
          enabled: television,
          child: TextFieldArrowShortcuts(child: child!),
        ),
      ),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pumpAndSettle();

  return player;
}

/// A hub client that sees another device play: the app follows it, and the bar gets the "Tocando
/// em" strip under it, which makes it taller.
SegueClient _anotherDevicePlaying() {
  final client = SegueClient(
    url: Uri.parse('ws://unused'),
    auth: const Auth.subsonic(username: 'a', token: 't', salt: 's'),
    device: const DeviceInfo(id: 'me', name: 'me', client: 'test', api: Api.subsonic, roles: [], capabilities: []),
  );
  client.devices['desktop'] = Device(
    info: const DeviceInfo(
      id: 'desktop',
      name: 'desktop',
      client: 'test',
      api: Api.subsonic,
      roles: [Role.player],
      capabilities: CommandAction.values,
    ),
    online: true,
    state: StampedState(
      status: PlaybackStatus.playing,
      positionMs: 30000,
      at: DateTime.now().millisecondsSinceEpoch,
      index: 0,
      repeat: Repeat.all,
      queue: const [QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', durationMs: 240000)],
    ),
  );

  return client;
}

bool inBar() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<NowPlayingBar>() != null;

/// The tooltip of what has the focus: a button's, or the song's ("Abrir o player").
String? focusedTip() {
  final context = FocusManager.instance.primaryFocus?.context;

  return context?.findAncestorWidgetOfExactType<IconButton>()?.tooltip ??
      context?.findAncestorWidgetOfExactType<Tooltip>()?.message;
}

/// Tabs until [there]: from the top of the screen, through the home's rows of 30 albums, before the bar, where there is
/// one.
Future<void> tabTo(WidgetTester tester, bool Function() there) async {
  for (var i = 0; i < 200 && !there(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }

  expect(there(), isTrue);
}

/// Like [tabTo], backwards: from the end of the screen, the bar, without passing through the grid,
/// which a Tab would scroll to line its rows up.
Future<void> shiftTabTo(WidgetTester tester, bool Function() there) async {
  for (var i = 0; i < 100 && !there(); i++) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  expect(there(), isTrue);
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('on a TV, the home has no player bar: the rail\'s first button opens the full-screen player, over '
      'everything, the remote on play, and back closes it, the focus back on the button', (tester) async {
    await pumpFullHdHome(tester);
    expect(find.byTooltip('Abrir o player'), findsNothing);
    expect(find.byTooltip('Aparelhos'), findsNothing);

    await shiftTabTo(tester, () => focusedTip() == 'Tocando agora');
    await press(tester, LogicalKeyboardKey.select);
    expect(tester.getRect(find.byType(PlayerPage)), const Rect.fromLTWH(0, 0, 960, 540));
    expect(focusedTip(), 'Tocar');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(focusedTip(), 'Tocando agora');
    await tester.pumpWidget(const SizedBox()); // stops the player's timers
  });

  testWidgets('on a TV, in the full-screen player\'s controls, down from play goes to the slider, which left and right '
      'move, down from it stays there, and up goes back to the buttons, and on to the song, without moving it', (
    tester,
  ) async {
    final player = await pumpFullHdHome(tester);

    await tester.tap(find.byTooltip('Tocando agora'));
    await tester.pumpAndSettle();
    expect(focusedTip(), 'Tocar');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(sliderFocused(), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);

    final moved = player.position;

    expect(moved, greaterThan(Duration.zero));

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(sliderFocused(), isTrue, reason: 'the controls are the floor');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedIn<TelevisionControls>() && !sliderFocused() && !focusedIn<TextLink>(), isTrue);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedIn<TextLink>(), isTrue, reason: 'up out of the controls, to the song');
    expect(player.position, moved);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, up from the end of the full-screen player\'s controls goes to the song, not to the page as a '
      'whole, which shows nothing for it', (tester) async {
    await pumpFullHdHome(tester);
    await tester.tap(find.byTooltip('Tocando agora'));
    await tester.pumpAndSettle();
    await pressUntil(tester, LogicalKeyboardKey.arrowRight, () => focusedTip() == 'Aparelhos');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedIn<TextLink>(), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('elsewhere, the arrows keep moving a focused slider, as they do on a computer', (tester) async {
    final player = await pumpBarOnSlider(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(player.position, lessThan(const Duration(minutes: 1)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a computer, in the bar, the arrow right goes along the buttons to the last one, and stops there', (
    tester,
  ) async {
    await pumpFullHdHome(tester, television: false);
    await tabTo(tester, () => focusedTip() == 'Próxima');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Repetir a lista');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Mostrar a letra');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Adicionar à playlist');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Fila');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Aparelhos');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Aparelhos', reason: 'the last one: not to the albums under the bar');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a computer, right from "Próxima" stays in the bar with an album row cut by it, as the grid scrolls', (
    tester,
  ) async {
    // As the grid first shows: its second row goes on under the bar, level with the buttons.
    await pumpFullHdHome(tester, television: false, followingAnotherDevice: true);
    await shiftTabTo(tester, () => focusedTip() == 'Próxima');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Repetir a faixa', reason: 'not the album under the bar');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Mostrar a letra');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Adicionar à playlist');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Fila');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Aparelhos');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Aparelhos');

    for (var i = 0; i < 6; i++) {
      await press(tester, LogicalKeyboardKey.arrowLeft);
    }

    expect(focusedTip(), 'Pausar', reason: 'and back left along the buttons');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a computer, left from the bar\'s song stays in the bar', (tester) async {
    await pumpFullHdHome(tester, television: false);
    await tabTo(tester, () => focusedTip() == 'Abrir o player');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedTip(), 'Abrir o player');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('left from the first album goes to the side rail, and right comes back to the albums', (tester) async {
    await pumpFullHdHome(tester);
    await tabTo(tester, () => focusedIn<AlbumTile>());
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(inRail(), isTrue, reason: 'out of the page');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn<AlbumTile>(), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('up from the top of the page goes to the top bar, and down stays in the page to its bottom', (
    tester,
  ) async {
    await pumpFullHdHome(tester);
    await tabTo(tester, () => focusedIn<AlbumTile>());
    await pressUntil(tester, LogicalKeyboardKey.arrowUp, inTopBar);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn<HomeView>(), isTrue, reason: 'back in the page');

    for (var i = 0; i < 10; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn<HomeView>(), isTrue);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on an album over the home, the arrows go to the bars and back to the album, not the home under it', (
    tester,
  ) async {
    await pumpFullHdHome(tester);
    await tabTo(tester, () => focusedIn<AlbumTile>());
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AlbumPage), findsOneWidget);
    await pressUntil(tester, LogicalKeyboardKey.arrowDown, () => focusedIn<AlbumPage>());

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(inRail(), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn<AlbumPage>(), isTrue, reason: 'the album, not the home\'s albums under it');

    await pressUntil(tester, LogicalKeyboardKey.arrowUp, inTopBar);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn<AlbumPage>(), isTrue);

    for (var i = 0; i < 25; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIn<AlbumPage>(), isTrue, reason: 'to its last track, under which the TV has no bar');
    }

    // The remote's back: the album closes, and the focus is back on it, in the home.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsNothing);
    expect(focusedIn<AlbumTile>() && focusedIn<HomeView>(), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a section the rail opened, then left, takes no focus under the one shown', (tester) async {
    await pumpFullHdHome(tester);
    await shiftTabTo(tester, () => focusedTip() == 'Álbuns');
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn<AlbumsView>(), isTrue);

    await shiftTabTo(tester, () => focusedTip() == 'Início');
    await press(tester, LogicalKeyboardKey.enter);
    await tabTo(tester, () => focusedTip() == 'Álbuns');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn<HomeView>(), isTrue);

    for (final key in [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown]) {
      await press(tester, key);
      expect(focusedIn<AlbumsView>(), isFalse, reason: 'the albums section is hidden');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the search bar opens the keyboard on the center button, not as the focus comes to it', (tester) async {
    await pumpFullHdHome(tester);
    await shiftTabTo(tester, inSearch);
    expect(tester.testTextInput.isVisible, isFalse, reason: 'the focus only passing by');
    await press(tester, LogicalKeyboardKey.select);
    expect(inSearch(), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('left and right go on from the search bar to the buttons beside it', (tester) async {
    await pumpFullHdHome(tester);
    await shiftTabTo(tester, inSearch);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn<ShuffleLibraryChip>(), isTrue, reason: 'the library at random');
    expect(inTopBar(), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTip(), 'Configurações', reason: 'past the hub\'s status, which only tells');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(inSearch(), isTrue);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedTip(), 'Início', reason: 'the app\'s icon: a TV has no arrows beside it, its remote going back');
    expect(find.byTooltip('Voltar'), findsNothing);
    expect(find.byTooltip('Avançar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('left and right stay in the top bar, rather than go to a card scrolled under it, level with the search', (
    tester,
  ) async {
    await pumpFullHdHome(tester);

    final search = tester.widget<TextField>(find.descendant(of: find.byType(AppBar), matching: find.byType(TextField)));

    search.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    final page = tester.state<ScrollableState>(
      find.descendant(of: find.byType(HomeView), matching: find.byType(Scrollable)).first,
    );
    final band = FocusManager.instance.primaryFocus!.rect;

    // The first row of albums level with the search, scrolled under the bar.
    page.position.jumpTo(tester.getRect(find.byType(AlbumTile).first).center.dy - band.center.dy);
    await tester.pumpAndSettle();

    final under = [
      for (final tile in tester.widgetList(find.byType(AlbumTile)))
        if (tester.getRect(find.byWidget(tile)) case final rect when rect.top < band.bottom && rect.bottom > band.top)
          rect,
    ];

    expect(under, isNotEmpty, reason: 'a card under the bar, level with the search');

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedTip(), 'Início');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(inSearch(), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}

/// The search bar's text field has the focus.
bool inSearch() => focusedIn<TextField>() && inTopBar();

bool focusedIn<T extends Widget>() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<T>() != null;

bool inRail() => ['Tocando agora', 'Álbuns', 'Artistas', 'Gêneros', 'Playlists', 'Favoritos'].contains(focusedTip());

/// In the home's top bar: the app's icon, the arrows, the search, the buttons at its end.
bool inTopBar() => focusedIn<AppBar>() && focusedIn<HomePage>();

/// Presses [key] until [there], a few times at most.
Future<void> pressUntil(WidgetTester tester, LogicalKeyboardKey key, bool Function() there) async {
  for (var i = 0; i < 30 && !there(); i++) {
    await press(tester, key);
  }

  expect(there(), isTrue);
}
