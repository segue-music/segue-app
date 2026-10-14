import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/jellyfin/api.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/server/server.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/app/television_screen.dart';
import 'package:segue/ui/playlist/playlist_menu.dart';
import 'package:segue/ui/song/song_menu.dart';
import 'package:segue/ui/widgets/share_link.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'fakes.dart';

/// What shares out of the app, as share_plus asks the platform.
class FakeShare extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('', ShareResultStatus.success);
  }
}

const credentials = SubsonicCredentials(username: 'alice', token: 't', salt: 's');
const song = Song(id: 's1', title: 'Walk This Way', artist: 'Aerosmith');
const playlist = Playlist(id: 'p1', name: 'Road trip');

http.Response _ok(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  // SharePlus takes the platform's share as it is first asked for: this one, for every test here.
  final share = FakeShare();

  SharePlatform.instance = share;

  // The ids createShare was asked for, and what went to the clipboard.
  late List<String> shared;
  String? copied;

  setUp(() {
    share.shared.clear();
    shared = [];
    copied = null;
  });

  /// A Subsonic server that makes links to its items with [address] (`<address>/share/<id>`), where the user may share
  /// ([shareRole]).
  SubsonicApi server({String address = 'https://music.example', bool shareRole = true}) => SubsonicApi(
    Uri.parse('https://music.example'),
    credentials,
    client: MockClient((request) async {
      final id = request.url.queryParameters['id'];

      switch (request.url.pathSegments.last) {
        case 'getUser.view':
          return _ok({
            'user': {'username': 'alice', 'shareRole': shareRole},
          });
        case 'createShare.view':
          shared.add(id!);
          return _ok({
            'shares': {
              'share': [
                {'id': 'sh1', 'url': '$address/share/$id'},
              ],
            },
          });
      }

      return http.Response('', 404);
    }),
  );

  /// [home] with the app given [api], on [platform], with the remote where [television], on a TV's screen (960 by
  /// 540); the clipboard noted in [copied].
  Future<void> pump(
    WidgetTester tester,
    MediaServer api, {
    Widget home = const _SongLine(),
    TargetPlatform platform = TargetPlatform.linux,
    bool television = false,
  }) async {
    final player = PlayerController(FakeEngine(), api);
    final services = Services(
      Session(server: Uri.parse('https://music.example'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
    );
    final messenger = tester.binding.defaultBinaryMessenger;

    if (television) {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }

      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => ServicesScope(
          services: services,
          child: TelevisionScreen(enabled: television, child: child!),
        ),
        home: Scaffold(body: home),
      ),
    );
  }

  Future<void> shareSong(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
  }

  testWidgets('on a computer, a song\'s menu copies a public link to it, which the server makes, and says so', (
    tester,
  ) async {
    await pump(tester, server());
    await shareSong(tester);
    expect(shared, ['s1']);
    expect(copied, 'https://music.example/share/s1');
    expect(find.text('Link copiado'), findsOneWidget);
    expect(share.shared, isEmpty);
  });

  testWidgets('on a phone, the link goes to the system\'s share sheet', (tester) async {
    await pump(tester, server(), platform: TargetPlatform.android);
    await shareSong(tester);
    expect(share.shared.single.uri, Uri.parse('https://music.example/share/s1'));
    expect(copied, isNull);
  });

  testWidgets('a link with an address of the server\'s own network asks first: cancelled, it goes nowhere; asked '
      'again, it goes', (tester) async {
    await pump(tester, server(address: 'http://192.168.0.10:4533'));
    await shareSong(tester);
    expect(find.text('Link da rede local'), findsOneWidget);
    expect(find.textContaining('192.168.0.10, que só abre na rede dele'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(copied, isNull);
    expect(find.text('Link copiado'), findsNothing);

    await shareSong(tester);
    await tester.tap(find.text('Copiar o link'));
    await tester.pumpAndSettle();
    expect(copied, 'http://192.168.0.10:4533/share/s1');
  });

  testWidgets('on a TV, the link shows as a QR code, the link under it, and where it opens only on the server\'s '
      'network, that too', (tester) async {
    await pump(tester, server(address: 'http://192.168.0.10:4533'), platform: TargetPlatform.android, television: true);
    await shareSong(tester);
    expect(find.text('Link público'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('http://192.168.0.10:4533/share/s1'), findsOneWidget);
    expect(find.textContaining('que só abre na rede dele'), findsOneWidget);
    expect(share.shared, isEmpty, reason: 'a TV\'s share sheet has nowhere to send it');
    expect(copied, isNull);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('a server that makes no links for the user says so', (tester) async {
    await pump(tester, server(shareRole: false));
    await shareSong(tester);
    expect(find.text('Este servidor não cria links públicos.'), findsOneWidget);
    expect(shared, isEmpty);
    expect(copied, isNull);
  });

  testWidgets('on Jellyfin, which makes no public links, a song\'s menu has no item for them', (tester) async {
    final api = JellyfinApi(
      Uri.parse('https://music.example'),
      const JellyfinCredentials(username: 'alice', userId: 'u1', token: 'tok'),
      deviceId: 'me',
      deviceName: 'me',
      client: MockClient((_) async => http.Response('', 404)),
    );

    await pump(tester, api);
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    expect(find.text('Rádio da música'), findsOneWidget);
    expect(find.text('Compartilhar'), findsNothing);
  });

  testWidgets('a playlist\'s menu shares the playlist\'s link, and an artist\'s button theirs', (tester) async {
    await pump(
      tester,
      server(),
      home: Builder(
        builder: (context) => Row(
          children: [
            PopupMenuButton<PlaylistAction>(
              tooltip: 'Mais opções',
              itemBuilder: (context) => playlistMenuItems(context, playlist, hasSongs: false),
              onSelected: (action) => runPlaylistAction(context, playlist, action),
            ),
            const ShareButton('ar1'),
          ],
        ),
      ),
    );
    await shareSong(tester);
    expect(copied, 'https://music.example/share/p1');

    await tester.tap(find.byType(ShareButton));
    await tester.pumpAndSettle();
    expect(shared, ['p1', 'ar1']);
    expect(copied, 'https://music.example/share/ar1');
  });

  test('a link opens only on the server\'s network where its host is a private address or a local name', () {
    for (final address in [
      'http://192.168.0.10:4533',
      'http://10.0.0.2',
      'http://172.20.1.1',
      'http://100.101.102.103',
      'http://127.0.0.1:4533',
      'http://169.254.1.1',
      'http://[fd12:3456::1]:4533',
      'http://[fe80::1]',
      'http://[::1]',
      'http://navidrome:4533',
      'http://music.local',
      'http://music.lan',
      'http://music.home.arpa',
      'http://music.internal',
    ]) {
      expect(isLocalLink(Uri.parse('$address/share/x')), isTrue, reason: address);
    }

    for (final address in [
      'https://music.example',
      'https://203.0.113.5',
      'http://172.32.0.1',
      'http://100.128.0.1',
      'http://[2001:db8::1]',
      'https://music.tail1234.ts.net',
    ]) {
      expect(isLocalLink(Uri.parse('$address/share/x')), isFalse, reason: address);
    }
  });
}

/// A song's line, with its menu.
class _SongLine extends StatelessWidget {
  const _SongLine();

  @override
  Widget build(BuildContext context) => SongMenu(
    song,
    builder: (context, button) => ListTile(title: Text(song.title), trailing: button),
  );
}
