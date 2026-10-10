import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/downloads/downloads.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/server/server.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/download_button.dart';
import 'package:segue/ui/downloads_page.dart';
import 'package:segue/ui/playlists_view.dart';
import 'package:segue/ui/spinner.dart';

import 'fakes.dart';

const album = Album(id: 'al1', name: 'Toys in the Attic', artist: 'Aerosmith', coverArt: 'al1');

const songs = [
  Song(id: 's1', title: 'Walk This Way', coverArt: 'al1', duration: Duration(minutes: 3)),
  Song(id: 's2', title: 'Sweet Emotion', coverArt: 'al1', duration: Duration(minutes: 4)),
];

/// [child] with the services of a session on [server], with [downloads], in Portuguese.
Future<void> pumpWith(WidgetTester tester, FileServer server, Downloads? downloads, Widget child) async {
  final player = PlayerController(FakeEngine(), server.api);
  final services = Services(
    Session(
      server: Uri.parse('https://music.test'),
      credentials: const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
      deviceId: 'me',
      deviceName: 'me',
    ),
    server.api,
    player,
    ConnectController(player: player),
    downloads: downloads,
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, page) => ServicesScope(services: services, child: page!),
      home: Scaffold(body: child),
    ),
  );
}

/// Lets the downloads write and read their files, which they do outside the test's fake time, until [done].
Future<void> until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }

  expect(done(), isTrue);
}

void main() {
  late Directory directory;
  late FileServer server;
  late Downloads downloads;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('segue-download-button');
    server = FileServer();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    downloads = (await tester.runAsync(() => Downloads.open(directory, server.api, client: server.client)))!;
    addTearDown(downloads.dispose);
  }

  bool progressIs(int done, int failed) {
    final download = downloads.ofAlbum('al1');
    return download != null && downloads.progressOf(download) == (done: done, failed: failed, total: 2);
  }

  testWidgets('an album downloads from its button, which shows how far it has got, then that it is there', (
    tester,
  ) async {
    await open(tester);
    final second = server.held['s2'] = Completer<void>();
    await pumpWith(tester, server, downloads, const Center(child: DownloadButton.album(album, songs)));
    expect(find.byTooltip('Baixar'), findsOneWidget);

    await tester.tap(find.byTooltip('Baixar'));
    await until(tester, () => progressIs(1, 0));
    expect(find.byTooltip('Baixando: 1 de 2 faixas'), findsOneWidget);
    expect(tester.widget<ProgressRing>(find.byType(ProgressRing)).value, 0.5);

    second.complete();
    await until(tester, () => progressIs(2, 0));
    await tester.pump();
    expect(find.byTooltip('Baixado: toca sem o servidor'), findsOneWidget);
  });

  testWidgets('a downloaded album asks before going off the device', (tester) async {
    await open(tester);
    await tester.runAsync(() => downloads.addAlbum(album, songs));
    await pumpWith(tester, server, downloads, const Center(child: DownloadButton.album(album, songs)));
    await until(tester, () => progressIs(2, 0));
    await tester.tap(find.byTooltip('Baixado: toca sem o servidor'));
    await tester.pumpAndSettle();
    expect(find.text('Remover “Toys in the Attic” do aparelho?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(downloads.ofAlbum('al1'), isNotNull);

    await tester.tap(find.byTooltip('Baixado: toca sem o servidor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover'));
    await until(tester, () => downloads.ofAlbum('al1') == null && downloads.songFile('s1') == null);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Baixar'), findsOneWidget);
  });

  testWidgets('songs that failed to come are tried again from the button', (tester) async {
    await open(tester);
    server.failing.add('s2');
    await pumpWith(tester, server, downloads, const Center(child: DownloadButton.album(album, songs)));
    await tester.tap(find.byTooltip('Baixar'));
    await until(tester, () => progressIs(1, 1));
    expect(find.byTooltip('1 faixa não baixou: tentar de novo'), findsOneWidget);

    server.failing.clear();
    await tester.tap(find.byTooltip('1 faixa não baixou: tentar de novo'));
    await until(tester, () => progressIs(2, 0));
  });

  testWidgets('where the app downloads nothing, there is no button', (tester) async {
    await pumpWith(tester, server, null, const Center(child: DownloadButton.album(album, songs)));
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('the downloads\' page lists them, the latest first, under the room they take', (tester) async {
    await open(tester);
    await tester.runAsync(() async {
      await downloads.addAlbum(album, songs);
      await downloads.addPlaylist(const Playlist(id: 'p1', name: 'Road trip'), songs.take(1).toList());
    });
    await pumpWith(tester, server, downloads, const DownloadsPage());
    await until(tester, () => progressIs(2, 0) && find.textContaining('no aparelho').evaluate().isNotEmpty);
    final names = [
      for (final title in find.byType(ListTile).evaluate()) ((title.widget as ListTile).title! as Text).data,
    ];
    expect(names, ['Road trip', 'Toys in the Attic']);
    expect(find.text('0 MB no aparelho'), findsOneWidget);
    expect(find.text('2 faixas, 7 min'), findsOneWidget);
  });

  testWidgets('the albums tab\'s "Baixados" shows the downloaded albums alone, as they come and go', (tester) async {
    await open(tester);
    await tester.runAsync(() => downloads.addAlbum(album, songs));
    var downloaded = true;
    AlbumOrder? picked;
    await pumpWith(
      tester,
      server,
      downloads,
      StatefulBuilder(
        builder: (context, setState) => AlbumsView(
          order: AlbumOrder.name,
          downloaded: downloaded,
          onOrder: (order) => setState(() {
            picked = order;
            downloaded = false;
          }),
          onDownloaded: () => setState(() => downloaded = true),
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Baixados')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Nome')).selected, isFalse);
    expect(find.text('Toys in the Attic'), findsOneWidget);

    await tester.runAsync(() => downloads.addAlbum(const Album(id: 'al2', name: 'Rocks'), songs.take(1).toList()));
    await tester.pump();
    expect(find.text('Rocks'), findsOneWidget);
    await tester.runAsync(() => downloads.remove(downloads.ofAlbum('al1')!));
    await tester.pump();
    expect(find.text('Toys in the Attic'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Nome'));
    await tester.pump();
    expect(picked, AlbumOrder.name);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Baixados')).selected, isFalse);
  });

  testWidgets('the playlists tab\'s "Baixadas" shows the downloaded playlists alone', (tester) async {
    await open(tester);
    await tester.runAsync(() => downloads.addPlaylist(const Playlist(id: 'p1', name: 'Road trip'), songs));
    await pumpWith(tester, server, downloads, const PlaylistsView());
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Todas')).selected, isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Baixadas'));
    await tester.pump();
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('Nova playlist'), findsNothing);

    await tester.runAsync(() => downloads.remove(downloads.ofPlaylist('p1')!));
    await tester.pump();
    expect(find.text('Road trip'), findsNothing);
    expect(find.textContaining('Nada baixado'), findsOneWidget);
  });

  testWidgets('where the app downloads nothing, the tabs have no such chips', (tester) async {
    await pumpWith(tester, server, null, const PlaylistsView());
    await tester.pump();
    expect(find.byType(ChoiceChip), findsNothing);
    await pumpWith(tester, server, null, AlbumsView(onOrder: (_) {}, onDownloaded: () {}));
    await tester.pump();
    expect(find.widgetWithText(ChoiceChip, 'Baixados'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Nome'), findsOneWidget);
  });
}
