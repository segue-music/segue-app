import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album/album_page.dart';
import 'package:segue/ui/album/albums_view.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/app/shortcuts.dart';
import 'package:segue/ui/app/television_screen.dart';
import 'package:segue/ui/artist/artists_view.dart';
import 'package:segue/ui/widgets/letter_bar.dart';

import 'fakes.dart';
import 'sections.dart';

http.Response _subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The library's albums by name: "1999", then twenty for each letter but Q, "A00" to "Z19".
final _albums = [
  '1999',
  for (final letter in letters.skip(1))
    if (letter != 'Q')
      for (var i = 0; i < 20; i++) '$letter${'$i'.padLeft(2, '0')}',
];

/// The home page on a TV's Full HD screen, or, with [television] false, a computer's or a tablet's as wide (as the
/// platform is), over a library of [_albums], whose artists are named as they are, and whose albums have sixty songs
/// each. Returns the pages of albums by name the app asks for: their offset and size.
Future<List<String>> _pumpHome(
  WidgetTester tester, {
  bool television = true,
  Size size = const Size(1920, 1080),
}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final asked = <String>[];
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      final query = request.url.queryParameters;
      final path = request.url.path;

      if (path.endsWith('getAlbumList2.view')) {
        final names = query['type'] == 'alphabeticalByName' ? _albums : const <String>[];
        final offset = int.parse(query['offset']!);
        final size = int.parse(query['size']!);

        if (query['type'] == 'alphabeticalByName') {
          asked.add('$offset $size');
        }

        return _subsonic({
          'albumList2': {
            'album': [
              for (final name in names.skip(offset).take(size)) {'id': name, 'name': name},
            ],
          },
        });
      }

      if (path.endsWith('getAlbum.view')) {
        return _subsonic({
          'album': {
            'id': query['id'],
            'name': query['id'],
            'song': [
              for (var i = 0; i < 60; i++) {'id': 't$i', 'title': 'Track $i', 'duration': 200, 'track': i + 1},
            ],
          },
        });
      }

      if (path.endsWith('getArtists.view')) {
        return _subsonic({
          'artists': {
            'index': [
              for (final letter in letters)
                {
                  'name': letter,
                  'artist': [
                    for (final name in _albums)
                      if (letterOf(name) == letter) {'id': 'ar-$name', 'name': name},
                  ],
                },
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
          child: ListShortcuts(child: TextFieldArrowShortcuts(child: child!)),
        ),
      ),
      home: HomePage(onSignOut: () {}),
    ),
  );
  await tester.pumpAndSettle();

  return asked;
}

/// The name of the album, or of the artist, that has the focus.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;

  return context?.findAncestorWidgetOfExactType<AlbumTile>()?.album.name ??
      context?.findAncestorWidgetOfExactType<ArtistTile>()?.artist.name;
}

/// Whether the list shows [name], an album or an artist, in its top row, at the top.
bool _atTop(WidgetTester tester, String name) {
  final tile = find.ancestor(
    of: find.text(name),
    matching: find.byWidgetPredicate((widget) => widget is AlbumTile || widget is ArtistTile),
  );
  final view = tester.getRect(find.ancestor(of: tile, matching: find.byType(CustomScrollView)));

  return (tester.getRect(tile).top - view.top).abs() < 1;
}

/// The albums' grid, the list of the albums tab.
ScrollPosition _albumsGrid(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.descendant(of: find.byType(AlbumsView), matching: find.byType(Scrollable)))
    .firstWhere((scrollable) => scrollable.position.axis == Axis.vertical)
    .position;

/// Whether the focus is on a letter beside the list.
bool _onLetter() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<LetterBar>() != null;

/// How far down the list with the focus is scrolled.
double _scrolled() {
  final context = FocusManager.instance.primaryFocus!.context!;

  return Scrollable.of(context, axis: Axis.vertical).position.pixels;
}

/// Gives the focus to what [text] is in, as the remote would.
Future<void> _focus(WidgetTester tester, String text) async {
  Focus.of(tester.element(find.text(text))).requestFocus();
  await tester.pumpAndSettle();
}

/// Presses [key] as the remote does, and says whether the app took it: one it leaves goes to the system, back's
/// closing the page. Its back, which the tests' keyboard lacks, comes as a browser's: the same key to the app.
Future<bool> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  final taken = key == LogicalKeyboardKey.goBack
      ? await tester.sendKeyEvent(key, platform: 'web', physicalKey: PhysicalKeyboardKey.browserBack)
      : await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();

  return taken;
}

void _expectUnderSettings(WidgetTester tester) {
  final letter = find.descendant(of: find.byType(LetterBar), matching: find.text('M'));
  expect(tester.getCenter(letter).dx, moreOrLessEquals(tester.getCenter(find.byTooltip('Configurações')).dx));
}

void main() {
  test('a name is listed under its first letter, past an article, without its accent, and one that starts with no '
      'letter under #', () {
    expect(letterOf('Aerosmith'), 'A');
    expect(letterOf('the Beatles'), 'B');
    expect(letterOf('Os Paralamas do Sucesso'), 'P');
    expect(letterOf('Échame la culpa'), 'E');
    expect(letterOf('Ñu'), 'N');
    expect(letterOf('A'), 'A');
    expect(letterOf('...And Justice for All'), '#');
    expect(letterOf('1999'), '#');
    expect(letterOf(''), '#');
  });

  test('a letter starts after the one before it, so that a name out of its place doesn\'t take it there, and one with '
      'none starts where the next one there is does', () {
    // The third, sorted under A by a server that leaves out an article the app doesn't know (Die Ärzte), under D by the
    // app.
    const listed = ['#', 'A', 'D', 'A', 'B', 'D', 'E'];

    expect(letterStart(listed, '#'), 0);
    expect(letterStart(listed, 'A'), 1);
    expect(letterStart(listed, 'B'), 4);
    expect(letterStart(listed, 'C'), 5, reason: 'no C: where the D start');
    expect(letterStart(listed, 'D'), 5);
    expect(letterStart(listed, 'F'), isNull);
    expect(letterStart(['A', 'B'], 'M'), isNull, reason: 'further down, not come yet');
  });

  testWidgets('on a TV, the channel buttons move the focus a page down the albums, and back up, and at the end to its '
      'last row', (tester) async {
    await _pumpHome(tester);
    await openSection(tester, 'Álbuns');
    await _focus(tester, 'A01');

    expect(await _press(tester, LogicalKeyboardKey.channelDown), isTrue);
    final down = _albums.indexOf(_focused()!);
    expect(down, greaterThan(_albums.indexOf('A01')));
    expect(down % 5, _albums.indexOf('A01') % 5, reason: 'in the same column');
    expect(_scrolled(), greaterThan(0));
    final rect = tester.getRect(find.text(_focused()!));
    expect(rect.top, greaterThan(0));
    expect(rect.bottom, lessThan(540));

    expect(await _press(tester, LogicalKeyboardKey.channelUp), isTrue);
    expect(_focused(), 'A01');
    expect(_scrolled(), 0);

    expect(await _press(tester, LogicalKeyboardKey.channelUp), isTrue, reason: 'at the top already');
    expect(_focused(), 'A01');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, a letter beside the albums by name scrolls them to the first under it, the pages up to it '
      'asked for first, and to the next letter\'s where it has none, the focus staying on the letter', (tester) async {
    final asked = await _pumpHome(tester);
    await openSection(tester, 'Álbuns');
    expect(find.byType(LetterBar), findsOneWidget);
    expect(asked, ['0 200']);

    await _focus(tester, 'M');
    await _press(tester, LogicalKeyboardKey.select);
    expect(_atTop(tester, 'M00'), isTrue);
    expect(_onLetter(), isTrue);
    expect(asked, ['0 200', '200 500']);

    await _focus(tester, 'Q');
    await _press(tester, LogicalKeyboardKey.select);
    expect(_atTop(tester, 'R00'), isTrue);

    await _focus(tester, '#');
    await _press(tester, LogicalKeyboardKey.select);
    expect(_atTop(tester, '1999'), isTrue);

    await _focus(tester, 'Z');
    await _press(tester, LogicalKeyboardKey.select);
    expect(_atTop(tester, 'Z00'), isTrue);
    expect(asked, ['0 200', '200 500']);

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused(), startsWith('Z'), reason: 'left goes on to the albums beside');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, the letters are under the top bar\'s settings button', (tester) async {
    await _pumpHome(tester);
    await openSection(tester, 'Álbuns');
    _expectUnderSettings(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a computer, the letters are under the top bar\'s settings button', (tester) async {
    await _pumpHome(tester, television: false);
    await openSection(tester, 'Álbuns');
    _expectUnderSettings(tester);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on a TV, the albums in another order have no letters', (tester) async {
    await _pumpHome(tester);
    await openSection(tester, 'Álbuns');
    await tester.tap(find.text('Mais tocados'));
    await tester.pumpAndSettle();
    expect(find.byType(LetterBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, a letter beside the artists by name scrolls them to the first under it, and right of the '
      'letters is nowhere', (tester) async {
    await _pumpHome(tester);
    await openSection(tester, 'Artistas');
    await _focus(tester, 'C');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_onLetter(), isTrue);

    await _focus(tester, 'K');
    await _press(tester, LogicalKeyboardKey.select);
    expect(_atTop(tester, 'K00'), isTrue);
    expect(_onLetter(), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a computer, a click on a letter beside the albums scrolls them to the first under it, and the letter under the '
    'pointer shows big',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      await _pumpHome(tester, television: false);
      await openSection(tester, 'Álbuns');
      expect(find.byType(LetterBar), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.text('K')));
      await tester.pumpAndSettle();
      expect(find.text('K'), findsNWidgets(2), reason: 'in the bar and beside it');

      await tester.tap(find.text('M'));
      await tester.pumpAndSettle();
      expect(_atTop(tester, 'M00'), isTrue);
      expect(_focused(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the side rail\'s button of the section shown takes it back to its start', (tester) async {
    await _pumpHome(tester, television: false);
    await openSection(tester, 'Álbuns');
    _albumsGrid(tester).jumpTo(3000);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Álbuns'));
    await tester.pumpAndSettle();
    expect(_albumsGrid(tester).pixels, 0);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on a phone, the library picked again takes its tab back to its start', (tester) async {
    await _pumpHome(tester, television: false, size: const Size(1080, 2340));
    await openSection(tester, 'Álbuns');
    _albumsGrid(tester).jumpTo(3000);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Biblioteca')));
    await tester.pumpAndSettle();
    expect(_albumsGrid(tester).pixels, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a tablet, the albums by name have their letters too', (tester) async {
    await _pumpHome(tester, television: false);
    await openSection(tester, 'Álbuns');
    expect(find.byType(LetterBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, a finger slid along the letters takes the albums to each it goes onto, that one big beside '
      'them, and they end over the bars at the bottom, under the settings button', (tester) async {
    await _pumpHome(tester, television: false, size: const Size(1080, 2340));
    await openSection(tester, 'Álbuns');
    _expectUnderSettings(tester);
    Finder letter(String text) => find.descendant(of: find.byType(LetterBar), matching: find.text(text)).first;
    expect(tester.getRect(letter('Z')).bottom, lessThan(tester.getRect(find.byType(NavigationBar)).top));

    final finger = await tester.startGesture(tester.getCenter(letter('A')));
    await finger.moveTo(tester.getCenter(letter('F')));
    await tester.pumpAndSettle();
    expect(find.text('F'), findsNWidgets(2), reason: 'in the bar and beside it');
    expect(_atTop(tester, 'F00'), isTrue);

    await finger.moveTo(tester.getCenter(letter('M')));
    await tester.pumpAndSettle();
    expect(_atTop(tester, 'M00'), isTrue);

    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('M'), findsOneWidget, reason: 'beside them no more');
    expect(_atTop(tester, 'M00'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, back far down a page goes back to its top, the focus first there, and only then leaves it', (
    tester,
  ) async {
    await _pumpHome(tester);
    await openSection(tester, 'Álbuns');
    await _focus(tester, 'A00');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(AlbumPage), findsOneWidget);
    await _focus(tester, 'Track 0');

    expect(await _press(tester, LogicalKeyboardKey.goBack), isFalse, reason: 'in the first screen: left to the system');

    await _press(tester, LogicalKeyboardKey.channelDown);
    await _press(tester, LogicalKeyboardKey.channelDown);
    expect(_scrolled(), greaterThan(0));
    expect(await _press(tester, LogicalKeyboardKey.goBack), isTrue);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(_scrolled(), 0);
    expect(find.text('Track 0').hitTestable(), findsOneWidget);

    expect(await _press(tester, LogicalKeyboardKey.goBack), isFalse, reason: 'at the top: left to the system');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a TV, back far down the albums goes back to the first', (tester) async {
    await _pumpHome(tester);
    await openSection(tester, 'Álbuns');
    await _focus(tester, 'L');
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused(), startsWith('L'));

    expect(await _press(tester, LogicalKeyboardKey.goBack), isTrue);
    expect(_focused(), '1999');
    expect(_scrolled(), 0);
    await tester.pumpWidget(const SizedBox());
  });
}
