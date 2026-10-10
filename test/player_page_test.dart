import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/lyrics/lrclib.dart';
import 'package:segue/player/player.dart';
import 'package:segue/player/sleep_timer.dart';
import 'package:segue/segue/client.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album_page.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/artist_page.dart';
import 'package:segue/ui/cover.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/lyrics_page.dart';
import 'package:segue/ui/lyrics_view.dart';
import 'package:segue/ui/now_playing_bar.dart';
import 'package:segue/ui/player_page.dart';
import 'package:segue/ui/queue_page.dart';
import 'package:segue/ui/themed_icon.dart';

import 'fakes.dart';
import 'themed_icons.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A media server that knows two songs, with their albums and artists: Sweet Emotion (s1), by
/// Aerosmith, and Walk This Way (s2), by Run-DMC with Aerosmith.
http.Response library(http.Request request) {
  final path = request.url.path;
  final id = request.url.queryParameters['id'];
  const songs = {
    's1': {
      'id': 's1',
      'title': 'Sweet Emotion',
      'artist': 'Aerosmith',
      'album': 'Toys in the Attic',
      'albumId': 'a1',
      'artistId': 'ar1',
    },
    's2': {
      'id': 's2',
      'title': 'Walk This Way',
      'artist': 'Run-DMC; Aerosmith',
      'album': 'Raising Hell',
      'albumId': 'a2',
      'artistId': 'ar2',
      'artists': [
        {'id': 'ar2', 'name': 'Run-DMC'},
        {'id': 'ar1', 'name': 'Aerosmith'},
      ],
    },
  };
  final albums = {
    'a1': {
      'id': 'a1',
      'name': 'Toys in the Attic',
      'artist': 'Aerosmith',
      'song': [?songs['s1']],
    },
    'a2': {
      'id': 'a2',
      'name': 'Raising Hell',
      'artist': 'Run-DMC',
      'song': [?songs['s2']],
    },
  };
  final artists = {
    'ar1': {
      'id': 'ar1',
      'name': 'Aerosmith',
      'album': [
        {'id': 'a1', 'name': 'Toys in the Attic', 'year': 1975},
        {'id': 'a3', 'name': 'Get Your Wings', 'year': 1974},
      ],
    },
    'ar2': {
      'id': 'ar2',
      'name': 'Run-DMC',
      'album': [
        {'id': 'a2', 'name': 'Raising Hell', 'year': 1986},
      ],
    },
  };
  final found = switch (path.split('/').last) {
    'getSong.view' => songs[id] == null ? null : {'song': songs[id]},
    'getAlbum.view' => albums[id] == null ? null : {'album': albums[id]},
    'getArtist.view' => artists[id] == null ? null : {'artist': artists[id]},
    _ => null,
  };
  return found == null ? http.Response('', 404) : subsonic(found);
}

/// A hub client that sees the device tv play [song].
SegueClient tvPlaying(QueueItem song) {
  final client = SegueClient(
    url: Uri.parse('ws://unused'),
    auth: const Auth.subsonic(username: 'a', token: 't', salt: 's'),
    device: const DeviceInfo(id: 'me', name: 'me', client: 'test', api: Api.subsonic, roles: [], capabilities: []),
  );
  client.devices['tv'] = Device(
    info: const DeviceInfo(
      id: 'tv',
      name: 'Sala de estar',
      client: 'test',
      api: Api.subsonic,
      roles: [Role.player],
      capabilities: CommandAction.values,
    ),
    online: true,
    state: StampedState(
      status: PlaybackStatus.playing,
      positionMs: 61000,
      at: DateTime.now().millisecondsSinceEpoch,
      index: 0,
      queue: [song],
    ),
  );
  return client;
}

const sweetEmotion = Song(
  id: 's1',
  title: 'Sweet Emotion',
  artist: 'Aerosmith',
  album: 'Toys in the Attic',
  duration: Duration(seconds: 274),
);

/// The player bar, under the navigator as in the app, on a screen of [size] (a phone's by default),
/// playing [song] here, Sweet Emotion by default: under an empty page, or with [inHome], the home's.
/// [client] adds a hub, and the bar then shows what it says; [server] answers for the media server,
/// which by default knows nothing. With [sleepTimer], the session has one.
Future<PlayerController> pumpBar(
  WidgetTester tester, {
  SegueClient? client,
  http.Response Function(http.Request request)? server,
  Lrclib? lrclib,
  Size size = const Size(360, 640),
  bool inHome = false,
  Song song = sweetEmotion,
  bool sleepTimer = false,
}) async {
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async => server?.call(request) ?? http.Response('', 404)),
  );
  final player = PlayerController(FakeEngine(), api);

  if (client == null) {
    await player.playQueue([song], play: false);
  }

  final connect = ConnectController(player: player, client: client);
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  client?.notifyListeners(); // as when another device's state arrives
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    connect,
    lrclib: lrclib,
    sleepTimer: sleepTimer ? SleepTimer(player) : null,
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: inHome
          ? HomePage(onSignOut: () {})
          : const Scaffold(body: SizedBox.expand(), bottomNavigationBar: NowPlayingBar()),
    ),
  );
  return player;
}

/// A media server whose lyrics for every song are [lines]: (start in seconds, text), synced, or with
/// no starts, not; none at all, without lines.
http.Response Function(http.Request request) withLyrics(List<(int?, String)> lines) => (request) {
  if (!request.url.path.endsWith('getLyricsBySongId.view')) {
    return http.Response('', 404);
  }

  return subsonic({
    'type': 'navidrome',
    'lyricsList': {
      'structuredLyrics': [
        if (lines.isNotEmpty)
          {
            'synced': lines.first.$1 != null,
            'line': [
              for (final (start, text) in lines) {'start': ?(start == null ? null : start * 1000), 'value': text},
            ],
          },
      ],
    },
  });
};

const verse = [
  (0, 'You talk about things'),
  (5, 'That nobody cares'),
  (10, 'You\'re wearing out things'),
  (15, 'That nobody wears'),
];

/// The size of the lyrics' [line], and the theme's [size] of text, to compare it to.
(double?, double?) lyricsSize(WidgetTester tester, String line, TextStyle? Function(TextTheme text) size) => (
  tester.widget<Text>(onPage(find.text(line))).style?.fontSize,
  size(Theme.of(tester.element(onPage(find.byType(LyricsView)))).textTheme)?.fontSize,
);

/// How opaque the lyrics' [line] is.
double? opacity(WidgetTester tester, String line) => tester.widget<Text>(onPage(find.text(line))).style?.color?.a;

/// Whether the lyrics mark [line] as the one that plays.
bool marked(WidgetTester tester, String line) =>
    tester.widget<Text>(onPage(find.text(line))).style?.fontWeight == FontWeight.bold;

Future<void> openPlayer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Abrir o player'));
  await tester.pumpAndSettle();
}

Finder onPage(Finder finder) => find.descendant(of: find.byType(PlayerPage), matching: finder);

/// Opens the player, its lyrics under it, and from there the lyrics full screen.
Future<void> openLyricsPage(WidgetTester tester) async {
  await openPlayer(tester);
  await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
  await tester.pumpAndSettle();
  await tester.tap(onPage(find.byTooltip('Maximizar a letra')));
  await tester.pumpAndSettle();
  expect(find.byType(LyricsPage), findsOneWidget);
}

/// What [matches] in the full-screen player itself, rather than in the bar it keeps under it on a wide
/// screen.
Finder inPlayer(bool Function(Widget widget) matches) => find.byElementPredicate((element) {
  if (!matches(element.widget)) {
    return false;
  }

  var (inPage, inBar) = (false, false);
  element.visitAncestorElements((ancestor) {
    inBar |= ancestor.widget is NowPlayingBar;
    inPage |= ancestor.widget is PlayerPage;
    return !inPage;
  });
  return inPage && !inBar;
});

/// The full-screen player's own cover.
final playerCover = inPlayer((widget) => widget is Cover);

/// The full-screen player's own [tooltip].
Finder playerTip(String tooltip) => inPlayer((widget) => widget is Tooltip && widget.message == tooltip);

/// What the images ask for: it notes the covers, and has none of them.
class CoverRequests extends Fake implements HttpClient {
  final _urls = <Uri>[];

  /// The ids of the covers asked for at [size] pixels.
  Set<String?> at(int size) => {
    for (final url in _urls)
      if (url.queryParameters['size'] == '$size') url.queryParameters['id'],
  };

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _urls.add(url);
    return _NoCoverRequest();
  }
}

class _NoCoverRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _NoCover();
}

class _NoCover extends Fake implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.notFound;

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;
}

void main() {
  testWidgets('the bar opens the full-screen player: the song, its times and every control, even on a phone', (
    tester,
  ) async {
    final player = await pumpBar(tester);
    expect(find.text('4:34'), findsOneWidget, reason: 'the bar shows how long the song is');
    await openPlayer(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(onPage(find.text('Sweet Emotion')), findsOneWidget);
    expect(onPage(find.text('Aerosmith')), findsOneWidget);
    expect(onPage(find.text('Toys in the Attic')), findsOneWidget);
    expect(onPage(find.text('0:00')), findsOneWidget);
    expect(onPage(find.text('4:34')), findsOneWidget);

    for (final tooltip in ['Ativar aleatório', 'Anterior', 'Tocar', 'Próxima', 'Repetir a lista', 'Aparelhos']) {
      expect(onPage(find.byTooltip(tooltip)), findsOneWidget, reason: tooltip);
    }

    // On a phone, where the bar isn't under the player, the lyrics, the devices and the queue are in a bar of their
    // own, at the bottom, and the album is at the top.
    for (final tooltip in ['Mostrar a letra', 'Aparelhos', 'Fila']) {
      expect(
        tester.getRect(onPage(find.byTooltip(tooltip))).top,
        greaterThan(tester.getRect(onPage(find.byTooltip('Tocar'))).bottom),
        reason: tooltip,
      );
    }

    expect(find.descendant(of: onPage(find.byType(AppBar)), matching: find.text('Toys in the Attic')), findsOneWidget);

    expect(onPage(find.byType(NowPlayingBar)), findsNothing);

    await tester.tap(onPage(find.byTooltip('Tocar')));
    await tester.pump();
    expect(player.playing, isTrue);
    expect(onPage(find.byTooltip('Pausar')), findsOneWidget);

    await tester.tap(onPage(find.byTooltip('Fechar')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    await tester.pumpWidget(const SizedBox()); // stops the timers
  });

  testWidgets('the lyrics show beside the player, the line that plays marked as the song goes on', (tester) async {
    final player = await pumpBar(tester, server: withLyrics(verse), size: const Size(1280, 800));
    await player.seek(const Duration(seconds: 6));
    await openPlayer(tester);
    final cover = tester.getRect(playerCover);
    expect(onPage(find.text('That nobody cares')), findsNothing);

    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    // Half the screen each: the player in the middle of the left half, the lyrics all of the right.
    expect(tester.getRect(playerCover).size, cover.size, reason: 'the cover stays as it was');
    expect(tester.getCenter(playerCover).dx, 320);
    final lyrics = tester.getRect(onPage(find.byType(LyricsView)));
    expect((lyrics.left, lyrics.right), (640, 1280));
    expect(lyrics.top, lessThan(cover.bottom), reason: 'level with it');
    // On the player's background, each line in the middle.
    expect(
      find.ancestor(
        of: onPage(find.byType(LyricsView)),
        matching: onPage(find.byWidgetPredicate((widget) => widget is ColoredBox || widget is DecoratedBox)),
      ),
      findsNothing,
    );
    expect(tester.widget<Text>(onPage(find.text('That nobody cares'))).textAlign, TextAlign.center);
    final (size, headline) = lyricsSize(tester, 'You talk about things', (text) => text.headlineMedium);
    expect(size, headline, reason: 'big, with half the screen for them');
    expect(marked(tester, 'That nobody cares'), isTrue);
    expect(opacity(tester, 'That nobody cares'), 1, reason: 'the line that plays, whole');
    expect(opacity(tester, 'You talk about things'), lessThan(0.5), reason: 'the others, faded');
    expect(opacity(tester, 'That nobody wears'), lessThan(0.5));
    expect(marked(tester, 'You talk about things'), isFalse);

    await player.seek(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(marked(tester, 'You\'re wearing out things'), isTrue);
    expect(marked(tester, 'That nobody cares'), isFalse);

    await tester.tap(onPage(find.byTooltip('Esconder a letra')));
    await tester.pumpAndSettle();
    expect(onPage(find.byType(LyricsView)), findsNothing);
    expect(tester.getRect(playerCover), cover, reason: 'back where it was');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the lyrics show under the player, whose bar has no room for their button, the cover smaller '
      'to make room for them', (tester) async {
    await pumpBar(tester, server: withLyrics(verse));
    expect(find.byTooltip('Mostrar a letra'), findsNothing, reason: 'in the bar');
    await openPlayer(tester);
    final cover = tester.getSize(playerCover);
    final slider = tester.getSize(onPage(find.byType(Slider)));
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    expect(tester.getSize(playerCover).width, lessThan(cover.width));
    expect(tester.getSize(onPage(find.byType(Slider))), slider, reason: 'the rest as wide as before');
    final lyrics = tester.getRect(onPage(find.byType(LyricsView)));
    expect(lyrics.top, greaterThan(tester.getRect(onPage(find.byTooltip('Tocar'))).bottom));
    // On a phone this small, the cover goes out at the top rather than the lyrics under the buttons at the bottom.
    expect(lyrics.bottom, lessThanOrEqualTo(tester.getRect(onPage(find.byTooltip('Esconder a letra'))).top));
    final (size, headline) = lyricsSize(tester, 'You talk about things', (text) => text.headlineSmall);
    expect(size, headline, reason: 'a bit smaller, in a phone\'s width');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a tall phone the player is in the middle, between the top bar and the buttons\' at the bottom, '
      'above the system\'s, and with the lyrics all of it stays in view', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(412, 915));
    tester.view.padding = const FakeViewPadding(bottom: 48);
    await openPlayer(tester);
    final room = tester.getRect(onPage(find.byType(SingleChildScrollView)));
    final above = tester.getRect(playerCover).top - room.top;
    final below = room.bottom - tester.getRect(onPage(find.byTooltip('Tocar'))).bottom;
    expect(room.top, tester.getRect(onPage(find.byType(AppBar))).bottom);
    expect(above, greaterThan(8), reason: 'with room to spare');
    expect(above, moreOrLessEquals(below, epsilon: 1));

    for (final tooltip in ['Mostrar a letra', 'Aparelhos', 'Fila']) {
      final button = tester.getRect(onPage(find.byTooltip(tooltip)));
      expect(button.top, greaterThanOrEqualTo(room.bottom), reason: tooltip);
      expect(button.bottom, lessThanOrEqualTo(915 - 48), reason: tooltip);
    }

    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    expect(tester.getRect(playerCover).top, greaterThanOrEqualTo(room.top));
    expect(tester.getRect(onPage(find.byType(LyricsView))).bottom, lessThanOrEqualTo(room.bottom));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the lyrics come in gracefully, the player making room for them, and go the same way', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(1280, 800));
    await openPlayer(tester);
    final lyrics = onPage(find.byType(LyricsView));
    double shown() => tester.widget<Opacity>(find.ancestor(of: lyrics, matching: find.byType(Opacity)).first).opacity;

    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pump();
    await tester.pump(PlayerPage.lyricsTransition ~/ 2);
    // Halfway: the player on its way to the left half, the lyrics sliding in from the right, fading in.
    expect(tester.getCenter(playerCover).dx, inExclusiveRange(320, 640));
    expect(tester.getRect(lyrics).left, inExclusiveRange(640, 1280));
    expect(tester.getSize(lyrics).width, 640, reason: 'laid out as they end up, not narrower on the way');
    expect(shown(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(tester.getCenter(playerCover).dx, 320);
    expect(tester.getRect(lyrics).left, 640);
    expect(shown(), 1);

    await tester.tap(onPage(find.byTooltip('Esconder a letra')));
    await tester.pump();
    await tester.pump(PlayerPage.lyricsTransition ~/ 2);
    expect(tester.getCenter(playerCover).dx, inExclusiveRange(320, 640));
    expect(tester.getRect(lyrics).left, inExclusiveRange(640, 1280));
    expect(shown(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(lyrics, findsNothing);
    expect(tester.getCenter(playerCover).dx, 640);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the lyrics\' room under the player grows as they fade in, and the cover shrinks', (
    tester,
  ) async {
    await pumpBar(tester, server: withLyrics(verse));
    await openPlayer(tester);
    final lyrics = onPage(find.byType(LyricsView));
    double room() => tester.getSize(find.ancestor(of: lyrics, matching: find.byType(ClipRect)).first).height;
    double shown() => tester.widget<Opacity>(find.ancestor(of: lyrics, matching: find.byType(Opacity)).first).opacity;
    double cover() => tester.getSize(playerCover).width;
    final alone = cover();

    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pump();
    await tester.pump(PlayerPage.lyricsTransition ~/ 2);
    final (halfway, coverHalfway) = (room(), cover());
    expect(shown(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(halfway, inExclusiveRange(0, room()));
    expect(coverHalfway, inExclusiveRange(cover(), alone));
    expect(shown(), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a tap on the lyrics under the player opens them full screen, with the song, the slider and '
      'the buttons, where a line tapped goes where it starts', (tester) async {
    final player = await pumpBar(tester, server: withLyrics(verse));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    await tester.tap(onPage(find.text('That nobody cares')));
    await tester.pumpAndSettle();
    expect(player.position, Duration.zero, reason: 'the tap opened them, rather than going to the line');

    final page = find.byType(LyricsPage);
    Finder onLyrics(Finder finder) => find.descendant(of: page, matching: finder);
    expect(page, findsOneWidget);

    for (final shown in ['Sweet Emotion', 'Aerosmith']) {
      expect(find.descendant(of: onLyrics(find.byType(AppBar)), matching: find.text(shown)), findsOneWidget);
    }

    expect(onLyrics(find.byType(Slider)), findsOneWidget);

    for (final tooltip in ['Ativar aleatório', 'Anterior', 'Tocar', 'Próxima', 'Repetir a lista']) {
      expect(onLyrics(find.byTooltip(tooltip)), findsOneWidget, reason: tooltip);
    }

    await tester.tap(onLyrics(find.text('That nobody wears')));
    await tester.pumpAndSettle();
    expect(player.position.inSeconds, 15);

    await tester.tap(onLyrics(find.byTooltip('Minimizar a letra')));
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget, reason: 'back in the player');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the lyrics under the player have a button at their top right corner that opens them full screen too, '
      'and the pointer is a hand over them; Esc closes them, back to the player', (tester) async {
    await pumpBar(tester, server: withLyrics(verse));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final lyrics = tester.getRect(onPage(find.byType(LyricsView)));
    final corner = tester.getRect(onPage(find.byTooltip('Maximizar a letra')));
    expect(lyrics.intersect(corner), corner);
    expect(corner.center.dx, greaterThan(lyrics.center.dx));
    expect(corner.center.dy, lessThan(lyrics.center.dy));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(onPage(find.text('That nobody cares'))));
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);

    await tester.tap(onPage(find.byTooltip('Maximizar a letra')));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPage), findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('while the lyrics show full screen, the screen stays on, and may go off again as they close', (
    tester,
  ) async {
    const channel = MethodChannel('segue/device');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final keptOn = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'keepScreenOn') {
        keptOn.add(call.arguments);
      }

      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await pumpBar(tester, server: withLyrics(verse));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    expect(keptOn, isEmpty, reason: 'under the player, they are not all there is');

    await tester.tap(onPage(find.byTooltip('Maximizar a letra')));
    await tester.pumpAndSettle();
    expect(keptOn, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPage), findsNothing);
    expect(keptOn, [true, false]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('at their top left, the lyrics full screen have a button that hides them: they go down, whole, over '
      'the player, which is back as it opened, without them', (tester) async {
    await pumpBar(tester, server: withLyrics(verse));
    await openLyricsPage(tester);
    final page = find.byType(LyricsPage);
    Finder onLyrics(Finder finder) => find.descendant(of: page, matching: finder);
    final hide = tester.getRect(onLyrics(find.byTooltip('Esconder a letra')));
    expect(hide.right, lessThan(tester.getRect(onLyrics(find.byTooltip('Minimizar a letra'))).left));
    expect(hide.top, lessThan(tester.getRect(onLyrics(find.byType(LyricsView))).top));

    await tester.tap(onLyrics(find.byTooltip('Esconder a letra')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(onLyrics(find.byType(AppBar))).top, inExclusiveRange(0, 640));
    expect(
      tester.widget<FadeTransition>(find.ancestor(of: page, matching: find.byType(FadeTransition)).first).opacity.value,
      1,
    );
    expect(tester.getRect(onPage(find.byType(AppBar))).top, 0, reason: 'the player stays');
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(onPage(find.byType(LyricsView)), findsNothing, reason: 'hidden under the player too');
    expect(onPage(find.byTooltip('Mostrar a letra')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a drag down on the lyrics full screen takes them down over the player, and let go past a '
      'third of the way, or flung, back under it, as minimized; the lyrics scroll as they do', (tester) async {
    await pumpBar(tester, server: withLyrics([for (var line = 0; line < 30; line++) (line * 5, 'Line $line')]));
    await openLyricsPage(tester);
    final page = find.byType(LyricsPage);
    Finder onLyrics(Finder finder) => find.descendant(of: page, matching: finder);
    final top = onLyrics(find.byType(AppBar));

    await tester.drag(onLyrics(find.text('Line 3')), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(tester.getRect(top).top, 0, reason: 'the lyrics took it');

    // Where nothing else takes a drag, it starts with the finger.
    final finger = await tester.startGesture(tester.getCenter(onLyrics(find.text('Sweet Emotion'))));
    await finger.moveBy(const Offset(0, 150));
    await tester.pump();
    expect(tester.getRect(top).top, 150, reason: 'with the finger');
    expect(tester.getRect(onPage(find.byType(AppBar))).top, 0, reason: 'over the player, which stays');
    await finger.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(top).top, 0, reason: 'back up, short of a third');
    expect(find.byType(PlayerPage), findsNothing, reason: 'under them, hidden');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(page, findsNothing, reason: 'Esc takes them back to the player, the focus back in them');
    expect(onPage(find.byType(LyricsView)), findsOneWidget, reason: 'under it, as they were');

    await tester.tap(onPage(find.byTooltip('Maximizar a letra')));
    await tester.pumpAndSettle();
    await tester.drag(onLyrics(find.text('Sweet Emotion')), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(onPage(find.byType(LyricsView)), findsOneWidget, reason: 'under the player, a step back only');
    expect(onPage(find.byTooltip('Esconder a letra')), findsOneWidget);

    // From the buttons under them too.
    await tester.tap(onPage(find.byTooltip('Maximizar a letra')));
    await tester.pumpAndSettle();
    await tester.fling(onLyrics(find.byTooltip('Anterior')), const Offset(0, 60), 1000);
    await tester.pumpAndSettle();
    expect(page, findsNothing, reason: 'flung, however short');
    expect(onPage(find.byType(LyricsView)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('as the lyrics full screen fade out over the player, a drag down on it waits for them to have gone', (
    tester,
  ) async {
    await pumpBar(tester, server: withLyrics(verse));
    await openLyricsPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LyricsPage), findsOneWidget);
    final top = onPage(find.byType(AppBar));

    final finger = await tester.startGesture(tester.getCenter(onPage(find.byTooltip('Fila'))));
    await finger.moveBy(const Offset(0, 20)); // past the slop, where the drag starts
    await finger.moveBy(const Offset(0, 50));
    await tester.pump();
    expect(tester.getRect(top).top, 0);
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPage), findsNothing);
    // Back under the player, they go out with the finger, rather than the player down.
    final lyrics = onPage(find.byType(LyricsView));
    double shown() => tester.widget<Opacity>(find.ancestor(of: lyrics, matching: find.byType(Opacity)).first).opacity;
    expect(shown(), 1);
    await finger.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(shown(), inExclusiveRange(0, 1));
    expect(tester.getRect(top).top, 0);
    await finger.up();
    await tester.pumpAndSettle();
    expect(lyrics, findsNothing);
    expect(tester.getRect(top).top, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, where they are under the player, the lyrics full screen\'s button hides them, and a '
      'drag down leaves them be', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(650, 800));
    await tester.tap(find.byTooltip('Mostrar a letra'));
    await tester.pumpAndSettle();
    await tester.tap(onPage(find.byTooltip('Maximizar a letra')));
    await tester.pumpAndSettle();
    final page = find.byType(LyricsPage);
    await tester.fling(find.descendant(of: page, matching: find.byType(AppBar)), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(page, findsOneWidget);
    expect(tester.getRect(find.descendant(of: page, matching: find.byType(AppBar))).top, 0);

    await tester.tap(find.descendant(of: page, matching: find.byTooltip('Esconder a letra')));
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(onPage(find.byType(LyricsView)), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a player opened with the lyrics shows them at once', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(1280, 800));
    await tester.tap(find.byTooltip('Mostrar a letra'));
    // The page's first frame is offstage, for the bar's hero to measure it; the next is the first that shows.
    await tester.pump();
    await tester.pump();
    final lyrics = onPage(find.byType(LyricsView));
    expect(tester.getRect(lyrics).left, 640);
    expect(tester.widget<Opacity>(find.ancestor(of: lyrics, matching: find.byType(Opacity)).first).opacity, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wide bar has a button for the lyrics, which opens the player with them', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(1000, 700));
    await tester.tap(find.byTooltip('Mostrar a letra'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(onPage(find.byType(LyricsView)), findsOneWidget);
    expect(onPage(find.text('You talk about things')), findsOneWidget);
    expect(onPage(find.byTooltip('Esconder a letra')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long lyrics scroll to the line that plays, which stays in their upper half while there is more to '
      'scroll, and the page stays where it was', (tester) async {
    // A tall phone's: a small one's lyrics are short enough for their last line to stay where the line that plays
    // does, with where they come from under it.
    final player = await pumpBar(
      tester,
      server: withLyrics([for (var i = 0; i < 60; i++) (i * 4, 'Line $i')]),
      size: const Size(412, 915),
    );
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final title = tester.getRect(onPage(find.text('Sweet Emotion')));
    final lyrics = tester.getRect(onPage(find.byType(LyricsView)));

    final scroll = tester
        .state<ScrollableState>(find.descendant(of: onPage(find.byType(LyricsView)), matching: find.byType(Scrollable)))
        .position;

    await player.seek(const Duration(seconds: 160));
    await tester.pumpAndSettle();
    expect(marked(tester, 'Line 40'), isTrue);
    var line = tester.getRect(onPage(find.text('Line 40')));
    expect(line.top, greaterThan(lyrics.top), reason: 'in view');
    expect(line.bottom, lessThan(lyrics.center.dy), reason: 'not past the middle');
    final held = line.top;

    // With no more to scroll, the last lines go on down.
    await player.seek(const Duration(seconds: 237));
    await tester.pumpAndSettle();
    expect(marked(tester, 'Line 59'), isTrue);
    line = tester.getRect(onPage(find.text('Line 59')));
    expect(line.top, greaterThan(held));
    expect(line.bottom, lessThanOrEqualTo(lyrics.bottom), reason: 'in view');
    expect(scroll.pixels, scroll.maxScrollExtent);

    expect(tester.getRect(onPage(find.text('Sweet Emotion'))), title);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the lyrics scroll by themselves with no scrollbar, which shows when the user scrolls them', (
    tester,
  ) async {
    final player = await pumpBar(
      tester,
      server: withLyrics([for (var i = 0; i < 60; i++) (i * 4, 'Line $i')]),
      size: const Size(1280, 800),
    );
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final scrollbar = find.descendant(of: onPage(find.byType(LyricsView)), matching: find.byType(Scrollbar));
    expect(scrollbar, findsOneWidget);

    await player.seek(const Duration(seconds: 160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // as they scroll
    expect(scrollbar, isNot(paints..rrect()));
    await tester.pumpAndSettle();
    expect(scrollbar, isNot(paints..rrect()));

    await tester.drag(onPage(find.text('Line 40')), const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // as it fades in
    expect(scrollbar, paints..rrect());
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the lyrics end saying where they come from', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(1280, 800));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final credit = onPage(find.text('Letras providas por Navidrome'));
    expect(credit, findsOneWidget);
    expect(tester.getRect(credit).top, greaterThan(tester.getRect(onPage(find.text('That nobody wears'))).bottom));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the top bar keeps the background\'s color as the lyrics scroll under it', (tester) async {
    final player = await pumpBar(
      tester,
      server: withLyrics([for (var i = 0; i < 60; i++) (i * 4, 'Line $i')]),
      size: const Size(1280, 800),
    );
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();

    (Color?, double) bar() {
      final material = tester.widget<Material>(
        find.descendant(of: onPage(find.byType(AppBar)), matching: find.byType(Material)).first,
      );
      return (material.color, material.elevation);
    }

    final background = Theme.of(tester.element(onPage(find.byType(LyricsView)))).colorScheme.surface;
    expect(bar(), (background, 0));
    await player.seek(const Duration(seconds: 160)); // they scroll by themselves
    await tester.pumpAndSettle();
    expect(bar(), (background, 0));
    await tester.drag(onPage(find.text('Line 40')), const Offset(0, -300)); // and by the user
    await tester.pumpAndSettle();
    expect(bar(), (background, 0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the lyrics fade out at their top and bottom, with room there to show whole at the ends', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(1280, 800));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final fade = find.descendant(of: onPage(find.byType(LyricsView)), matching: find.byType(ShaderMask));
    expect(fade, findsOneWidget);
    expect(tester.widget<ShaderMask>(fade).blendMode, BlendMode.dstIn, reason: 'it keeps the lines where it is opaque');
    final first = find.descendant(of: fade, matching: find.text('You talk about things'));
    expect(first, findsOneWidget);
    expect(tester.getRect(first).top - tester.getRect(fade).top, greaterThanOrEqualTo(LyricsView.edgeFade));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a blank line of synced lyrics, a part with no singing, shows a note, whole while it plays', (
    tester,
  ) async {
    final player = await pumpBar(
      tester,
      server: withLyrics([(0, 'Sweet emotion'), (5, ''), (10, 'Talk about things')]),
      size: const Size(1280, 800),
    );
    await player.seek(const Duration(seconds: 6));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final note = find.descendant(
      of: onPage(find.byType(LyricsView)),
      matching: themedIcon(LyricsView.instrumentalIcon),
    );
    expect(note, findsOneWidget);
    expect(tester.getCenter(note).dy, greaterThan(tester.getRect(onPage(find.text('Sweet emotion'))).bottom));
    expect(tester.getCenter(note).dy, lessThan(tester.getRect(onPage(find.text('Talk about things'))).top));
    expect(tester.widget<ThemedIcon>(note).color?.a, 1, reason: 'it plays');
    expect(marked(tester, 'Sweet emotion'), isFalse);

    await player.seek(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(tester.widget<ThemedIcon>(note).color?.a, lessThan(0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an intro before the first line shows a note above it, while it plays', (tester) async {
    final player = await pumpBar(
      tester,
      server: withLyrics([(8, 'Sweet emotion'), (12, 'Talk about things')]),
      size: const Size(1280, 800),
    );
    await player.seek(const Duration(seconds: 2));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final note = find.descendant(
      of: onPage(find.byType(LyricsView)),
      matching: themedIcon(LyricsView.instrumentalIcon),
    );
    expect(note, findsOneWidget);
    expect(tester.getCenter(note).dy, lessThan(tester.getRect(onPage(find.text('Sweet emotion'))).top));
    expect(tester.widget<ThemedIcon>(note).color?.a, 1);

    await player.seek(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(marked(tester, 'Sweet emotion'), isTrue);
    expect(tester.widget<ThemedIcon>(note).color?.a, lessThan(0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a line of synced lyrics, tapped, goes there', (tester) async {
    final player = await pumpBar(tester, server: withLyrics(verse), size: const Size(1280, 800));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    await tester.tap(onPage(find.text('That nobody wears')));
    await tester.pumpAndSettle();
    expect(player.position.inSeconds, 15);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lyrics that aren\'t synced show as they are, with no line marked', (tester) async {
    final player = await pumpBar(
      tester,
      server: withLyrics([for (final (_, text) in verse) (null, text)]),
      size: const Size(1280, 800),
    );
    await player.seek(const Duration(seconds: 6));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();

    for (final (_, text) in verse) {
      expect(marked(tester, text), isFalse, reason: text);
      expect(opacity(tester, text), 1, reason: '$text: none faded, with none playing');
    }

    await tester.tap(onPage(find.text('That nobody wears')));
    await tester.pumpAndSettle();
    expect(player.position.inSeconds, 6, reason: 'not a place in the song');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lyrics the media server doesn\'t have come from LRCLIB, which they say', (tester) async {
    final asked = <http.Request>[];
    final lrclib = Lrclib(
      client: MockClient((request) async {
        asked.add(request);
        return request.url.path == '/api/get'
            ? http.Response(
                jsonEncode({
                  'trackName': 'Sweet Emotion',
                  'artistName': 'Aerosmith',
                  'duration': 274,
                  'instrumental': false,
                  'syncedLyrics': '[00:00.00] You talk about things\n[00:05.00] That nobody cares',
                }),
                200,
                headers: {'content-type': 'application/json'},
              )
            : http.Response('', 404);
      }),
    );
    await pumpBar(tester, server: withLyrics([]), lrclib: lrclib, size: const Size(1280, 800));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    expect(asked.single.url.queryParameters['track_name'], 'Sweet Emotion');
    expect(onPage(find.text('That nobody cares')), findsOneWidget);
    expect(onPage(find.text('Letras providas por LRCLIB')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('LRCLIB failing, with the media server having no lyrics, says so, but not how', (tester) async {
    final lrclib = Lrclib(client: MockClient((_) async => http.Response('', 503)));
    await pumpBar(tester, server: withLyrics([]), lrclib: lrclib, size: const Size(1280, 800));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    expect(onPage(find.text('Não consegui buscar a letra.')), findsOneWidget);
    expect(onPage(find.textContaining('503')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song without lyrics says so', (tester) async {
    await pumpBar(tester, server: withLyrics([]));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    expect(onPage(find.text('Esta música não tem letra.')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a big screen the cover is as big as the height leaves room for, with the rest in view', (
    tester,
  ) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(1920, 1080));
    await openPlayer(tester);

    void expectBig(String what) {
      expect(tester.getSize(playerCover).height, greaterThan(600), reason: what);
      expect(
        tester.getRect(inPlayer((widget) => widget is Text && widget.data == 'Toys in the Attic')).bottom,
        lessThanOrEqualTo(tester.getRect(onPage(find.byType(NowPlayingBar))).top),
        reason: what,
      );
    }

    expectBig('alone');
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    expectBig('beside the lyrics');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the song\'s title, artist and album show in the middle, big, the title in bold', (tester) async {
    await pumpBar(tester, size: const Size(1280, 800));
    await openPlayer(tester);
    final cover = tester.getRect(playerCover);
    final text = Theme.of(tester.element(playerCover)).textTheme;

    for (final (line, size, bold) in [
      ('Sweet Emotion', text.headlineMedium, true),
      ('Aerosmith', text.titleLarge, false),
      ('Toys in the Attic', text.titleMedium, false),
    ]) {
      final shown = inPlayer((widget) => widget is Text && widget.data == line);
      final style = tester.widget<Text>(shown).style;
      expect(style?.fontSize, size?.fontSize, reason: line);
      expect(style?.fontWeight == FontWeight.bold, bold, reason: line);
      // The artists are pieces in a line, which is centered as a whole; the title and the album, each one text, center it.
      if (line != 'Aerosmith') {
        expect(tester.widget<Text>(shown).textAlign, TextAlign.center, reason: line);
      }

      expect(tester.getCenter(shown).dx, moreOrLessEquals(cover.center.dx, epsilon: 1), reason: line);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen the minimized player stays under the full-screen one, with the lyrics, the queue and '
      'the devices, which leave its top bar', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(1280, 800));
    await openPlayer(tester);
    final bar = onPage(find.byType(NowPlayingBar));
    expect(bar, findsOneWidget);

    for (final tooltip in ['Mostrar a letra', 'Fila', 'Aparelhos']) {
      expect(find.descendant(of: onPage(find.byType(AppBar)), matching: find.byTooltip(tooltip)), findsNothing);
      expect(
        find.descendant(of: bar, matching: find.byTooltip(tooltip)),
        findsOneWidget,
        reason: tooltip,
      );
    }

    await tester.tap(find.descendant(of: bar, matching: find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget, reason: 'in this player, not another');
    expect(onPage(find.byType(LyricsView)), findsOneWidget);
    await tester.tap(find.descendant(of: bar, matching: find.byTooltip('Esconder a letra')));
    await tester.pumpAndSettle();
    expect(onPage(find.byType(LyricsView)), findsNothing);

    // Its song closes the full-screen player.
    await tester.tap(find.descendant(of: bar, matching: find.byTooltip('Fechar o player')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen the full-screen player shows the song alone: the controls are the bar\'s, under it', (
    tester,
  ) async {
    await pumpBar(tester, size: const Size(1280, 800));
    await openPlayer(tester);
    expect(onPage(find.text('Sweet Emotion')), findsWidgets);
    expect(playerCover, findsOneWidget);
    expect(inPlayer((widget) => widget is Slider), findsNothing);

    for (final tooltip in ['Ativar aleatório', 'Anterior', 'Tocar', 'Próxima', 'Repetir a lista']) {
      expect(playerTip(tooltip), findsNothing, reason: tooltip);
      expect(
        find.descendant(of: onPage(find.byType(NowPlayingBar)), matching: find.byTooltip(tooltip)),
        findsOneWidget,
      );
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen the bar stays put as the full-screen player slides up over the page', (tester) async {
    await pumpBar(tester, size: const Size(1280, 800));
    final devices = tester.getRect(find.byTooltip('Aparelhos')); // in the bar alone
    await tester.tap(find.byTooltip('Abrir o player'));
    await tester.pump();

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(find.byTooltip('Aparelhos')), devices, reason: 'as the player slides up');
    }

    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(tester.getRect(find.byTooltip('Aparelhos')), devices, reason: 'under the player');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the bar stays put from page to page: the queue has it too', (tester) async {
    await pumpBar(tester, size: const Size(1280, 800));
    final next = tester.getRect(find.byTooltip('Próxima'));
    await tester.tap(find.byTooltip('Fila'));
    await tester.pump();

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(find.byTooltip('Próxima')), next, reason: 'as the queue comes in');
    }

    await tester.pumpAndSettle();
    expect(find.byType(QueuePage), findsOneWidget);
    expect(tester.getRect(find.byTooltip('Próxima')), next, reason: 'under the queue');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Esc closes the full-screen player', (tester) async {
    await pumpBar(tester);
    await openPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a swipe on the cover to the left goes to the next song, and to the right to the previous one, wherever '
      'the song is; a short one, back to its place', (tester) async {
    final player = await pumpBar(tester);
    await player.playQueue(const [
      Song(id: 's1', title: 'Sweet Emotion', artist: 'Aerosmith', duration: Duration(seconds: 274)),
      Song(id: 's2', title: 'Walk This Way', artist: 'Run-DMC', duration: Duration(seconds: 311)),
    ], play: false);
    await openPlayer(tester);
    final place = tester.getRect(playerCover);

    await tester.drag(playerCover, const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(player.index, 0, reason: 'too short');
    expect(tester.getRect(playerCover), place, reason: 'back in its place');

    await tester.drag(playerCover, Offset(-place.width / 2, 0));
    await tester.pumpAndSettle();
    expect(player.index, 1);
    expect(onPage(find.text('Walk This Way')), findsOneWidget);
    expect(tester.getRect(playerCover), place, reason: 'back from the other side');

    // Past the first seconds, where the button only starts the song over.
    await player.seek(const Duration(seconds: 30));
    await tester.fling(playerCover, const Offset(60, 0), 1000);
    await tester.pumpAndSettle();
    expect(player.index, 0, reason: 'flung, however short');

    // The first song has none before it.
    await player.seek(const Duration(seconds: 30));
    await tester.fling(playerCover, const Offset(60, 0), 1000);
    await tester.pumpAndSettle();
    expect(player.index, 0);
    expect(player.position, greaterThanOrEqualTo(const Duration(seconds: 30)), reason: 'not started over');
    expect(tester.getRect(playerCover), place);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on the last song, a swipe to the left goes nowhere, as one to the right on the first; unless the queue '
      'repeats, when it goes to the first', (tester) async {
    final player = await pumpBar(tester);
    await player.playQueue(
      const [
        Song(id: 's1', title: 'Sweet Emotion', artist: 'Aerosmith', duration: Duration(seconds: 274)),
        Song(id: 's2', title: 'Walk This Way', artist: 'Run-DMC', duration: Duration(seconds: 311)),
      ],
      index: 1,
      play: false,
    );
    await openPlayer(tester);
    final place = tester.getRect(playerCover);

    await tester.fling(playerCover, const Offset(-60, 0), 1000);
    await tester.pumpAndSettle();
    expect(player.index, 1);
    expect(find.text('Não há próxima faixa.'), findsNothing);
    expect(tester.getRect(playerCover), place, reason: 'back in its place');

    await player.setRepeat(Repeat.all);
    await tester.fling(playerCover, const Offset(-60, 0), 1000);
    await tester.pumpAndSettle();
    expect(player.index, 0);
    expect(tester.getRect(playerCover), place);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a swipe sends the cover out as it was, and it comes back from the other side with the song it went to', (
    tester,
  ) async {
    final player = await pumpBar(tester);
    await player.playQueue(const [
      Song(id: 's1', title: 'Sweet Emotion', artist: 'Aerosmith', coverArt: 'c1', duration: Duration(seconds: 274)),
      Song(id: 's2', title: 'Walk This Way', artist: 'Run-DMC', coverArt: 'c2', duration: Duration(seconds: 311)),
    ], play: false);
    await openPlayer(tester);
    final place = tester.getRect(playerCover);
    String? cover() => tester.widget<Cover>(playerCover).id;

    await tester.drag(playerCover, Offset(-place.width / 2, 0));
    await tester.pump();
    expect(player.index, 1);
    expect(onPage(find.text('Walk This Way')), findsOneWidget);
    expect(cover(), 'c1', reason: 'the song it leaves, on its way out');

    await tester.pump(const Duration(milliseconds: 100));
    expect(cover(), 'c1');
    expect(tester.getRect(playerCover).left, lessThan(place.left));

    await tester.pump(const Duration(milliseconds: 100)); // out of sight by now
    expect(cover(), 'c2');
    expect(tester.getRect(playerCover).left, greaterThan(place.left), reason: 'from the other side');

    await tester.pumpAndSettle();
    expect(tester.getRect(playerCover), place);
    expect(cover(), 'c2');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the covers of the songs on either side load ahead, for a swipe to bring at once', (tester) async {
    final covers = CoverRequests();
    debugNetworkImageHttpClientProvider = () => covers;

    try {
      final player = await pumpBar(tester);
      await player.playQueue(
        const [
          Song(id: 's1', title: 'Sweet Emotion', artist: 'Aerosmith', coverArt: 'c1', duration: Duration(seconds: 274)),
          Song(id: 's2', title: 'Walk This Way', artist: 'Run-DMC', coverArt: 'c2', duration: Duration(seconds: 311)),
          Song(id: 's3', title: 'Dream On', artist: 'Aerosmith', coverArt: 'c3', duration: Duration(seconds: 267)),
          Song(
            id: 's4',
            title: 'Back in the Saddle',
            artist: 'Aerosmith',
            coverArt: 'c4',
            duration: Duration(seconds: 280),
          ),
        ],
        index: 1,
        play: false,
      );
      await openPlayer(tester);
      expect(covers.at(800), {'c1', 'c2', 'c3'});

      await tester.drag(playerCover, Offset(-tester.getSize(playerCover).width / 2, 0));
      await tester.pumpAndSettle();
      expect(player.index, 2);
      expect(covers.at(800), {'c1', 'c2', 'c3', 'c4'});
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  testWidgets('on a phone, a drag down takes the player down with it, over the page under it; let go past a third of '
      'the way down, or flung, it closes, and otherwise goes back up', (tester) async {
    await pumpBar(tester);
    await openPlayer(tester);
    final top = onPage(find.byType(AppBar));

    final finger = await tester.startGesture(tester.getCenter(playerCover));
    await finger.moveBy(const Offset(0, 20)); // past the slop, where the drag starts
    await finger.moveBy(const Offset(0, 150));
    await tester.pump();
    expect(tester.getRect(top).top, 150, reason: 'with the finger');
    expect(find.byTooltip('Abrir o player'), findsOneWidget, reason: 'the bar under it shows');
    await finger.moveBy(const Offset(0, -50));
    await tester.pump();
    expect(tester.getRect(top).top, 100);
    await finger.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(top).top, 0, reason: 'back up, short of a third');
    expect(find.byTooltip('Abrir o player'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing, reason: 'Esc closes it, the focus back in it');

    await openPlayer(tester);
    await tester.drag(playerCover, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);

    // From its bars too.
    await openPlayer(tester);
    await tester.fling(onPage(find.byTooltip('Fila')), const Offset(0, 60), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing, reason: 'flung, however short');

    // Not up, past where it opens: that brings the lyrics in.
    await openPlayer(tester);
    await tester.fling(playerCover, const Offset(0, -200), 1000);
    await tester.pumpAndSettle();
    expect(tester.getRect(top).top, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a drag up brings the lyrics in with the finger, where they are hidden; let go past a third '
      'of the way, or flung, they stay, and otherwise go back out', (tester) async {
    await pumpBar(tester, server: withLyrics(verse));
    await openPlayer(tester);
    final top = onPage(find.byType(AppBar));
    final lyrics = onPage(find.byType(LyricsView));
    double shown() => tester.widget<Opacity>(find.ancestor(of: lyrics, matching: find.byType(Opacity)).first).opacity;
    final cover = tester.getSize(playerCover).width;

    final finger = await tester.startGesture(tester.getCenter(playerCover));
    await finger.moveBy(const Offset(0, -20)); // past the slop, where the drag starts
    await finger.moveBy(const Offset(0, -40));
    await tester.pump();
    final some = shown();
    expect(some, inExclusiveRange(0, 1), reason: 'with the finger');
    expect(tester.getSize(playerCover).width, lessThan(cover), reason: 'the cover making room for them');
    await finger.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(shown(), greaterThan(some));
    await finger.moveBy(const Offset(0, 70));
    await tester.pump();
    expect(shown(), lessThan(some));
    await finger.up();
    await tester.pumpAndSettle();
    expect(lyrics, findsNothing, reason: 'back out, short of a third');
    expect(tester.getSize(playerCover).width, cover);
    expect(onPage(find.byTooltip('Mostrar a letra')), findsOneWidget);

    await tester.drag(playerCover, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(shown(), 1);
    expect(onPage(find.byTooltip('Esconder a letra')), findsOneWidget, reason: 'turned on, as by their button');
    expect(tester.getRect(top).top, 0, reason: 'the player where it opens');

    // From the bars too.
    await tester.tap(onPage(find.byTooltip('Esconder a letra')));
    await tester.pumpAndSettle();
    await tester.fling(onPage(find.byTooltip('Fila')), const Offset(0, -60), 1000);
    await tester.pumpAndSettle();
    expect(shown(), 1, reason: 'flung, however short');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, with the lyrics under the player, a drag down takes them out with the finger, rather than '
      'the player down; let go past a third of the way, or flung, they hide, and otherwise come back', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(412, 915));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final top = onPage(find.byType(AppBar));
    final lyrics = onPage(find.byType(LyricsView));
    double shown() => tester.widget<Opacity>(find.ancestor(of: lyrics, matching: find.byType(Opacity)).first).opacity;

    final finger = await tester.startGesture(tester.getCenter(playerCover));
    await finger.moveBy(const Offset(0, 20)); // past the slop, where the drag starts
    await finger.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(shown(), inExclusiveRange(0, 1), reason: 'with the finger');
    expect(tester.getRect(top).top, 0, reason: 'the player where it opens');
    await finger.up();
    await tester.pumpAndSettle();
    expect(shown(), 1, reason: 'back, short of a third');

    await tester.drag(playerCover, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(lyrics, findsNothing);
    expect(onPage(find.byTooltip('Mostrar a letra')), findsOneWidget, reason: 'turned off, as by their button');
    expect(tester.getRect(top).top, 0);

    // From the bars too.
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    await tester.fling(onPage(find.byTooltip('Fila')), const Offset(0, 60), 1000);
    await tester.pumpAndSettle();
    expect(lyrics, findsNothing, reason: 'flung, however short');

    // Hidden, the next drag down takes the player down.
    await tester.drag(playerCover, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, with the lyrics under the player, a drag up opens them full screen, let go past a third of '
      'the way that brings them in, or flung', (tester) async {
    await pumpBar(tester, server: withLyrics(verse));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final title = onPage(find.text('Sweet Emotion'));

    final finger = await tester.startGesture(tester.getCenter(title));
    await finger.moveBy(const Offset(0, -20)); // past the slop, where the drag starts
    await finger.moveBy(const Offset(0, -30));
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPage), findsNothing, reason: 'short of a third');
    expect(onPage(find.byTooltip('Esconder a letra')), findsOneWidget, reason: 'still under the player');

    await tester.drag(title, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPage), findsOneWidget);

    // From the bars too, flung.
    await tester.tap(find.byTooltip('Minimizar a letra'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPage), findsNothing);
    await tester.fling(onPage(find.byTooltip('Fila')), const Offset(0, -60), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPage), findsOneWidget, reason: 'flung, however short');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a drag up cut short, as the screen turns wide, leaves the lyrics hidden', (tester) async {
    await pumpBar(tester, server: withLyrics(verse));
    await openPlayer(tester);
    final finger = await tester.startGesture(tester.getCenter(playerCover));
    await finger.moveBy(const Offset(0, -20));
    await finger.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(onPage(find.byType(LyricsView)), findsOneWidget);
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(onPage(find.byType(LyricsView)), findsNothing);
    await finger.up();
    await tester.pumpAndSettle();
    expect(onPage(find.byType(LyricsView)), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a small phone, where the player with its lyrics is taller than the screen, a drag down scrolls it to '
      'its top, and from there on takes the lyrics out; the lyrics scroll as they do', (tester) async {
    await pumpBar(tester, server: withLyrics([for (var line = 0; line < 30; line++) (line * 5, 'Line $line')]));
    await openPlayer(tester);
    await tester.tap(onPage(find.byTooltip('Mostrar a letra')));
    await tester.pumpAndSettle();
    final top = onPage(find.byType(AppBar));
    final lyrics = onPage(find.byType(LyricsView));
    double shown() => tester.widget<Opacity>(find.ancestor(of: lyrics, matching: find.byType(Opacity)).first).opacity;
    // Where the cover is at the page's top, under its padding.
    final room = tester.getRect(onPage(find.byType(SingleChildScrollView)).first).top + 8;
    final hidden = room - tester.getRect(playerCover).top;
    expect(hidden, greaterThan(8), reason: 'the cover goes out at the top');

    await tester.drag(lyrics, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(shown(), 1, reason: 'the lyrics took it');
    expect(room - tester.getRect(playerCover).top, hidden);

    final finger = await tester.startGesture(tester.getCenter(onPage(find.text('Sweet Emotion'))));
    await finger.moveBy(const Offset(0, 20)); // past the slop, where the drag starts
    await finger.moveBy(Offset(0, hidden + 60));
    await tester.pump();
    expect(shown(), inExclusiveRange(0, 1), reason: 'on down from the top');
    expect(tester.getRect(playerCover).top, moreOrLessEquals(room), reason: 'the page at its top');
    expect(tester.getRect(top).top, 0, reason: 'the player where it opens');
    await finger.moveBy(const Offset(0, -150));
    await tester.pump();
    expect(shown(), 1, reason: 'back first');
    expect(tester.getRect(playerCover).top, lessThan(room), reason: 'then scrolled');
    // All the way out, though the page, the lyrics going, comes to fit the screen.
    await finger.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(lyrics, findsNothing);
    await finger.up();
    await tester.pumpAndSettle();
    expect(lyrics, findsNothing);
    expect(onPage(find.byTooltip('Mostrar a letra')), findsOneWidget);
    expect(tester.getRect(top).top, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone so short that the player is taller than the screen, a drag down scrolls it to its top, and '
      'from there on takes it down; a drag up, from its bottom, brings in the lyrics', (tester) async {
    await pumpBar(tester, server: withLyrics(verse), size: const Size(360, 420));
    await openPlayer(tester);
    final top = onPage(find.byType(AppBar));
    final title = onPage(find.text('Sweet Emotion'));
    // Where the cover is at the page's top, under its padding.
    final room = tester.getRect(onPage(find.byType(SingleChildScrollView)).first).top + 8;
    final hidden = room - tester.getRect(playerCover).top;
    expect(hidden, greaterThan(8), reason: 'the cover goes out at the top');

    final finger = await tester.startGesture(tester.getCenter(title));
    await finger.moveBy(const Offset(0, 20)); // past the slop, where the drag starts
    await finger.moveBy(Offset(0, hidden + 100));
    await tester.pump();
    expect(tester.getRect(top).top, moreOrLessEquals(100), reason: 'on down from the top');
    expect(tester.getRect(playerCover).top, room + 100);
    await finger.moveBy(const Offset(0, -150));
    await tester.pump();
    expect(tester.getRect(top).top, 0, reason: 'back up first');
    expect(tester.getRect(playerCover).top, room - 50, reason: 'then scrolled');
    await finger.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(tester.getRect(top).top, 250);
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);

    await openPlayer(tester);
    await tester.drag(title, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(onPage(find.byType(LyricsView)), findsOneWidget);
    expect(onPage(find.byTooltip('Esconder a letra')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a drag down cut short, as the screen turns wide, leaves the player where it opens, still at hand', (
    tester,
  ) async {
    await pumpBar(tester);
    await openPlayer(tester);
    final finger = await tester.startGesture(tester.getCenter(playerCover));
    await finger.moveBy(const Offset(0, 20));
    await finger.moveBy(const Offset(0, 150));
    await tester.pump();
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(tester.getRect(onPage(find.byType(AppBar))).top, 0);
    await finger.up();

    await tester.tap(onPage(find.byTooltip('Fechar')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, a drag down leaves the player be, and one up its lyrics', (tester) async {
    await pumpBar(tester, size: const Size(1280, 800));
    await openPlayer(tester);
    await tester.fling(playerCover, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(tester.getRect(onPage(find.byType(AppBar))).top, 0);
    await tester.fling(playerCover, const Offset(0, -300), 1000);
    await tester.pumpAndSettle();
    expect(onPage(find.byType(LyricsView)), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('its slider jumps to where it is tapped', (tester) async {
    final player = await pumpBar(tester);
    await openPlayer(tester);
    await tester.tap(onPage(find.byType(Slider)));
    await tester.pump();
    expect(player.position.inSeconds, closeTo(137, 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('it says where it plays, when that is another device', (tester) async {
    await pumpBar(
      tester,
      client: tvPlaying(const QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', album: 'Aerosmith')),
      size: const Size(1280, 800),
    );
    await openPlayer(tester);
    expect(inPlayer((widget) => widget is Text && widget.data == 'Tocando em Sala de estar'), findsOneWidget);
    expect(inPlayer((widget) => widget is Text && widget.data == 'Dream On'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, its devices button says that it plays on another device, tinted', (tester) async {
    Color? devicesColor() => tester
        .widget<ThemedIcon>(find.descendant(of: onPage(find.byTooltip('Aparelhos')), matching: find.byType(ThemedIcon)))
        .color;

    await pumpBar(tester);
    await openPlayer(tester);
    expect(devicesColor(), isNull, reason: 'it plays here');
    await tester.pumpWidget(const SizedBox());

    await pumpBar(
      tester,
      client: tvPlaying(const QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', album: 'Aerosmith')),
    );
    await openPlayer(tester);
    expect(onPage(find.textContaining('Sala de estar')), findsNothing, reason: 'no room at the top for where');
    expect(devicesColor(), Theme.of(tester.element(find.byType(PlayerPage))).colorScheme.primary);
    expect(onPage(find.text('Dream On')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the title opens the album, and the artist their page, in place of the player', (tester) async {
    await pumpBar(tester, server: library);
    await openPlayer(tester);
    await tester.tap(onPage(find.text('Sweet Emotion')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.descendant(of: find.byType(AlbumPage), matching: find.text('Toys in the Attic')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsNothing, reason: 'back goes where the player was opened from');
    expect(find.byType(PlayerPage), findsNothing);

    await openPlayer(tester);
    await tester.tap(onPage(find.text('Aerosmith')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.text('Get Your Wings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone\'s home, the player covers the bars at the bottom too; its links close it and open their page '
    'under them, in the home\'s page area',
    (tester) async {
      await pumpBar(tester, server: library, inHome: true);
      final sections = find.byType(NavigationBar);
      await openPlayer(tester);
      expect(sections.hitTestable(), findsNothing);

      await tester.tap(onPage(find.text('Sweet Emotion')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(AlbumPage), findsOneWidget);
      expect(sections.hitTestable(), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumPage), findsNothing);

      // The queue opens over the player, out of the page area too.
      await openPlayer(tester);
      await tester.tap(onPage(find.byTooltip('Fila')));
      await tester.pumpAndSettle();
      expect(find.byType(QueuePage), findsOneWidget);
      expect(sections.hitTestable(), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the album\'s name opens it too, at the top on a phone', (tester) async {
    await pumpBar(tester, server: library);
    await openPlayer(tester);
    await tester.tap(find.descendant(of: onPage(find.byType(AppBar)), matching: find.text('Toys in the Attic')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.descendant(of: find.byType(AlbumPage), matching: find.text('Toys in the Attic')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('another device\'s song links too, each of its artists, whose page is named after them', (tester) async {
    await pumpBar(
      tester,
      client: tvPlaying(const QueueItem(id: 's2', title: 'Walk This Way', artist: 'Run-DMC; Aerosmith')),
      server: library,
    );
    await openPlayer(tester);
    expect(onPage(find.byTooltip('Abrir o artista')), findsNWidgets(2), reason: 'the media server says who they are');
    await tester.tap(onPage(find.text('Run-DMC')));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsOneWidget);
    // On the page itself, not in its bar, where it comes as it scrolls.
    expect(find.descendant(of: find.byType(AlbumGrid), matching: find.text('Run-DMC')), findsOneWidget);
    expect(find.text('Raising Hell'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await openPlayer(tester);
    await tester.tap(onPage(find.text('Aerosmith')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AlbumGrid), matching: find.text('Aerosmith')), findsOneWidget);
    expect(find.text('Get Your Wings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the song that plays here links each of its artists, without asking the server who they are', (
    tester,
  ) async {
    final asked = <http.Request>[];
    await pumpBar(
      tester,
      song: const Song(
        id: 's2',
        title: 'Walk This Way',
        artist: 'Run-DMC; Aerosmith',
        album: 'Raising Hell',
        albumId: 'a2',
        artists: [
          Artist(id: 'ar2', name: 'Run-DMC'),
          Artist(id: 'ar1', name: 'Aerosmith'),
        ],
      ),
      server: (request) {
        asked.add(request);
        return library(request);
      },
      size: const Size(1000, 600),
    );
    expect(find.byTooltip('Abrir o artista'), findsNWidgets(2), reason: 'in the bar');
    await tester.tap(find.text('Aerosmith'));
    await tester.pumpAndSettle();
    expect(tester.widget<ArtistPage>(find.byType(ArtistPage)).artist.id, 'ar1');
    expect(asked.where((request) => request.url.path.endsWith('getSong.view')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song the server can\'t find opens nothing, and says so', (tester) async {
    await pumpBar(tester);
    await openPlayer(tester);
    await tester.tap(onPage(find.text('Sweet Emotion')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(AlbumPage), findsNothing);
    expect(find.textContaining('Não consegui abrir o álbum'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song the hub couldn\'t give in this device\'s API links nowhere', (tester) async {
    final asked = <http.Request>[];
    await pumpBar(
      tester,
      client: tvPlaying(const QueueItem(title: 'Dream On', artist: 'Aerosmith')),
      server: (request) {
        asked.add(request);
        return library(request);
      },
    );
    await openPlayer(tester);
    await tester.tap(onPage(find.text('Dream On')), warnIfMissed: false);
    await tester.tap(onPage(find.text('Aerosmith')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(asked.where((request) => request.url.path.endsWith('getSong.view')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wide bar links too: the title to the album, the artist to their page; the rest opens the player', (
    tester,
  ) async {
    await pumpBar(tester, server: library, size: const Size(1000, 600));
    await tester.tap(find.byTooltip('Abrir o álbum'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.descendant(of: find.byType(AlbumPage), matching: find.text('Toys in the Attic')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Abrir o artista'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.text('Get Your Wings'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsNothing);

    await openPlayer(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(
      playerTip('Abrir o álbum'),
      findsNWidgets(2),
      reason: 'the player\'s links say where they go: its title and its album\'s name open the album',
    );
    expect(playerTip('Abrir o artista'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the whole song in the bar opens the player, its title and artist included', (tester) async {
    await pumpBar(tester, server: library);
    expect(find.byTooltip('Abrir o álbum'), findsNothing);
    expect(find.byTooltip('Abrir o artista'), findsNothing);
    await tester.tap(find.text('Aerosmith'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(ArtistPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the bar parts several artists by commas, where the media server has semicolons', (
    tester,
  ) async {
    await pumpBar(
      tester,
      song: const Song(id: 's2', title: 'Walk This Way', artist: 'Run-DMC; Aerosmith', album: 'Raising Hell'),
    );
    expect(find.text('Run-DMC, Aerosmith'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a link is underlined under the mouse', (tester) async {
    await pumpBar(tester, server: library, size: const Size(1000, 600));
    TextDecoration? decoration() => tester.widget<Text>(find.text('Aerosmith')).style?.decoration;

    expect(decoration(), isNot(TextDecoration.underline));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Aerosmith')));
    await tester.pump();
    expect(decoration(), TextDecoration.underline);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(decoration(), isNot(TextDecoration.underline));
    await tester.pumpWidget(const SizedBox());
  });
}
