import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/log_file.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/settings/log_tile.dart';
import 'package:segue/ui/settings/settings_page.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';
import 'themed_icons.dart';

/// What shares out of the app, as share_plus asks the platform: it notes what, and fails with [failure] where there is
/// one.
class FakeShare extends SharePlatform {
  final shared = <ShareParams>[];
  Object? failure;

  @override
  Future<ShareResult> share(ShareParams params) async {
    final failure = this.failure;

    shared.add(params);

    if (failure != null) {
      throw failure;
    }

    return const ShareResult('', ShareResultStatus.dismissed);
  }
}

const detail = 'O que deu errado no app. Tem o endereço do servidor e o seu usuário, mas nenhuma senha.';

void main() {
  // SharePlus takes the platform's share as it is first asked for: this one, for every test here.
  final share = FakeShare();

  SharePlatform.instance = share;

  late Directory directory;
  late LogFile log;
  late FakeUrlLauncher launcher;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('segue-log');
    // Three lines to a file: four make the one before and the one now.
    log = await LogFile.open(directory, limit: 200);

    for (var i = 0; i < 4; i++) {
      log.write(LogRecord(Level.INFO, 'line $i of the log', 'Segue'));
    }

    share
      ..shared.clear()
      ..failure = null;
    launcher = FakeUrlLauncher();

    final previous = UrlLauncherPlatform.instance;

    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
  });
  tearDown(() async {
    await log.close();
    directory.deleteSync(recursive: true);
  });

  /// The line alone, as on [platform].
  Future<void> pumpTile(WidgetTester tester, TargetPlatform platform) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      home: Scaffold(
        body: ListView(children: [LogTile(log, deviceName: 'Sala de estar')]),
      ),
    ),
  );

  /// Taps [line], and waits, in real time, for what it reads from the files and shares.
  Future<void> tapAndShare(WidgetTester tester, Finder line) async {
    await tester.runAsync(() async {
      await tester.tap(line);

      while (share.shared.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // What comes of it.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
  }

  testWidgets('on a phone, the line shares the log as one file, the one before first, named for the device and the '
      'time, its sheet coming out of the line', (tester) async {
    await pumpTile(tester, TargetPlatform.android);

    final line = find.widgetWithText(ListTile, 'Compartilhar o log');

    expect(find.descendant(of: line, matching: find.text(detail)), findsOneWidget);
    expect(find.descendant(of: line, matching: themedIcon(HugeIcons.strokeRoundedFileExport)), findsOneWidget);

    await tapAndShare(tester, line);

    final ShareParams(:files, :fileNameOverrides, :sharePositionOrigin) = share.shared.single;
    final text = utf8.decode(await files!.single.readAsBytes());

    expect(files.single.mimeType, 'text/plain');
    expect(fileNameOverrides, [matches(r'^segue-log-sala-de-estar-\d{4}-\d\d-\d\d-\d{4}\.txt$')]);
    expect(text.split('\n'), [for (var i = 0; i < 4; i++) endsWith('Segue: line $i of the log'), '']);
    expect(sharePositionOrigin, tester.getRect(line));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a share that fails says so', (tester) async {
    share.failure = Exception('no share sheet');
    await pumpTile(tester, TargetPlatform.iOS);
    await tapAndShare(tester, find.text('Compartilhar o log'));
    expect(find.text('Não deu para abrir o log.'), findsOneWidget);
  });

  testWidgets('on a computer, the line opens the log\'s folder', (tester) async {
    await pumpTile(tester, TargetPlatform.linux);

    final line = find.widgetWithText(ListTile, 'Abrir a pasta do log');

    expect(find.descendant(of: line, matching: find.text(detail)), findsOneWidget);
    expect(find.descendant(of: line, matching: themedIcon(HugeIcons.strokeRoundedFolderOpen)), findsOneWidget);

    await tester.tap(line);
    await tester.pump();
    expect(launcher.launched, [Uri.directory(directory.path).toString()]);
    expect(share.shared, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a folder that doesn\'t open says so', (tester) async {
    launcher.opens = (_) => false;
    await pumpTile(tester, TargetPlatform.windows);
    await tester.tap(find.text('Abrir a pasta do log'));
    await tester.pump();
    expect(find.text('Não deu para abrir o log.'), findsOneWidget);
  });

  testWidgets('the settings have the log\'s line after the version, but not on a TV, nor with no log', (tester) async {
    const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final player = PlayerController(FakeEngine(), api);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
    );

    // A window tall enough for every line of the settings.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pump({LogFile? log, bool television = false}) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(navigationMode: television ? NavigationMode.directional : NavigationMode.traditional),
          child: ServicesScope(services: services, child: child!),
        ),
        home: SettingsPage(
          onSignOut: () {},
          packageInfo: PackageInfo(appName: 'Segue', packageName: 'segue', version: '1.0.0', buildNumber: '1'),
          log: log,
        ),
      ),
    );

    await pump(log: log);

    final version = tester.getRect(find.text('Versão'));
    final line = tester.getRect(find.byType(LogTile));
    final licenses = tester.getRect(find.text('Licenças de código aberto'));

    expect(line.top, greaterThan(version.bottom));
    expect(licenses.top, greaterThan(line.bottom));

    await pump(log: log, television: true);
    expect(find.byType(LogTile), findsNothing);

    await pump();
    expect(find.byType(LogTile), findsNothing);
  });

  test('the shared log\'s name has the device\'s words and the time', () {
    final time = DateTime(2026, 10, 14, 9, 5);

    expect(logName('Sala de Estar (TV)', time), 'segue-log-sala-de-estar-tv-2026-10-14-0905.txt');
    expect(logName('Télé du salon', time), 'segue-log-télé-du-salon-2026-10-14-0905.txt');
    expect(logName('', time), 'segue-log-2026-10-14-0905.txt');
  });
}
