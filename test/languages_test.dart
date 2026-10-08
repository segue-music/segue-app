import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/language_choice.dart';
import 'package:segue/player/player.dart';
import 'package:segue/quality_choice.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/theme_choice.dart';
import 'package:segue/ui/artist_page.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/login_page.dart';
import 'package:segue/ui/settings_page.dart';
import 'package:segue/ui/theme.dart';

import 'fakes.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

const album = {
  'id': 'a1',
  'name': 'Toys in the Attic',
  'artist': 'Aerosmith',
  'artistId': 'ar1',
  'year': 1975,
  'releaseDate': {'year': 1975, 'month': 4, 'day': 8},
  'recordLabels': [
    {'name': 'Columbia'},
  ],
  'playCount': 1,
};

const songs = [
  {
    'id': 's1',
    'title': 'Toys in the Attic',
    'artist': 'Aerosmith',
    'albumId': 'a1',
    'artistId': 'ar1',
    'duration': 185,
  },
  {
    'id': 's2',
    'title': 'Sweet Emotion',
    'artist': 'Aerosmith',
    'albumId': 'a1',
    'artistId': 'ar1',
    'duration': 274,
    'playCount': 1,
  },
];

/// A library of an album and an EP by one artist, in one genre, whose songs have lyrics, one of them played, and are
/// the artist's popular ones.
http.Response server(http.Request request) {
  final path = request.url.path;

  return switch (path.split('/').last) {
    'getAlbumList2.view' => subsonic({
      'albumList2': {
        'album': [album],
      },
    }),
    'getAlbum.view' => subsonic({
      'album': {...album, 'song': songs},
    }),
    'getArtists.view' => subsonic({
      'artists': {
        'index': [
          {
            'name': 'A',
            'artist': [
              {'id': 'ar1', 'name': 'Aerosmith', 'albumCount': 2},
            ],
          },
        ],
      },
    }),
    'getArtist.view' => subsonic({
      'artist': {
        'id': 'ar1',
        'name': 'Aerosmith',
        'album': [
          album,
          {
            'id': 'a2',
            'name': 'Dream On',
            'artist': 'Aerosmith',
            'year': 1973,
            'releaseTypes': ['EP'],
          },
        ],
      },
    }),
    'getTopSongs.view' => subsonic({
      'topSongs': {'song': songs},
    }),
    'getGenres.view' => subsonic({
      'genres': {
        'genre': [
          {'value': 'Rock', 'albumCount': 2, 'songCount': 20},
        ],
      },
    }),
    'getLyricsBySongId.view' => subsonic({
      'lyricsList': {
        'structuredLyrics': [
          {
            'synced': false,
            'line': [
              {'value': 'Sweet emotion'},
            ],
          },
        ],
      },
    }),
    _ => http.Response('', 404),
  };
}

/// The home on a screen of [size], in [language], with Sweet Emotion in the player.
Future<void> pumpHome(WidgetTester tester, Locale language, Size size) async {
  final api = SubsonicApi(Uri.parse('https://music.test'), credentials, client: MockClient((r) async => server(r)));
  final player = PlayerController(FakeEngine(), api);
  await player.playQueue([
    for (final song in songs)
      Song(
        id: song['id']! as String,
        title: song['title']! as String,
        artist: 'Aerosmith',
        album: 'Toys in the Attic',
        albumId: 'a1',
        artistId: 'ar1',
        duration: Duration(seconds: song['duration']! as int),
      ),
  ], play: false);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'laptop'),
    api,
    player,
    ConnectController(player: player),
  );
  final themeChoice = ThemeChoice();
  addTearDown(themeChoice.dispose);
  final languageChoice = LanguageChoice(language);
  addTearDown(languageChoice.dispose);
  final qualityChoice = QualityChoice();
  addTearDown(qualityChoice.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: language,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: segueTheme(Brightness.light),
      builder: (context, child) => ServicesScope(services: services, child: child!),
      home: HomePage(
        onSignOut: () {},
        themeChoice: themeChoice,
        languageChoice: languageChoice,
        qualityChoice: qualityChoice,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  // Portuguese, the language the other tests read the app in, has every page; here are the others. A text too long for
  // its room fails the test, as Flutter's overflow errors do.
  for (final language in AppLocalizations.supportedLocales.where((language) => language.languageCode != 'pt')) {
    final strings = lookupAppLocalizations(language);

    for (final (screen, size) in [('a wide screen', const Size(1000, 700)), ('a phone', const Size(360, 640))]) {
      testWidgets('in ${strings.languageName}, on $screen, every section and page has room for its words', (
        tester,
      ) async {
        final narrow = size.width < 600;
        await pumpHome(tester, language, size);
        expect(find.text(strings.orderReleased), findsOneWidget, reason: 'the home\'s first row');

        await tap(tester, find.byTooltip(strings.settings));
        expect(find.text(strings.systemTheme), findsOneWidget, reason: 'the settings');
        // To their end, past the qualities.
        await tester.scrollUntilVisible(
          find.text(strings.signedInAs('a', 'music.test')),
          100,
          scrollable: find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable)),
        );
        expect(find.text(strings.automaticQualityDetail(160)), findsOneWidget, reason: 'the qualities');
        expect(find.text(strings.signOut), findsOneWidget);
        // On a phone the page's arrow; on a wide screen the top bar's.
        await tap(tester, narrow ? find.byType(BackButton).hitTestable() : find.byTooltip(strings.back));

        await tap(tester, narrow ? find.text(strings.albums) : find.byTooltip(strings.albums));
        expect(find.widgetWithText(ChoiceChip, strings.orderLatest), findsOneWidget);

        await tap(tester, narrow ? find.text(strings.artists) : find.byTooltip(strings.artists));
        expect(find.text(strings.albumCount(2)), findsOneWidget);

        await tap(tester, narrow ? find.text(strings.genres) : find.byTooltip(strings.genres));
        expect(find.text(strings.albumCount(2)), findsOneWidget);

        await tap(tester, find.byTooltip(strings.home).first);
        await tap(tester, find.text('Toys in the Attic').first);
        expect(find.byTooltip(strings.playRelease('album')), findsOneWidget);
        expect(find.textContaining(strings.trackCount(2)), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Columbia'), 100, scrollable: find.byType(Scrollable).last);
        expect(find.text(strings.releaseDay(8, language.languageCode == 'en' ? 'April' : 'abril', '1975')), findsOne);

        await tap(tester, find.text('Aerosmith').first);
        expect(find.text('${strings.albumCount(1)} · ${strings.epCount(1)}'), findsOneWidget);
        // On a phone, icons, their names in tooltips.
        expect(narrow ? find.byTooltip(strings.mostPlayedSongs) : find.text(strings.mostPlayedSongs), findsOneWidget);
        expect(narrow ? find.byTooltip(strings.popularSongs) : find.text(strings.popularSongs), findsOneWidget);
        // Under the songs, the page scrolls to them.
        final page = find.descendant(of: find.byType(ArtistPage), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text(strings.singlesAndEps), 100, scrollable: page);

        await tap(tester, find.byTooltip(strings.openPlayer));
        await tap(tester, find.byTooltip(strings.showLyrics));
        expect(find.text('Sweet emotion'), findsOneWidget);

        await tap(tester, find.byTooltip(strings.queue));
        expect(find.text(strings.songTitle), findsOneWidget);
        // On a wide screen, the top bar's arrow: the queue is in the page area, under it.
        await tap(tester, narrow ? find.byType(BackButton).hitTestable() : find.byTooltip(strings.back));

        await tap(tester, find.byTooltip(strings.devices).last);
        expect(find.text(strings.thisDevice('laptop')), findsOneWidget);
        expect(find.text(strings.noHubAt('music.test')), findsOneWidget);
        await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
      });
    }

    testWidgets('in ${strings.languageName}, the sign-in has room for its words, its errors too', (tester) async {
      final languageChoice = LanguageChoice(language);
      addTearDown(languageChoice.dispose);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: language,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginPage(onSignedIn: (_) {}, languageChoice: languageChoice),
        ),
      );
      await tap(tester, find.text(strings.advanced));
      expect(find.text(strings.hubAddressHelp), findsOneWidget);
      await tap(tester, find.text(strings.signIn));
      expect(find.text(strings.required), findsNWidgets(3));
      await tap(tester, find.byTooltip(strings.language));
      expect(find.text(strings.systemLanguage), findsOneWidget);
    });
  }
}
