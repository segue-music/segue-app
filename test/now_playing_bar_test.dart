import 'package:flutter/material.dart';
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
import 'package:segue/ui/player/now_playing_bar.dart';
import 'package:segue/ui/widgets/cover.dart';
import 'package:segue/ui/widgets/themed_icon.dart';

import 'fakes.dart';
import 'player_page_test.dart' show pumpBar, tvPlaying;

void main() {
  for (final (screen, size) in [('a wide screen', const Size(960, 540)), ('a phone', const Size(360, 640))]) {
    testWidgets('on $screen, the bar\'s cover is as tall as the title and the artist beside it, and no button taller', (
      tester,
    ) async {
      await pumpBar(tester, size: size);
      final bar = find.byType(NowPlayingBar);
      final cover = tester.getRect(find.descendant(of: bar, matching: find.byType(Cover)));
      final title = tester.getRect(find.descendant(of: bar, matching: find.text('Sweet Emotion')));
      final artist = tester.getRect(find.descendant(of: bar, matching: find.text('Aerosmith')));
      expect(cover.height, moreOrLessEquals(artist.bottom - title.top, epsilon: 1));
      expect(cover.center.dy, moreOrLessEquals((title.top + artist.bottom) / 2, epsilon: 1));

      for (final button in tester.widgetList<IconButton>(find.descendant(of: bar, matching: find.byType(IconButton)))) {
        expect(
          tester.getSize(find.byWidget(button)).height,
          lessThanOrEqualTo(cover.height + 1),
          reason: button.tooltip,
        );
      }

      await tester.pumpWidget(const SizedBox()); // stops the bar's timer
    });
  }

  testWidgets('on a wide screen, the playback\'s buttons are in the middle, play filled, between the heart and the '
      'lyrics, over the slider; a playlist to add the song to, the queue and the devices are at the end', (
    tester,
  ) async {
    await pumpBar(tester, size: const Size(1280, 700));
    final bar = find.byType(NowPlayingBar);
    Rect rect(Finder finder) => tester.getRect(find.descendant(of: bar, matching: finder));
    final play = rect(find.byTooltip('Tocar'));

    // In the middle, but for the bar's edges: the song's own room inside takes some from its side.
    expect(play.center.dx, moreOrLessEquals(640, epsilon: 2));
    // Its button's, around the icon and the tooltip.
    final playButton = find.ancestor(
      of: find.descendant(of: bar, matching: find.byTooltip('Tocar')),
      matching: find.byType(Material),
    );
    expect(
      tester.widget<Material>(playButton.first).color,
      Theme.of(tester.element(bar)).colorScheme.primary,
      reason: 'filled',
    );

    final buttons = [
      for (final tooltip in [
        'Adicionar aos favoritos',
        'Ativar aleatório',
        'Anterior',
        'Próxima',
        'Repetir a lista',
        'Mostrar a letra',
      ])
        rect(find.byTooltip(tooltip)),
    ];
    expect(play.center.dx - buttons.first.center.dx, moreOrLessEquals(buttons.last.center.dx - play.center.dx));
    final slider = rect(find.byType(Slider));
    expect(slider.center.dx, moreOrLessEquals(640, epsilon: 2));

    for (final button in [play, ...buttons]) {
      expect(button.center.dy, moreOrLessEquals(play.center.dy, epsilon: 1));
      expect(button.bottom, lessThanOrEqualTo(slider.top + 1));
      expect(button.left, greaterThanOrEqualTo(slider.left - 40));
      expect(button.right, lessThanOrEqualTo(slider.right + 40));
    }

    expect(slider.bottom, lessThanOrEqualTo(tester.getRect(bar).bottom - 8), reason: 'room under it');

    for (final tooltip in ['Adicionar à playlist', 'Fila', 'Aparelhos']) {
      expect(rect(find.byTooltip(tooltip)).left, greaterThan(slider.right), reason: tooltip);
    }

    expect(rect(find.byTooltip('Aparelhos')).right, moreOrLessEquals(1280 - 8, epsilon: 1));
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('at 960 wide, the narrowest a computer\'s window gets, the middle buttons\' icons are over the seek bar, '
      'none past its ends', (tester) async {
    // The runners keep the window no narrower (linux/runner/my_application.cc, macos/Runner/MainFlutterWindow.swift,
    // windows/runner/win32_window.cpp): with another layout, another width there.
    await pumpBar(tester, size: const Size(960, 700));
    final bar = find.byType(NowPlayingBar);
    Rect icon(String tooltip) => tester.getRect(
      find.descendant(
        of: find.descendant(of: bar, matching: find.byTooltip(tooltip)),
        matching: find.byType(ThemedIcon),
      ),
    );
    // Where its track goes, inside the slider's room around it.
    final track = tester.getRect(find.descendant(of: bar, matching: find.byType(Slider))).deflate(14);
    expect(icon('Adicionar aos favoritos').left, greaterThanOrEqualTo(track.left - 1));
    expect(icon('Mostrar a letra').right, lessThanOrEqualTo(track.right + 1));
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a phone, the bar is slightly see-through, its corners slightly rounded; on a wide screen, opaque and '
      'square', (tester) async {
    Material material() =>
        tester.widget<Material>(find.descendant(of: find.byType(NowPlayingBar), matching: find.byType(Material)).first);

    await pumpBar(tester, size: const Size(360, 640));
    expect(material().color?.a, NowPlayingBar.phoneOpacity);
    expect(material().shape, RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)));
    await pumpBar(tester, size: const Size(960, 540));
    expect(material().color?.a, 1);
    expect(material().shape, isNull);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a phone, the song in the bar has room around its cover and lines, where its tint and ring show', (
    tester,
  ) async {
    await pumpBar(tester);
    final bar = find.byType(NowPlayingBar);
    final cover = tester.getRect(find.descendant(of: bar, matching: find.byType(Cover)));
    final song = tester.getRect(find.descendant(of: bar, matching: find.byTooltip('Abrir o player')));
    expect(cover.left - song.left, moreOrLessEquals(4));
    expect(cover.top - song.top, moreOrLessEquals(4));
    expect(song.bottom - cover.bottom, moreOrLessEquals(4));
    expect(song.right, greaterThan(tester.getRect(find.descendant(of: bar, matching: find.text('Aerosmith'))).right));
    expect(cover.left, moreOrLessEquals(8), reason: 'where it was, the room taken from the bar\'s edge');
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a wide screen, only the cover opens the player, nothing around the song lighting up for it', (
    tester,
  ) async {
    await pumpBar(tester, size: const Size(960, 540));
    final bar = find.byType(NowPlayingBar);
    final cover = tester.getRect(find.descendant(of: bar, matching: find.byType(Cover)));
    expect(tester.getRect(find.descendant(of: bar, matching: find.byTooltip('Abrir o player'))), cover);
    expect(cover.left, moreOrLessEquals(8));
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a phone-sized screen, the bar shows what plays on another device, its devices button tinted', (
    tester,
  ) async {
    const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final player = PlayerController(FakeEngine(), api);
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
        capabilities: [],
      ),
      online: true,
      state: StampedState(
        status: PlaybackStatus.playing,
        positionMs: 61000,
        at: DateTime.now().millisecondsSinceEpoch,
        index: 0,
        queue: const [QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', durationMs: 268000)],
      ),
    );
    final connect = ConnectController(player: player, client: client);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    client.notifyListeners(); // as when the TV's state arrives
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      connect,
    );

    // The screen itself, not just the surface: the bar picks what fits from MediaQuery.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: ServicesScope(
          services: services,
          child: const Scaffold(bottomNavigationBar: NowPlayingBar()),
        ),
      ),
    );
    expect(find.text('Dream On'), findsOneWidget);
    expect(find.text('Aerosmith'), findsOneWidget);
    expect(find.textContaining('Sala de estar'), findsNothing, reason: 'no strip under the bar saying where');
    expect(
      tester
          .widget<ThemedIcon>(find.descendant(of: find.byTooltip('Aparelhos'), matching: find.byType(ThemedIcon)))
          .color,
      Theme.of(tester.element(find.byType(NowPlayingBar))).colorScheme.primary,
    );
    expect(find.text('1:01'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a wide screen, a strip under the bar says where it plays, when that is another device', (
    tester,
  ) async {
    await pumpBar(tester, size: const Size(960, 540));
    expect(find.textContaining('Tocando em'), findsNothing, reason: 'it plays here');
    await tester.pumpWidget(const SizedBox());

    await pumpBar(
      tester,
      client: tvPlaying(const QueueItem(id: 's1', title: 'Dream On', artist: 'Aerosmith', album: 'Aerosmith')),
      size: const Size(960, 540),
    );
    expect(find.text('Tocando em Sala de estar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the slider jumps to where it is tapped, or to where a drag lets go', (tester) async {
    const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final player = PlayerController(FakeEngine(), api);
    await player.playQueue(const [
      Song(id: 's1', title: 'Dream On', artist: 'Aerosmith', duration: Duration(seconds: 268)),
    ], play: false);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
    );
    // The screen itself, not just the surface: the bar picks what fits from MediaQuery.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: ServicesScope(
          services: services,
          child: const Scaffold(bottomNavigationBar: NowPlayingBar()),
        ),
      ),
    );

    await tester.tap(find.byType(Slider)); // its middle
    await tester.pump();
    expect(player.position.inSeconds, closeTo(134, 3));
    expect(find.text(formatDuration(player.position)), findsOneWidget);

    // While dragging, the time shows where it would go, and nothing moves until it lets go.
    final slider = tester.getRect(find.byType(Slider));
    final drag = await tester.startGesture(Offset(slider.left + 14 + 4, slider.center.dy));
    await tester.pump();
    await drag.moveTo(Offset(slider.left + 14 + (slider.width - 28) * 0.75, slider.center.dy));
    await tester.pump();
    expect(player.position.inSeconds, closeTo(134, 3));
    expect(find.text('3:21'), findsOneWidget);
    await drag.up();
    await tester.pump();
    expect(player.position.inSeconds, closeTo(201, 3));
    await tester.pumpWidget(const SizedBox()); // stops the bar's timers
  });

  testWidgets('shuffle and repeat buttons, on a wide screen: shuffle toggles, repeat goes off, list, track', (
    tester,
  ) async {
    const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final player = PlayerController(FakeEngine(), api);
    await player.playQueue(const [
      Song(id: 's1', title: 'Dream On', duration: Duration(seconds: 268)),
      Song(id: 's2', title: 'Other', duration: Duration(seconds: 200)),
    ], play: false);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
    );

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('pt')],
          home: ServicesScope(
            services: services,
            child: const Scaffold(bottomNavigationBar: NowPlayingBar()),
          ),
        ),
      );
    }

    addTearDown(tester.view.reset);
    await pumpAt(const Size(1000, 600));
    await tester.tap(find.byTooltip('Ativar aleatório'));
    await tester.pump();
    expect(player.shuffle, isTrue);
    expect(find.byTooltip('Desativar aleatório'), findsOneWidget);

    await tester.tap(find.byTooltip('Repetir a lista'));
    await tester.pump();
    expect(player.repeat, Repeat.all);
    await tester.tap(find.byTooltip('Repetir a faixa'));
    await tester.pump();
    expect(player.repeat, Repeat.one);
    await tester.tap(find.byTooltip('Não repetir'));
    await tester.pump();
    expect(player.repeat, Repeat.off);

    // No room for them in a phone-sized bar.
    await pumpAt(const Size(360, 640));
    expect(find.byTooltip('Ativar aleatório'), findsNothing);
    expect(find.byTooltip('Repetir a lista'), findsNothing);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timers
  });
}
