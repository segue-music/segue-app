import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/ui/home/home_chips.dart';
import 'package:segue/ui/playlist/favorite_songs_page.dart';

import 'fakes.dart';
import 'home_search_test.dart' show pumpHome;
import 'mixes_test.dart' show api, credentials;

/// The home's chips in a top bar, over mixes_test.dart's library, whose songs at random are three; [asked] gets the
/// queries of the songs asked for at random. Returns the player.
Future<PlayerController> pumpChips(WidgetTester tester, {List<Map<String, String>>? asked}) async {
  final server = api(asked: asked);
  final player = PlayerController(FakeEngine(), server);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    server,
    player,
    ConnectController(player: player),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: Scaffold(
        appBar: AppBar(title: HomeChips(onFavorites: () {})),
      ),
    ),
  );

  return player;
}

void main() {
  testWidgets('"Aleatório" plays songs of the whole library at random', (tester) async {
    final asked = <Map<String, String>>[];
    final player = await pumpChips(tester, asked: asked);
    await tester.tap(find.text('Aleatório'));
    await tester.pumpAndSettle();
    expect([for (final song in player.queue) song.id], ['s5', 's7', 's8']);
    expect(player.playing, isTrue);
    expect(asked.single, containsPair('size', '100'));
    expect(asked.single.keys, isNot(anyOf(contains('genre'), contains('fromYear'), contains('toYear'))));
  });

  testWidgets('on a phone, "Favoritas" opens the favorite songs over the home, under the bars at the bottom, which '
      'stay', (tester) async {
    await pumpHome(tester, const Size(360, 800));
    // Scrolled to, as with the tests' font, whose letters are all as wide as tall, it doesn't fit beside the first.
    await tester.ensureVisible(find.text('Favoritas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favoritas'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteSongsPage), findsOneWidget);
    expect(find.text('Início').hitTestable(), findsOneWidget, reason: 'the sections\' bar\'s');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, the home has no chips: its top bar has the search bar, the side rail the sections', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1200, 700));
    expect(find.byType(HomeChips), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
