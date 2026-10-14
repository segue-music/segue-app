import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/equalizer_choice.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/language_choice.dart';
import 'package:segue/player/player.dart';
import 'package:segue/quality_choice.dart';
import 'package:segue/replay_gain_choice.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/settings.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/theme_choice.dart';
import 'package:segue/ui/album/credits_page.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/app/login_page.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/artist/artist_page.dart';
import 'package:segue/ui/artist/biography_page.dart';
import 'package:segue/ui/player/queue_page.dart';
import 'package:segue/ui/settings/settings_page.dart';

import 'fakes.dart';
import 'sections.dart';

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

const playlist = {'id': 'p1', 'name': 'Road trip', 'songCount': 2};

const songs = [
  {
    'id': 's1',
    'title': 'Toys in the Attic',
    'artist': 'Aerosmith',
    'albumId': 'a1',
    'artistId': 'ar1',
    'duration': 185,
    'contributors': [
      {
        'role': 'performer',
        'subRole': 'lead vocals',
        'artist': {'id': 'ar3', 'name': 'Steven Tyler'},
      },
      {
        'role': 'performer',
        'subRole': 'harmonica',
        'artist': {'id': 'ar3', 'name': 'Steven Tyler'},
      },
      {
        'role': 'composer',
        'artist': {'id': 'ar3', 'name': 'Steven Tyler'},
      },
      {
        'role': 'producer',
        'artist': {'id': 'ar5', 'name': 'Jack Douglas'},
      },
    ],
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
/// the artist's popular ones, and its mixes', and a playlist of them. The artist has a biography, Last.fm's, and an artist like them.
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
    'getArtistInfo2.view' => subsonic({
      'artistInfo2': {
        'biography':
            'Aerosmith is an American rock band formed in Boston in 1970. <a target=\'_blank\' '
            'href="https://www.last.fm/music/Aerosmith" rel="nofollow">Read more on Last.fm</a>',
        'similarArtist': [
          {'id': 'ar2', 'name': 'Cheap Trick', 'albumCount': 1},
        ],
      },
    }),
    'getTopSongs.view' => subsonic({
      'topSongs': {'song': songs},
    }),
    'getRandomSongs.view' => subsonic({
      'randomSongs': {'song': songs},
    }),
    'getGenres.view' => subsonic({
      'genres': {
        'genre': [
          {'value': 'Rock', 'albumCount': 2, 'songCount': 20},
        ],
      },
    }),
    'getPlaylists.view' => subsonic({
      'playlists': {
        'playlist': [playlist],
      },
    }),
    'getPlaylist.view' => subsonic({
      'playlist': {...playlist, 'entry': songs},
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

/// The home on a screen of [size], in [language], with Sweet Emotion in the player and the app's version in the settings.
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
        artists: const [Artist(id: 'ar1', name: 'Aerosmith')],
        duration: Duration(seconds: song['duration']! as int),
      ),
  ], play: false);

  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'laptop'),
    api,
    player,
    ConnectController(player: player),
  );
  final settings = Settings(
    language: LanguageChoice(language),
    // As on a phone, with the automatic quality, and what it does under it.
    quality: QualityChoice(mobileData: true),
    // Its bands as far as they go, with the widest numbers.
    equalizer: EqualizerChoice(
      const EqualizerSettings(
        on: true,
        preset: EqualizerPreset.custom,
        custom: [-12, 12, -12, 12, -12, 12, -12, 12, -12, 12],
      ),
    ),
  );

  addTearDown(settings.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: language,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: segueTheme(Brightness.light),
      builder: (context, child) => SettingsScope(
        settings: settings,
        child: ServicesScope(services: services, child: child!),
      ),
      home: HomePage(
        onSignOut: () {},
        packageInfo: PackageInfo(appName: 'Segue', packageName: 'segue', version: '0.1.0', buildNumber: '214'),
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
        expect(find.text(strings.mixes), findsOneWidget, reason: 'the home\'s first row');
        expect(find.text(strings.decade('1970')), findsOneWidget, reason: 'the album\'s, played');
        expect(find.text(strings.orderReleased), findsOneWidget);

        await tap(tester, find.byTooltip(strings.settings));
        expect(find.text(strings.appearance), findsOneWidget, reason: 'the settings');
        expect(find.text(strings.highContrastDetail), findsOneWidget);
        expect(find.text(strings.playback), findsOneWidget);

        final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable));
        // Each choice's sheet, with all its options and what they do, down the settings, clear of a phone's bars at the
        // bottom.
        for (final (choice, options) in [
          (strings.theme, [strings.systemTheme, strings.lightTheme, strings.darkTheme]),
          (strings.themeColors, [for (final palette in Palette.values) strings.paletteDetail(palette.name)]),
          (strings.language, [strings.systemLanguage, 'English', 'Español', 'Português']),
          (strings.audioQuality, [strings.streamQuality('original', 0), strings.automaticQualityDetail(160)]),
          (
            strings.volumeNormalization,
            [for (final mode in ReplayGainMode.values) strings.replayGainModeDetail(mode.name)],
          ),
        ]) {
          final line = find.widgetWithText(ListTile, choice).hitTestable();

          await tester.scrollUntilVisible(line, 100, scrollable: list);
          await tap(tester, line);

          for (final text in options) {
            expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(text)), findsOneWidget);
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }

        // Down to the end, clear of a phone's bars at the bottom, and from there to the equalizer's page.
        await tester.scrollUntilVisible(find.text(strings.signedInAs('a', 'music.test')), 100, scrollable: list);
        expect(find.text(strings.about), findsOneWidget);
        expect(find.text(strings.appVersionNumber('0.1.0', '214')), findsOneWidget);
        expect(find.text(strings.openSourceLicenses), findsOneWidget);
        expect(find.text(strings.signOut), findsOneWidget);
        expect(find.text(strings.signInTv), findsOneWidget);
        expect(find.text(strings.signInTvDetail), findsOneWidget);
        // Back up to the crossfade, which the lines at the end took above the top on a phone.
        await tester.scrollUntilVisible(find.text(strings.crossfade).hitTestable(), -100, scrollable: list);
        await tap(tester, find.text(strings.crossfade).hitTestable());

        for (final text in [strings.crossfadeOffDetail, strings.crossfadeLength(12)]) {
          expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(text)), findsOneWidget);
        }

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        // Back up to the equalizer, which the crossfade's line took below the top.
        await tester.scrollUntilVisible(find.text(strings.equalizer).hitTestable(), -100, scrollable: list);
        await tap(tester, find.text(strings.equalizer).hitTestable());
        expect(find.text(strings.useEqualizer), findsOneWidget);

        for (final preset in EqualizerPreset.values) {
          expect(find.widgetWithText(ChoiceChip, strings.equalizerPreset(preset.name)), findsOneWidget);
        }

        expect(find.text(strings.kilohertzShort(16)), findsOneWidget);
        await tap(tester, narrow ? find.byType(BackButton).hitTestable() : find.byTooltip(strings.back));
        // On a phone the page's arrow; on a wide screen the top bar's.
        await tap(tester, narrow ? find.byType(BackButton).hitTestable() : find.byTooltip(strings.back));

        await openSection(tester, strings.albums, strings: strings);
        expect(find.widgetWithText(ChoiceChip, strings.orderLatest), findsOneWidget);

        await openSection(tester, strings.artists, strings: strings);
        expect(find.widgetWithText(ChoiceChip, strings.orderName).hitTestable(), findsOneWidget);

        await openSection(tester, strings.genres, strings: strings);
        expect(find.text(strings.albumCount(2)), findsOneWidget);

        await openSection(tester, strings.playlists, strings: strings);
        expect(find.text(strings.trackCount(2)), findsOneWidget);
        await tap(tester, find.text('Road trip'));
        expect(find.byTooltip(strings.playPlaylist), findsOneWidget);
        expect(find.textContaining(strings.trackCount(2)), findsOneWidget);
        // Its menu, and a song's.
        await tap(tester, find.byTooltip(strings.moreOptions).first);
        expect(find.text(strings.renamePlaylist), findsOneWidget);
        await tap(tester, find.text(strings.deletePlaylist));
        expect(find.text(strings.deletePlaylistDetail), findsOneWidget);
        await tap(tester, find.text(strings.cancel));
        await tap(tester, find.byTooltip(strings.moreOptions).at(1)); // the first song's
        expect(find.text(strings.removeFromPlaylist), findsOneWidget);
        await tap(tester, find.text(strings.addToPlaylist));
        expect(find.text(strings.newPlaylist), findsOneWidget);
        await tap(tester, find.text(strings.newPlaylist));
        expect(find.text(strings.playlistName), findsOneWidget);
        await tap(tester, find.text(strings.cancel));

        await tap(tester, find.byTooltip(strings.home).first);
        // Under the mixes.
        await tester.ensureVisible(find.text('Toys in the Attic').first);
        await tester.pumpAndSettle();
        await tap(tester, find.text('Toys in the Attic').first);
        expect(find.byTooltip(strings.playRelease('album')), findsOneWidget);
        expect(find.textContaining(strings.trackCount(2)), findsOneWidget);
        // Its credits, from the button after how many songs it has.
        await tap(tester, find.byTooltip(strings.showCredits));
        expect(find.text(strings.creditSection('performance')), findsOneWidget);

        // All on the first of its two songs.
        final voice = strings.creditOnTracks(strings.creditPart('leadVocals', 'lead vocals'), 1, '1');
        final harmonica = strings.creditOnTracks(strings.creditPart('harmonica', 'harmonica'), 1, '1');

        expect(find.text('$voice, $harmonica'), findsOneWidget);
        expect(find.text(strings.creditOnTracks(strings.creditRole('producer'), 1, '1')), findsOneWidget);
        await tap(tester, find.descendant(of: find.byType(CreditsPage), matching: find.byTooltip(strings.close)));
        await tester.scrollUntilVisible(find.text('Columbia'), 100, scrollable: find.byType(Scrollable).last);
        expect(find.text(strings.releaseDay(8, language.languageCode == 'en' ? 'April' : 'abril', '1975')), findsOne);

        await tap(tester, find.text('Aerosmith').first);
        expect(find.text('${strings.albumCount(1)} · ${strings.epCount(1)}'), findsOneWidget);
        // On a phone, icons, their names in tooltips.
        expect(narrow ? find.byTooltip(strings.mostPlayedSongs) : find.text(strings.mostPlayedSongs), findsOneWidget);
        expect(narrow ? find.byTooltip(strings.popularSongs) : find.text(strings.popularSongs), findsOneWidget);
        // Their biography, from the button after how many albums they have.
        await tap(tester, find.byTooltip(strings.showBiography));
        expect(find.text(strings.biographyProvidedBy('Last.fm')), findsOneWidget);
        await tap(tester, find.descendant(of: find.byType(BiographyPage), matching: find.byTooltip(strings.close)));

        // Under the songs, the page scrolls to them.
        final page = find.descendant(of: find.byType(ArtistPage), matching: find.byType(Scrollable)).first;

        await tester.scrollUntilVisible(find.text(strings.singlesAndEps), 100, scrollable: page);
        // Then the artists like them.
        await tester.scrollUntilVisible(find.text(strings.similarArtists), 100, scrollable: page);

        await tap(tester, find.byTooltip(strings.openPlayer));
        await tap(tester, find.byTooltip(strings.showLyrics));
        expect(find.text('Sweet emotion'), findsOneWidget);

        await tap(tester, find.byTooltip(strings.queue));
        expect(find.text(strings.songTitle), findsOneWidget);
        // After the last song, autoplay's switch.
        await tester.scrollUntilVisible(
          find.text(strings.autoplayDetail),
          100,
          scrollable: find.descendant(of: find.byType(QueuePage), matching: find.byType(Scrollable)).first,
        );
        // On a wide screen, the top bar's arrow: the queue is in the page area, under it.
        await tap(tester, narrow ? find.byType(BackButton).hitTestable() : find.byTooltip(strings.back));

        await tap(tester, find.byTooltip(strings.devices).last);
        expect(find.text(strings.thisDevice('laptop')), findsOneWidget);
        expect(find.text(strings.noHubAt('music.test')), findsOneWidget);
        await tester.pumpWidget(const SizedBox()); // stops the player bar's timers
      });
    }

    testWidgets('in ${strings.languageName}, the sign-in has room for its words, its errors too', (tester) async {
      final settings = Settings(language: LanguageChoice(language));

      addTearDown(settings.dispose);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: language,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => SettingsScope(settings: settings, child: child!),
          home: LoginPage(onSignedIn: (_) {}),
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
