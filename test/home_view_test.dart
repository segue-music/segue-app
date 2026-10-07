import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album_page.dart';
import 'package:segue/ui/albums_view.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/shortcuts.dart';
import 'package:segue/ui/themed_icon.dart';

import 'fakes.dart';
import 'side_rail.dart';
import 'themed_icons.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response albumList(List<String> names) => subsonic({
  'albumList2': {
    'album': [
      for (final name in names) {'id': name, 'name': name, 'artist': 'Aerosmith'},
    ],
  },
});

/// The home page on a screen of [size], over a server whose latest released albums are [released],
/// whose most played are [mostPlayed] (null: it fails to list them) and whose latest added are
/// [latest], however many are asked for. Returns the queries of the album lists asked for.
Future<List<Map<String, String>>> pumpHome(
  WidgetTester tester,
  Size size, {
  List<String> released = const ['Music from Another Dimension!'],
  List<String>? mostPlayed = const ['Pump', 'Toys in the Attic'],
  List<String> latest = const ['Night in the Ruts'],
  bool television = false,
}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final asked = <Map<String, String>>[];
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      final query = request.url.queryParameters;

      if (request.url.path.endsWith('getAlbumList2.view')) {
        asked.add(query);
        return switch (query['type']) {
          'frequent' when mostPlayed != null => albumList(mostPlayed),
          'newest' => albumList(latest),
          'byYear' => albumList(released),
          _ => http.Response('', 500),
        };
      }

      if (request.url.path.endsWith('getAlbum.view')) {
        return subsonic({
          'album': {
            'id': query['id'],
            'name': query['id'],
            'song': [
              {'id': 's1', 'title': 'Love in an Elevator', 'artist': 'Aerosmith'},
            ],
          },
        });
      }

      return http.Response('', 404);
    }),
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
      builder: (context, child) => ServicesScope(
        services: services,
        child: DirectionalNavigation(enabled: television, child: child!),
      ),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pumpAndSettle();
  return asked;
}

/// The rows' sideways lists, in order.
final rows = find.byWidgetPredicate((widget) => widget is ListView && widget.scrollDirection == Axis.horizontal);

Finder title(String text) => find.descendant(of: find.byType(AppBar), matching: find.text(text));

/// A text, where it shows.
Finder shown(String text) => find.text(text).hitTestable();

/// Where the side rail ends: the line between it and the section.
double railWidth(WidgetTester tester) => tester.getTopLeft(find.byType(VerticalDivider)).dx;

/// The side rail's button for [section], which its tooltip names.
Finder railButton(String section) =>
    find.descendant(of: find.byTooltip(section), matching: find.byWidgetPredicate((widget) => widget is InkResponse));

/// The name of the album that has the focus.
String? focusedAlbum() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<AlbumTile>()?.album.name;

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the app opens on the home: a row of the latest released albums, then the most played, then the latest '
      'added', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    expectHomeInRail();

    final released = tester.getRect(find.text('Lançamentos'));
    final another = tester.getRect(find.text('Music from Another Dimension!'));
    final mostPlayed = tester.getRect(find.text('Mais tocados'));
    final pump = tester.getRect(find.text('Pump'));
    final toys = tester.getRect(find.text('Toys in the Attic'));
    final latest = tester.getRect(find.text('Adicionados recentemente'));
    final ruts = tester.getRect(find.text('Night in the Ruts'));
    expect(another.top, greaterThan(released.bottom));
    expect(mostPlayed.top, greaterThan(another.bottom));
    expect(pump.top, greaterThan(mostPlayed.bottom));
    expect(toys.top, pump.top, reason: 'side by side, the most played first');
    expect(toys.left, greaterThan(pump.right));
    expect(latest.top, greaterThan(pump.bottom));
    expect(ruts.top, greaterThan(latest.bottom));

    await tester.tap(find.text('Pump'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AlbumPage), matching: find.text('Pump')), findsOneWidget);
    expect(find.text('Love in an Elevator'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
  });

  testWidgets('the side rail has the sections\' icons, each a button no bigger than its highlight, named on hover', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    expect(railWidth(tester), 56);
    expect(shown('Álbuns'), findsNothing);
    expect(shown('Artistas'), findsNothing);
    expect(shown('Gêneros'), findsNothing);
    expect(find.byTooltip('Recolher a barra lateral'), findsNothing, reason: 'it is always so');

    for (final section in ['Álbuns', 'Artistas', 'Gêneros']) {
      expect(tester.getSize(railButton(section)), const Size(40, 40), reason: section);
    }

    await tester.tap(find.byTooltip('Álbuns'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Álbuns'), findsOneWidget);

    bool selected(String section) => tester
        .widget<IconButton>(find.ancestor(of: railButton(section), matching: find.byType(IconButton)))
        .isSelected!;

    expect(selected('Álbuns'), isTrue);
    expect(selected('Artistas'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a section\'s name shows beside its icon, level with it, rather than over the icon below', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(999, 699));
    addTearDown(mouse.removePointer);

    for (final section in ['Álbuns', 'Artistas', 'Gêneros']) {
      final icon = tester.getRect(railButton(section));
      await mouse.moveTo(icon.center);
      await tester.pumpAndSettle();
      final name = tester.getRect(find.text(section));
      expect(name.left, greaterThan(icon.right), reason: '$section: to the right of its icon');
      expect(name.center.dy, moreOrLessEquals(icon.center.dy, epsilon: 1), reason: '$section: level with it');
      await mouse.moveTo(const Offset(999, 699));
      await tester.pumpAndSettle(const Duration(seconds: 2)); // the name goes away
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the app\'s icon, in the top left corner, goes to the home, which the side rail doesn\'t list', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1000, 700));
    final logo = find.byTooltip('Início');
    expect(logo, findsOneWidget, reason: 'the app\'s icon alone');
    expect(find.descendant(of: logo, matching: find.byType(Image)), findsOneWidget);
    expect(themedIcon(HugeIcons.strokeRoundedHome01), findsNothing);
    final corner = tester.getRect(logo);
    expect(corner.left, lessThan(16));
    expect(corner.top, lessThan(16));
    expect(corner.right, lessThanOrEqualTo(railWidth(tester)), reason: 'over the side rail');

    await tester.tap(find.byTooltip('Artistas'));
    await tester.pumpAndSettle();
    expect(selectedInRail('Artistas'), findsOneWidget);
    expect(shown('Mais tocados'), findsNothing);

    await tester.tap(logo);
    await tester.pumpAndSettle();
    expectHomeInRail();
    expect(shown('Mais tocados'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the hub\'s status sits as far from signing out as two buttons are from each other',
    (tester) async {
      await pumpHome(tester, const Size(1000, 700));

      Rect icon(HugeIconData icon) =>
          tester.getRect(find.descendant(of: find.byType(AppBar), matching: themedIcon(icon)));

      final (hub, signOut) = (icon(HugeIcons.strokeRoundedUnlink02), icon(HugeIcons.strokeRoundedLogout01));
      final button = tester.getSize(
        find.ancestor(of: themedIcon(HugeIcons.strokeRoundedLogout01), matching: find.byType(IconButton)),
      );
      expect(signOut.left - hub.right, button.width - signOut.width);
      expect(hub.center.dy, signOut.center.dy);
      await tester.pumpWidget(const SizedBox());
    },
    // Buttons are smaller on a desktop.
    variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.linux}),
  );

  testWidgets('on a phone, the app\'s icon is in the top left corner too, and the bar at the bottom keeps the home', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 640));
    final logo = find.descendant(of: find.byType(AppBar), matching: find.byTooltip('Início'));
    final bar = find.byType(NavigationBar);
    expect(tester.getRect(logo).left, lessThan(16));
    expect(find.descendant(of: bar, matching: find.text('Início')), findsOneWidget);

    await tester.tap(find.descendant(of: bar, matching: find.text('Álbuns')));
    await tester.pumpAndSettle();
    expect(title('Álbuns'), findsOneWidget);

    await tester.tap(logo);
    await tester.pumpAndSettle();
    expect(title('Início'), findsOneWidget);
    expect(tester.widget<NavigationBar>(bar).selectedIndex, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, up from the side rail goes to the app\'s icon, which goes to the home', (tester) async {
    await pumpHome(tester, const Size(960, 540), television: true);
    await tester.tap(find.byTooltip('Álbuns'));
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.descendant(of: find.byTooltip('Álbuns'), matching: find.byType(ThemedIcon))))
        .requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(Focus.of(tester.element(find.byType(Image).first)).hasFocus, isTrue);

    await press(tester, LogicalKeyboardKey.enter);
    expectHomeInRail();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a row goes on sideways', (tester) async {
    await pumpHome(tester, const Size(360, 640), released: [for (var i = 0; i < 10; i++) 'Released $i']);
    expect(find.text('Released 0'), findsOneWidget);
    expect(find.text('Released 9'), findsNothing);
    await tester.drag(find.text('Released 0'), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(find.text('Released 9'), findsOneWidget);
    expect(find.text('Pump'), findsOneWidget, reason: 'the other rows stay');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('arrows at the right of a row take it a screenful forward and back, lined up on an album', (
    tester,
  ) async {
    await pumpHome(
      tester,
      const Size(1000, 700),
      mostPlayed: [for (var i = 0; i < 20; i++) 'Most $i'],
      latest: [for (var i = 0; i < 20; i++) 'Latest $i'],
    );
    expect(find.byType(Scrollbar), findsNothing);
    final back = find.byTooltip('Anteriores').first;
    final forward = find.byTooltip('Próximos').first;
    final heading = tester.getRect(find.text('Mais tocados'));
    expect(tester.getRect(back).left, greaterThan(heading.right));
    expect(tester.getRect(forward).left, greaterThan(tester.getRect(back).right - 1));
    expect(tester.getRect(forward).right, greaterThan(1000 - 64), reason: 'in the right corner');
    expect(tester.getCenter(forward).dy, moreOrLessEquals(heading.center.dy, epsilon: 4));

    final scroll = tester.widget<ListView>(find.ancestor(of: find.text('Most 0'), matching: rows)).controller!;

    bool enabled(Finder arrow) =>
        tester.widget<IconButton>(find.ancestor(of: arrow, matching: find.byType(IconButton)).first).onPressed != null;

    expect(enabled(back), isFalse, reason: 'at the start');
    expect(enabled(forward), isTrue);

    await tester.tap(forward);
    await tester.pumpAndSettle();
    expect(find.text('Most 0'), findsNothing);
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset % (160 + 16), 0, reason: 'an album at the left edge');
    expect(find.text('Latest 0'), findsOneWidget, reason: 'the other row stays');
    expect(enabled(back), isTrue);

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(find.text('Most 0'), findsOneWidget);
    expect(enabled(back), isFalse);

    for (var i = 0; i < 10 && enabled(forward); i++) {
      await tester.tap(forward);
      await tester.pumpAndSettle();
    }

    expect(enabled(forward), isFalse, reason: 'at the end');
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(find.text('Most 19'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row\'s title opens the albums tab, in the row\'s order', (tester) async {
    final asked = await pumpHome(tester, const Size(1000, 700));

    bool picked(String label) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

    for (final (row, type) in [
      ('Lançamentos', 'byYear'),
      ('Mais tocados', 'frequent'),
      ('Adicionados recentemente', 'newest'),
    ]) {
      await tester.tap(find.byTooltip('Início'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(selectedInRail('Álbuns'), findsOneWidget, reason: row);
      expect(picked(row), isTrue, reason: row);
      expect(asked.last, allOf(containsPair('type', type), containsPair('size', '200')), reason: row);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row whose albums all fit has no arrows', (tester) async {
    await pumpHome(tester, const Size(1000, 700));
    expect(find.text('Toys in the Attic'), findsOneWidget);
    expect(find.byTooltip('Próximos'), findsNothing);
    expect(find.byTooltip('Anteriores'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row has 30 albums at most, even from a server that sends more', (tester) async {
    final asked = await pumpHome(
      tester,
      const Size(360, 640),
      released: [for (var i = 0; i < 40; i++) 'Released $i'],
      mostPlayed: [for (var i = 0; i < 40; i++) 'Most $i'],
      latest: [for (var i = 0; i < 40; i++) 'Latest $i'],
    );
    expect([for (final query in asked) query['size']], ['30', '30', '30']);

    for (final prefix in ['Released', 'Most', 'Latest']) {
      // By its albums: the list builds the rows that show, which change as it scrolls.
      final row = find.ancestor(of: find.text('$prefix 0'), matching: rows);
      await tester.ensureVisible(row); // the last ones are under the bottom bar, at first
      await tester.pumpAndSettle();
      await tester.drag(row, const Offset(-10000, 0));
      await tester.pumpAndSettle();
      expect(find.text('$prefix 29'), findsOneWidget);
      expect(find.text('$prefix 30'), findsNothing);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('before anything has played, the home says what will show there', (tester) async {
    await pumpHome(tester, const Size(1000, 700), mostPlayed: []);
    expect(find.text('Mais tocados'), findsOneWidget);
    expect(find.text('Os álbuns que você mais ouvir aparecem aqui.'), findsOneWidget);
    expect(find.text('Night in the Ruts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row the server fails to list says so, and the other still shows', (tester) async {
    await pumpHome(tester, const Size(1000, 700), mostPlayed: null);
    expect(find.textContaining('Não consegui listar os álbuns'), findsOneWidget);
    expect(find.text('Night in the Ruts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pulling the home down lists every row again', (tester) async {
    final asked = await pumpHome(tester, const Size(360, 640));

    List<String?> types() => [for (final query in asked) query['type']];

    expect(types(), unorderedEquals(['byYear', 'frequent', 'newest']));
    await tester.fling(find.text('Lançamentos'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(types(), unorderedEquals(['byYear', 'frequent', 'newest', 'byYear', 'frequent', 'newest']));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, right goes along a row, scrolling it, and down goes to the next row, past its arrows', (
    tester,
  ) async {
    await pumpHome(
      tester,
      const Size(960, 540),
      mostPlayed: [for (var i = 0; i < 12; i++) 'Most $i'],
      latest: [for (var i = 0; i < 12; i++) 'Latest $i'],
      television: true,
    );

    for (var i = 0; i < 100 && focusedAlbum() != 'Most 0'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(focusedAlbum(), 'Most 0');

    for (var i = 0; i < 7; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }

    expect(focusedAlbum(), 'Most 7');
    expect(tester.getRect(find.text('Most 7')).right, lessThanOrEqualTo(960), reason: 'scrolled into view');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedAlbum(), startsWith('Latest'));
    await tester.pumpWidget(const SizedBox());
  });
}
