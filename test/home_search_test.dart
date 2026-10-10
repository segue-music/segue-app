import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/now_playing_bar.dart';

import 'fakes.dart';
import 'themed_icons.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The home page on a screen of [size], over a fake server. Returns the player and the searches asked.
Future<(PlayerController, List<String?>)> pumpHome(WidgetTester tester, Size size) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final queries = <String?>[];
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      if (request.url.path.endsWith('getAlbumList2.view')) {
        // Only among the latest: nothing has played yet.
        if (request.url.queryParameters['type'] != 'newest') {
          return subsonic({'albumList2': <String, Object?>{}});
        }

        return subsonic({
          'albumList2': {
            'album': [
              {'id': 'a9', 'name': 'Toys in the Attic', 'artist': 'Aerosmith'},
            ],
          },
        });
      }

      // On a phone, in the search before something is searched.
      if (request.url.path.endsWith('getGenres.view')) {
        return subsonic({
          'genres': {
            'genre': [
              {'value': 'Hard Rock', 'albumCount': 2},
            ],
          },
        });
      }

      queries.add(request.url.queryParameters['query']);
      return subsonic({
        'searchResult3': {
          'album': [
            {'id': 'a1', 'name': 'Aerosmith', 'artist': 'Aerosmith', 'year': 1973},
          ],
          'song': [
            {'id': 's1', 'title': 'Dream On', 'artist': 'Aerosmith', 'album': 'Aerosmith', 'duration': 268},
            {'id': 's2', 'title': 'Dream Police', 'artist': 'Cheap Trick', 'album': 'Heaven Tonight'},
          ],
        },
      });
    }),
  );
  final player = PlayerController(FakeEngine(), api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  // The screen itself, not just the surface: the page picks its layout from MediaQuery.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      // Above the navigator, as in the app: on a phone, pages open in it, over the home.
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pump();
  return (player, queries);
}

void main() {
  testWidgets('on a phone-sized screen, the search is in the bar at the bottom, with the genres until typing stops', (
    tester,
  ) async {
    final (player, queries) = await pumpHome(tester, const Size(360, 640));
    final sections = find.byType(NavigationBar);
    expect(find.text('Toys in the Attic'), findsOneWidget);
    expect(find.byType(SearchBar), findsNothing, reason: 'only in the search');

    await tester.tap(find.descendant(of: sections, matching: find.text('Buscar')));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(sections).selectedIndex, 1, reason: 'after the home');
    expect(find.text('Toys in the Attic'), findsNothing);
    expect(find.text('Hard Rock'), findsOneWidget, reason: 'the genres, until a search');
    expect(find.byTooltip('Limpar'), findsNothing);
    expect(
      tester.testTextInput.isVisible,
      isFalse,
      reason: 'the keyboard would cover the genres, until a tap on the bar',
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    // In the top bar, 16 from the edge, in the place of the app's icon and the search's name, which its hint says.
    final searchBar = find.descendant(of: find.byType(AppBar), matching: find.byType(SearchBar));
    expect(searchBar, findsOneWidget);
    expect(tester.getTopLeft(searchBar).dx, 16);
    expect(find.descendant(of: searchBar, matching: find.text('Buscar')), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('Início')), findsNothing);

    await tester.enterText(find.byType(TextField), 'dre');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'dream ');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pump();
    expect(queries, ['dream']);
    expect(find.text('Hard Rock'), findsNothing);
    expect(find.textContaining('1973'), findsOneWidget, reason: 'the album, after its artist');
    expect(find.text('Cheap Trick · Heaven Tonight'), findsOneWidget);
    expect(find.text('4:28'), findsOneWidget);

    await tester.tap(find.text('Dream Police'));
    await tester.pump();
    expect([for (final song in player.queue) song.id], ['s1', 's2']);
    expect(player.current?.id, 's2');
    expect(player.playing, isTrue);

    // Another section, and back: the search is where it was, without the keyboard over it.
    await tester.tap(find.descendant(of: sections, matching: find.text('Início')));
    await tester.pumpAndSettle();
    expect(find.text('Toys in the Attic'), findsOneWidget);
    expect(find.byType(SearchBar), findsNothing);
    await tester.tap(find.descendant(of: sections, matching: find.text('Buscar')));
    await tester.pumpAndSettle();
    expect(find.text('Cheap Trick · Heaven Tonight'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byTooltip('Limpar'));
    await tester.pump();
    expect(find.textContaining('1973'), findsNothing);
    expect(find.text('Toys in the Attic'), findsNothing);
    expect(find.text('Hard Rock'), findsOneWidget, reason: 'the genres again');
    expect(queries, ['dream']);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a phone, a touch off the search bar closes the keyboard, and one on the bar, as on its clear button, '
      'leaves it open', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Buscar')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dream');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pump();
    final field = tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode;
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Músicas'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(field.hasFocus, isFalse);
    expect(find.text('Dream Police'), findsOneWidget, reason: 'the results stay');

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(
      find.descendant(of: find.byType(SearchBar), matching: themedIcon(HugeIcons.strokeRoundedSearch01)),
    );
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('Limpar'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue, reason: 'ready for another search');
    expect(field.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a phone, with the keyboard open, a touch off the search bar only closes it', (tester) async {
    final (player, _) = await pumpHome(tester, const Size(360, 640));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Buscar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    // The keyboard, over the bottom of the screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final field = tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode;

    await tester.tap(find.text('Hard Rock'));
    await tester.pumpAndSettle();
    expect(field.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(SearchBar), findsOneWidget, reason: 'no genre\'s page over the search');
    await tester.tap(find.text('Hard Rock'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsNothing, reason: 'the keyboard closed, the genre\'s page');

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dream');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pump();
    await tester.tap(find.text('Dream Police'));
    await tester.pump();
    expect(field.hasFocus, isFalse);
    expect(player.current, isNull);
    await tester.tap(find.text('Dream Police'));
    await tester.pump();
    expect(player.current?.id, 's2');
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a phone, a small gap sets the player bar apart from the sections\' bar, which alone keeps clear of '
      'the system\'s', (tester) async {
    final (player, _) = await pumpHome(tester, const Size(360, 640));
    final sections = find.byType(NavigationBar);
    final bottom = tester.getRect(sections).bottom;
    expect(find.byType(NowPlayingBar), findsOneWidget);
    expect(tester.getRect(find.byType(NowPlayingBar)).bottom, tester.getRect(sections).top, reason: 'nothing plays');

    await player.playQueue(const [Song(id: 's1', title: 'Dream On')]);
    await tester.pump();
    final bar = tester.getRect(find.byType(NowPlayingBar));
    expect(tester.getRect(sections).top - bar.bottom, 2);
    expect(
      tester.widget<NavigationBar>(sections).backgroundColor?.a,
      NowPlayingBar.phoneOpacity,
      reason: 'as the player',
    );
    expect(
      tester.widget<ClipRRect>(find.ancestor(of: sections, matching: find.byType(ClipRRect)).first).borderRadius,
      const BorderRadius.vertical(top: NowPlayingBar.phoneCorner),
      reason: 'its top corners rounded as the player\'s',
    );
    expect(tester.getRect(sections).bottom, bottom);

    tester.view.padding = const FakeViewPadding(bottom: 24);
    final height = tester.getSize(sections).height;
    expect(height, 68, reason: 'lower than Material\'s 80');
    await tester.pump();
    expect(tester.getSize(find.byType(NowPlayingBar)).height, bar.height);
    expect(tester.getSize(sections).height, height + 24);
    expect(tester.getRect(sections).top - tester.getRect(find.byType(NowPlayingBar)).bottom, 2);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timer
  });

  testWidgets('the songs found have no header over them, just their heading', (tester) async {
    await pumpHome(tester, const Size(1000, 640));
    await tester.enterText(find.byType(TextField), 'dream');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pump();
    expect(find.text('Músicas'), findsOneWidget);
    expect(find.text('Título'), findsNothing);
    expect(find.byTooltip('Duração'), findsNothing);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a wide screen, the bar sits in the middle of the window, past the arrows on its left', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1200, 640));
    final arrows = tester.getRect(find.byTooltip('Avançar'));
    final bar = tester.getRect(find.byType(SearchBar));
    expect(find.byTooltip('Buscar'), findsNothing, reason: 'no section in the side rail: the bar is always there');
    expect(bar.center.dx, moreOrLessEquals(600, epsilon: 1));
    expect(bar.left, greaterThan(arrows.right));
    expect(bar.center.dy, moreOrLessEquals(arrows.center.dy, epsilon: 4));
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a TV\'s window, the bar takes two fifths of it, and on a big one no more than 600', (tester) async {
    await pumpHome(tester, const Size(960, 540));
    expect(tester.getSize(find.byType(SearchBar)).width, moreOrLessEquals(384, epsilon: 1));
    await pumpHome(tester, const Size(1920, 1080));
    expect(tester.getSize(find.byType(SearchBar)).width, moreOrLessEquals(600, epsilon: 1));
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('where the middle has no room for it, the bar keeps clear of the arrows and the buttons', (tester) async {
    await pumpHome(tester, const Size(640, 640));
    final arrows = tester.getRect(find.byTooltip('Avançar'));
    final bar = tester.getRect(find.byType(SearchBar));
    expect(bar.left, greaterThan(arrows.right));
    expect(bar.right, lessThan(tester.getRect(find.byTooltip('Sem hub: só toca neste aparelho')).left));
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('off a TV, the keyboard opens as the focus comes to the search bar', (tester) async {
    await pumpHome(tester, const Size(1000, 640));
    expect(tester.testTextInput.isVisible, isFalse);

    for (var i = 0; i < 20 && !tester.testTextInput.isVisible; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('Esc in the search bar clears it, as its clear button does; empty, it leaves it', (tester) async {
    await pumpHome(tester, const Size(1000, 640));
    await tester.enterText(find.byType(TextField), 'dream');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pump();
    expect(find.text('Dream Police'), findsOneWidget);
    final field = tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode;
    expect(field.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Dream Police'), findsNothing);
    expect(find.text('Toys in the Attic'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
    expect(find.byTooltip('Limpar'), findsNothing);
    expect(field.hasFocus, isTrue, reason: 'ready for another search');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field.hasFocus, isFalse, reason: 'space plays and pauses again');
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('the key "/" goes to the search bar, also as a keyboard types it with Shift; not while typing, where it '
      'goes on to the text field', (tester) async {
    await pumpHome(tester, const Size(1000, 640));
    final field = tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode;
    expect(field.hasFocus, isFalse);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/'), isTrue);
    await tester.pump();
    expect(field.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue, reason: 'ready to type');
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/'), isFalse, reason: 'on to the field');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field.hasFocus, isFalse);
    // As a Spanish keyboard types it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7, character: '/');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(field.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a phone, the key "/" goes to the search, a section of its own, ready to type', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    expect(find.byType(SearchBar), findsNothing);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/'), isTrue);
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
    expect(tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('on a phone, the search picked again goes to its bar, ready to type; with a page over it, it shows '
      'again', (tester) async {
    await pumpHome(tester, const Size(360, 640));
    final search = find.descendant(of: find.byType(NavigationBar), matching: find.text('Buscar'));
    await tester.tap(search);
    await tester.pumpAndSettle();
    final field = tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode;
    expect(field.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(search);
    await tester.pump();
    expect(field.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Hard Rock'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsNothing, reason: 'the genre\'s page, over the search');
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.text('Hard Rock'), findsOneWidget, reason: 'the genres again');
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });

  testWidgets('the app\'s icon clears the search, going back to the home', (tester) async {
    await pumpHome(tester, const Size(1000, 640));
    await tester.enterText(find.byType(TextField), 'dream');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pump();
    expect(find.text('Dream Police'), findsOneWidget);

    await tester.tap(find.byTooltip('Início'));
    await tester.pump();
    expect(find.text('Dream Police'), findsNothing);
    expect(find.text('Toys in the Attic'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
    await tester.pumpWidget(const SizedBox()); // stops the bar's timer
  });
}
