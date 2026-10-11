import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/player/failed_song_message.dart';

import 'fakes.dart';

void main() {
  testWidgets('a song this device\'s player couldn\'t load is told of, each time', (tester) async {
    const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final engine = FakeEngine();
    final player = PlayerController(engine, api);
    await player.playQueue(const [
      Song(id: 's1', title: 'Walk This Way', artist: 'Aerosmith'),
      Song(id: 's2', title: 'Sweet Emotion', artist: 'Aerosmith'),
    ]);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => ServicesScope(
          services: services,
          child: FailedSongMessage(child: child!),
        ),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await player.next();
    await tester.pumpAndSettle();
    expect(find.textContaining('Não consegui tocar'), findsNothing, reason: 'nothing failed yet');

    engine.fail();
    await tester.pump();
    expect(find.text('Não consegui tocar “Sweet Emotion”.'), findsOneWidget);
    await tester.pumpAndSettle(); // the snack bar comes in, then goes away 4 s later
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não consegui tocar'), findsNothing);

    // Tried again, it fails again.
    await player.play();
    engine.fail();
    await tester.pump();
    expect(find.text('Não consegui tocar “Sweet Emotion”.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
