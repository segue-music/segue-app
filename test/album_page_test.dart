import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/releases/musicbrainz.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/album_page.dart';
import 'package:segue/ui/artist_page.dart';
import 'package:segue/ui/cover_page.dart';
import 'package:segue/ui/now_playing_bar.dart';
import 'package:segue/ui/page_bar.dart';

import 'fakes.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The page of Toys in the Attic, with the cover [coverArt], two songs by Aerosmith and then [more] songs, the release
/// date [releaseDate], the record labels [recordLabels] and the release types [releaseTypes], on a screen of [size],
/// with what [musicBrainz] adds.
/// Aerosmith's picture is `ar-ar1`. Returns the player's engine.
Future<FakeEngine> pumpAlbum(
  WidgetTester tester, {
  String? coverArt = 'al-a1',
  int more = 0,
  Map<String, int>? releaseDate,
  List<String> recordLabels = const [],
  List<String>? releaseTypes,
  MusicBrainz? musicBrainz,
  Size size = const Size(1000, 700),
}) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      if (request.url.path.endsWith('getArtist.view')) {
        return subsonic({
          'artist': {'id': 'ar1', 'name': 'Aerosmith', 'albumCount': 1, 'coverArt': 'ar-ar1'},
        });
      }

      return subsonic({
        'album': {
          'id': 'a1',
          'name': 'Toys in the Attic',
          'artist': 'Aerosmith',
          'artistId': 'ar1',
          'year': 1975,
          'coverArt': ?coverArt,
          'releaseDate': ?releaseDate,
          'releaseTypes': ?releaseTypes,
          'recordLabels': [
            for (final label in recordLabels) {'name': label},
          ],
          'song': [
            {'id': 's1', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'artistId': 'ar1', 'duration': 220},
            {'id': 's2', 'title': 'Sweet Emotion', 'artist': 'Aerosmith', 'artistId': 'ar1', 'duration': 274},
            for (var i = 1; i <= more; i++) {'id': 'm$i', 'title': 'Song $i', 'artist': 'Aerosmith', 'duration': 200},
          ],
        },
      });
    }),
  );
  final engine = FakeEngine();
  final player = PlayerController(engine, api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
    musicBrainz: musicBrainz,
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: const AlbumPage(Album(id: 'a1', name: 'Toys in the Attic')),
    ),
  );
  await tester.pumpAndSettle();
  return engine;
}

/// The song titled [title] in the album's list.
Finder song(String title) => find.widgetWithText(ListTile, title);

/// The cover as asked of the server at [size] pixels.
Finder coverAt(int size) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      Uri.parse((widget.image as NetworkImage).url).queryParameters['size'] == '$size',
);

/// The image of the cover whose id is [id].
Finder coverOf(String id) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      Uri.parse((widget.image as NetworkImage).url).queryParameters['id'] == id,
);

/// The play button, with the room around it that a tap on a touch screen takes too.
final playButton = find.ancestor(of: find.byTooltip('Tocar o álbum'), matching: find.byType(IconButton));

/// Opens the album's page again over the one [pumpAlbum] opened, so it has a page to go back to, and the back arrow.
Future<void> pushAlbum(WidgetTester tester) async {
  unawaited(
    Navigator.of(tester.element(find.byType(AlbumPage))).push(
      MaterialPageRoute<void>(
        builder: (context) => const AlbumPage(Album(id: 'a1', name: 'Toys in the Attic')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openCover(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ver a capa'));
  await tester.pumpAndSettle();
  expect(find.byType(CoverPage), findsOneWidget);
}

void main() {
  testWidgets('on a phone, the songs go on behind the player bar, and the last one scrolls clear of it', (
    tester,
  ) async {
    await pumpAlbum(tester, more: 20, size: const Size(360, 640));
    await tester.tap(song('Walk This Way'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(CustomScrollView)).bottom, 640);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -100000));
    await tester.pumpAndSettle();
    expect(tester.getRect(song('Song 20')).bottom, lessThanOrEqualTo(tester.getRect(find.byType(NowPlayingBar)).top));
    await tester.pumpWidget(const SizedBox()); // stops the player bar's timer
  });

  testWidgets('the cover opens full screen: as big as the screen\'s shorter side, asked of the server so', (
    tester,
  ) async {
    await pumpAlbum(tester);
    await openCover(tester);
    expect(tester.getSize(coverAt(700)), const Size(700, 700));
    expect(tester.getCenter(coverAt(700)), const Offset(500, 350));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap anywhere closes it, as do Esc and "Fechar"', (tester) async {
    await pumpAlbum(tester);
    await openCover(tester);
    await tester.tapAt(const Offset(500, 350));
    await tester.pumpAndSettle();
    expect(find.byType(CoverPage), findsNothing);
    expect(find.text('Walk This Way'), findsOneWidget);

    await openCover(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CoverPage), findsNothing);

    await openCover(tester);
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(CoverPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the keyboard and the remote get to the cover too', (tester) async {
    await pumpAlbum(tester);
    final cover = find.byTooltip('Ver a capa');

    for (var i = 0; i < 5 && FocusManager.instance.primaryFocus?.rect != tester.getRect(cover); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(cover));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CoverPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an album without a cover has none to open', (tester) async {
    await pumpAlbum(tester, coverArt: null);
    expect(find.byTooltip('Ver a capa'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the play button is just its icon, its name in the tooltip, and plays the album from its first song', (
    tester,
  ) async {
    final engine = await pumpAlbum(tester);
    final play = find.byTooltip('Tocar o álbum');
    expect(find.descendant(of: play, matching: find.byType(Text)), findsNothing);
    expect(find.text('Tocar'), findsNothing);
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(engine.tracks, hasLength(2));
    expect(engine.index, 0);
    expect(engine.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('under each song, its artist, a link to their page that doesn\'t play the song', (tester) async {
    final engine = await pumpAlbum(tester);
    final artist = find.descendant(of: song('Walk This Way'), matching: find.text('Aerosmith'));
    expect(artist, findsOneWidget, reason: 'also when they are the album\'s artist');
    await tester.tap(artist);
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.descendant(of: find.byType(ArtistPage), matching: find.text('Aerosmith')).first, findsOneWidget);
    expect(engine.tracks, isEmpty, reason: 'the song didn\'t play');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'under the album\'s name, its artist, with their picture, then its year, its songs and how long they last',
    (tester) async {
      await pumpAlbum(tester);
      final byline = find.textContaining(' · 1975 · 2 faixas, 8 min');
      expect(byline, findsOneWidget);
      final artist = find.descendant(of: byline, matching: find.text('Aerosmith'));
      final picture = find.descendant(of: byline, matching: coverOf('ar-ar1'));
      expect(tester.getSize(picture), const Size(24, 24));
      expect(tester.getRect(picture).right, lessThan(tester.getRect(artist).left));
      expect(tester.getCenter(picture).dy, moreOrLessEquals(tester.getCenter(artist).dy, epsilon: 1));
      await tester.tap(picture);
      await tester.pumpAndSettle();
      expect(find.byType(ArtistPage), findsOneWidget, reason: 'the picture is part of the link');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('an album of an hour or more says how long in hours and minutes', (tester) async {
    await pumpAlbum(tester, more: 20); // 494 seconds, and 20 songs of 200
    expect(find.textContaining(' · 1975 · 22 faixas, 1 h 14 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('over the songs, a header names their columns, lined up with them: #, the title, the duration', (
    tester,
  ) async {
    await pumpAlbum(tester);
    final first = song('Walk This Way');
    expect(
      tester.getRect(find.text('#')).right,
      tester.getRect(find.descendant(of: first, matching: find.text('1'))).right,
    );
    expect(tester.getRect(find.text('Título')).left, tester.getRect(find.text('Walk This Way')).left);
    expect(
      tester.getRect(find.byTooltip('Duração')).right,
      moreOrLessEquals(tester.getRect(find.text('3:40')).right, epsilon: 1),
    );
    expect(tester.getRect(find.text('Título')).bottom, lessThan(tester.getRect(first).top));
    expect(Focus.maybeOf(tester.element(find.text('Título')))?.canRequestFocus ?? false, isFalse, reason: 'no stop');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, no header over the songs, which keep their numbers', (tester) async {
    await pumpAlbum(tester, size: const Size(360, 640));
    expect(find.text('Título'), findsNothing);
    expect(find.byTooltip('Duração'), findsNothing);
    expect(find.descendant(of: song('Walk This Way'), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: song('Walk This Way'), matching: find.text('3:40')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the album\'s name is in a bar with the back arrow, centered, which stays as the page scrolls '
    'under it and the system\'s, taking the page\'s color, and the cover is under them',
    (tester) async {
      await pumpAlbum(tester, more: 20, size: const Size(360, 640));
      tester.view.padding = const FakeViewPadding(top: 24);
      final opened = Navigator.of(tester.element(find.byType(AlbumPage))).push(
        MaterialPageRoute<void>(
          builder: (context) => const AlbumPage(Album(id: 'a1', name: 'Toys in the Attic')),
        ),
      );
      await tester.pumpAndSettle();
      final page = find.byType(AlbumPage).last;
      final title = find.descendant(of: find.byType(AppBar), matching: find.text('Toys in the Attic'));
      final (arrow, name) = (tester.getRect(find.byType(BackButton)), tester.getRect(title));
      final cover = tester.getRect(find.byTooltip('Ver a capa'));
      expect(
        find.descendant(of: page, matching: find.text('Toys in the Attic')),
        findsOneWidget,
        reason: 'there alone',
      );
      expect(arrow.center.dy, 24 + kToolbarHeight / 2, reason: 'under the system\'s bar');
      expect(name.center.dy, moreOrLessEquals(arrow.center.dy, epsilon: 1), reason: 'on the arrow\'s line');
      expect(name.center.dx, moreOrLessEquals(180, epsilon: 1), reason: 'centered on the page');
      expect(name.left, greaterThanOrEqualTo(arrow.right));
      expect(cover.top, 24 + kToolbarHeight + 8, reason: 'under them');
      final list = find.descendant(of: page, matching: find.byType(CustomScrollView));
      expect(tester.getRect(list).top, 0, reason: 'the page goes on under the bars, to the top of the screen');
      // Clear at the top of the page, more of the page's color as the cover goes up under the bar, all of it once half
      // the cover has.
      final appBar = find.descendant(of: page, matching: find.byType(AppBar));
      Color bar() => tester.widget<Material>(find.descendant(of: appBar, matching: find.byType(Material)).first).color!;
      expect(bar().a, 0);

      await tester.drag(list, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(bar().a, inExclusiveRange(0, 1), reason: 'some of it');

      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byTooltip('Ver a capa')).top, lessThan(0), reason: 'the cover gone up under the bars');
      expect(bar().a, 1, reason: 'all of it');
      expect((tester.getRect(find.byType(BackButton)), tester.getRect(title)), (arrow, name), reason: 'the bar stays');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await opened;
      expect(find.byType(BackButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a wide screen, the album\'s name and byline are beside its cover, the play button under them', (
    tester,
  ) async {
    await pumpAlbum(tester);
    final cover = tester.getRect(find.byTooltip('Ver a capa'));
    final name = tester.getRect(find.text('Toys in the Attic'));
    final byline = tester.getRect(find.textContaining(' · 1975 · 2 faixas, 8 min'));
    final play = tester.getRect(playButton);
    expect(name.left, greaterThan(cover.right));
    expect(play.bottom, lessThanOrEqualTo(cover.bottom), reason: 'all beside it');
    expect((byline.left, play.left), (name.left, name.left));
    expect(play.top, greaterThan(byline.bottom));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, the byline is under the cover, from the page\'s margin, the play button at the end of its line',
    (tester) async {
      await pumpAlbum(tester, size: const Size(360, 640));
      await pushAlbum(tester);
      final cover = tester.getRect(find.byTooltip('Ver a capa'));
      // The artist with their picture, which the songs' have not.
      final artist = tester.getRect(find.ancestor(of: coverOf('ar-ar1'), matching: find.byTooltip('Abrir o artista')));
      final details = tester.getRect(find.text('1975 · 2 faixas, 8 min'));
      final play = tester.getRect(playButton);
      expect(artist.top, greaterThanOrEqualTo(cover.bottom));
      expect(details.top, greaterThanOrEqualTo(artist.bottom), reason: 'the year and the songs under the artist');
      expect((artist.left, details.left), (16, 16), reason: 'from the page\'s margin, not the cover\'s');
      expect(cover.left, greaterThan(16));
      expect(play.right, 360 - 16);

      for (final text in [artist, details]) {
        expect(play.left, greaterThanOrEqualTo(text.right));
      }

      expect(play.center.dy, moreOrLessEquals((artist.top + details.bottom) / 2, epsilon: 1));
      expect(play.bottom, lessThan(tester.getRect(song('Walk This Way')).top));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a phone, the cover is centered, as wide as the page less its margins, up to 280', (tester) async {
    for (final (width, side) in [(300.0, 300.0 - 2 * 16), (360.0, 280.0)]) {
      await pumpAlbum(tester, size: Size(width, 800));
      await pushAlbum(tester);
      final cover = find.byTooltip('Ver a capa');
      expect(tester.getSize(cover), Size.square(side), reason: '$width');
      expect(tester.getCenter(cover).dx, width / 2, reason: '$width');
      expect(
        find.descendant(of: cover, matching: coverAt(800)),
        findsOneWidget,
        reason: 'asked of the server as the player\'s, for a phone\'s pixels',
      );
      expect(
        find.descendant(of: cover, matching: coverAt(300)),
        findsOneWidget,
        reason: 'under it, as it comes',
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('on a wide screen, once the cover has gone up, the album\'s name stays in a bar at the top of the page, '
      'after the play button, coming in with the page\'s color; nothing there until then, where the cover takes taps', (
    tester,
  ) async {
    final engine = await pumpAlbum(tester, more: 20);
    final list = find.byType(CustomScrollView);
    final position = tester
        .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)))
        .position;
    Finder inBar(Finder finder) => find.descendant(of: find.byType(PageBarSliver), matching: finder);
    double shown() => tester.widget<Opacity>(inBar(find.byType(Opacity))).opacity;
    expect(inBar(find.byType(Opacity)), findsNothing, reason: 'nothing while the cover shows');
    expect(find.byTooltip('Ver a capa').hitTestable(at: Alignment.topCenter), findsOneWidget, reason: 'to its top');

    position.jumpTo(150);
    await tester.pumpAndSettle();
    expect(shown(), inExclusiveRange(0, 1), reason: 'coming in as the cover goes up');

    position.jumpTo(300);
    await tester.pumpAndSettle();
    expect(shown(), 1, reason: 'the cover gone');
    final (page, bar) = (tester.getRect(list), tester.getRect(inBar(find.byType(Material)).first));
    expect(bar, Rect.fromLTWH(page.left, page.top, page.width, kToolbarHeight + 1), reason: 'at the top, a line under');
    final play = tester.getRect(inBar(find.byTooltip('Tocar o álbum')));
    final name = tester.getRect(inBar(find.text('Toys in the Attic')));
    expect(name.left, greaterThan(play.right), reason: 'after the play button');
    expect(name.center.dy, moreOrLessEquals(page.top + kToolbarHeight / 2, epsilon: 1));
    expect(play.center.dy, moreOrLessEquals(page.top + kToolbarHeight / 2, epsilon: 1));

    await tester.tap(inBar(find.byTooltip('Tocar o álbum')));
    await tester.pumpAndSettle();
    expect(engine.tracks, hasLength(22), reason: 'the album, from its first song');
    expect(engine.index, 0);

    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(inBar(find.byType(Opacity)), findsNothing, reason: 'gone with the cover back');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a window widened with the page scrolled a little shows no bar yet, where a phone\'s had some color', (
    tester,
  ) async {
    await pumpAlbum(tester, more: 20, size: const Size(360, 640));
    final list = find.byType(CustomScrollView);
    tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable))).position.jumpTo(100);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(PageBarSliver), matching: find.byType(Opacity)), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a wide screen, as the keyboard or a remote goes up the songs, the one it comes to is clear of the bar',
    (tester) async {
      await pumpAlbum(tester, more: 20);

      for (
        var i = 0;
        i < 10 && FocusManager.instance.primaryFocus?.rect != tester.getRect(song('Walk This Way'));
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }

      for (var i = 0; i < 21; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }

      final bar = find.descendant(of: find.byType(PageBarSliver), matching: find.byType(Material)).first;
      expect(bar, findsOneWidget, reason: 'down at the last song');

      for (var i = 20; i > 0; i--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus!.rect;
        expect(focused, tester.getRect(song(i == 1 ? 'Sweet Emotion' : 'Song ${i - 1}')));

        if (bar.evaluate().isNotEmpty) {
          expect(focused.top, greaterThanOrEqualTo(tester.getRect(bar).bottom), reason: 'under the bar, at song $i');
        }
      }

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a wide screen, the cover is 220, asked of the server as the phone\'s', (tester) async {
    await pumpAlbum(tester);
    final cover = find.byTooltip('Ver a capa');
    expect(tester.getSize(cover), const Size.square(220));
    expect(find.descendant(of: cover, matching: coverAt(800)), findsOneWidget);
    expect(
      find.descendant(of: cover, matching: coverAt(300)),
      findsOneWidget,
      reason: 'under it, as it comes',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song\'s number and duration are as big as the artist\'s line beside them, in its title\'s color', (
    tester,
  ) async {
    await pumpAlbum(tester);
    TextStyle? style(Finder text) => tester.renderObject<RenderParagraph>(text).text.style;
    Finder inSong(String title, String text) => find.descendant(of: song(title), matching: find.text(text));
    final (number, duration) = (inSong('Walk This Way', '1'), inSong('Walk This Way', '3:40'));
    final artist = inSong('Walk This Way', 'Aerosmith');

    for (final (column, text) in [('number', number), ('duration', duration)]) {
      expect(style(text)?.fontSize, style(artist)?.fontSize, reason: column);
      expect(style(text)?.fontSize, greaterThan(11), reason: '$column, bigger than a list tile\'s own');
    }

    await tester.tap(find.text('Walk This Way'));
    await tester.pump();
    await tester.pump(kThemeChangeDuration); // the tile's colors change in this
    expect(
      style(duration)?.color,
      style(inSong('Walk This Way', 'Walk This Way'))?.color,
      reason: 'the song that plays',
    );
    final (otherNumber, otherDuration) = (inSong('Sweet Emotion', '2'), inSong('Sweet Emotion', '4:34'));
    expect(style(duration)?.color, isNot(style(otherDuration)?.color), reason: 'unlike the song that doesn\'t play');
    expect(style(otherNumber)?.color, style(otherDuration)?.color, reason: 'its number, as its duration');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only the artist\'s name is a link: the rest of its line, under the mouse, is the song\'s', (
    tester,
  ) async {
    final engine = await pumpAlbum(tester);
    final artist = find.descendant(of: song('Walk This Way'), matching: find.text('Aerosmith'));
    TextDecoration? decoration() => tester.widget<Text>(artist).style?.decoration;
    // On the artist's line, halfway along the song: well past their name.
    final besideName = Offset(tester.getCenter(song('Walk This Way')).dx, tester.getCenter(artist).dy);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(besideName);
    await tester.pump();
    expect(decoration(), isNot(TextDecoration.underline));
    await mouse.down(besideName);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsNothing);
    expect(engine.tracks, isNotEmpty, reason: 'the song played');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after the last song, the album\'s release date and its record labels, lined up with its cover', (
    tester,
  ) async {
    await pumpAlbum(tester, releaseDate: {'year': 1975, 'month': 4, 'day': 8}, recordLabels: ['Columbia', 'Sony']);
    final (date, labels) = (find.text('8 de abril de 1975'), find.text('Columbia, Sony'));
    expect(tester.getRect(date).top, greaterThan(tester.getRect(song('Sweet Emotion')).bottom));
    expect(tester.getRect(labels).top, greaterThanOrEqualTo(tester.getRect(date).bottom));
    expect(tester.getRect(date).left, tester.getRect(find.byTooltip('Ver a capa')).left);
    expect(tester.getRect(labels).left, tester.getRect(date).left);

    for (final text in [date, labels]) {
      expect(Focus.maybeOf(tester.element(text))?.canRequestFocus ?? false, isFalse, reason: 'no stop');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a wide screen, the album\'s type is above its name, lined up with it', (tester) async {
    await pumpAlbum(tester, releaseTypes: ['EP']);
    final (type, name) = (tester.getRect(find.text('EP')), tester.getRect(find.text('Toys in the Attic')));
    expect(type.bottom, lessThanOrEqualTo(name.top));
    expect(type.left, name.left);
    expect(find.textContaining('EP ·'), findsNothing, reason: 'not in the byline too');
    expect(find.byTooltip('Tocar o EP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, the album\'s type is before its year, under the artist', (tester) async {
    await pumpAlbum(tester, releaseTypes: ['EP'], size: const Size(360, 640));
    expect(find.text('EP · 1975 · 2 faixas, 8 min'), findsOneWidget);
    expect(find.text('EP'), findsNothing, reason: 'not above the name too');
    expect(find.byTooltip('Tocar o EP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('each type has its name, which the play button says too; an album the server says nothing of has none', (
    tester,
  ) async {
    for (final (types, name, play) in [
      (['album'], 'Álbum', 'Tocar o álbum'),
      (['single'], 'Single', 'Tocar o single'),
      (['album', 'compilation'], 'Coletânea', 'Tocar a coletânea'),
    ]) {
      await pumpAlbum(tester, releaseTypes: types);
      expect(find.text(name), findsOneWidget, reason: '$types');
      expect(find.byTooltip(play), findsOneWidget, reason: '$types');
      await tester.pumpWidget(const SizedBox());
    }

    await pumpAlbum(tester);
    expect(find.text('Álbum'), findsNothing, reason: 'not an album where it doesn\'t say');
    expect(find.byTooltip('Tocar o álbum'), findsOneWidget, reason: 'but its play button says album');
    expect(find.text('Toys in the Attic'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('where the server says no release date or type, MusicBrainz\'s, as they come', (tester) async {
    final brainz = MusicBrainz(
      spacing: Duration.zero,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'release-groups': [
              {
                'title': 'Toys in the Attic',
                'first-release-date': '1975-04-08',
                'primary-type': 'EP',
                'artist-credit': [
                  {'name': 'Aerosmith', 'joinphrase': ''},
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );
    await pumpAlbum(tester, musicBrainz: brainz);
    expect(find.text('8 de abril de 1975'), findsOneWidget);
    expect(find.text('EP'), findsOneWidget);
    expect(find.byTooltip('Tocar o EP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the release date as precisely as the server knows it', (tester) async {
    for (final (date, text) in [
      ({'year': 1975, 'month': 4, 'day': 1}, '1º de abril de 1975'),
      ({'year': 1975, 'month': 4}, 'abril de 1975'),
      ({'year': 1975}, '1975'),
    ]) {
      await pumpAlbum(tester, releaseDate: date);
      expect(find.text(text), findsOneWidget, reason: '$date');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('as the keyboard or a remote comes to the last song, the list scrolls on to the labels', (tester) async {
    await pumpAlbum(tester, more: 20, recordLabels: ['Columbia']);

    for (var i = 0; i < 10 && FocusManager.instance.primaryFocus?.rect != tester.getRect(song('Walk This Way')); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    for (var i = 0; i < 21; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }

    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(song('Song 20')));
    expect(
      tester.getRect(find.text('Columbia')).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(CustomScrollView)).bottom),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song\'s artist takes no focus: for the keyboard and a remote, each song is one stop', (tester) async {
    await pumpAlbum(tester);

    for (var i = 0; i < 10 && FocusManager.instance.primaryFocus?.rect != tester.getRect(song('Walk This Way')); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(song('Walk This Way')));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.rect, tester.getRect(song('Sweet Emotion')));
    await tester.pumpWidget(const SizedBox());
  });
}
