import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
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

import 'fakes.dart';

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// The page of Toys in the Attic, with the cover [coverArt], two songs by Aerosmith and then [more] songs, the release
/// date [releaseDate] and the record labels [recordLabels], on a screen of [size], with what [musicBrainz] adds.
/// Aerosmith's picture is `ar-ar1`. Returns the player's engine.
Future<FakeEngine> pumpAlbum(
  WidgetTester tester, {
  String? coverArt = 'al-a1',
  int more = 0,
  Map<String, int>? releaseDate,
  List<String> recordLabels = const [],
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
    expect(tester.getRect(find.byType(ListView)).bottom, 640);

    await tester.drag(find.byType(ListView), const Offset(0, -100000));
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

  testWidgets('where the server says no release date, MusicBrainz\'s, as it comes', (tester) async {
    final brainz = MusicBrainz(
      spacing: Duration.zero,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'release-groups': [
              {
                'title': 'Toys in the Attic',
                'first-release-date': '1975-04-08',
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
      lessThanOrEqualTo(tester.getRect(find.byType(ListView)).bottom),
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
