import 'dart:math';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/browse_tree.dart';
import 'package:segue/server/favorites.dart';
import 'package:segue/server/models.dart';
import 'package:segue/subsonic/api.dart';

import 'music_library.dart';

/// The key of an item's group title, which the car shows over the group.
const groupTitle = 'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';

/// The tree of [musicLibrary], in Portuguese, its covers at `cover:<id>`; out of reach with [offline].
BrowseTree tree({SubsonicApi? api, bool favorites = true, bool offline = false}) {
  final server = api ?? musicLibrary();

  return BrowseTree(
    server,
    strings: () => lookupAppLocalizations(const Locale('pt')),
    coverUri: (id) => id == null ? null : Uri.parse('cover:$id'),
    favorites: favorites ? Favorites(server) : null,
    offline: () => offline,
    random: Random(1),
  );
}

/// What [items] are: each one's title, and what it is under ("Mixes", "Lançamentos").
List<(String, Object?)> titles(List<MediaItem> items) => [
  for (final item in items) (item.title, item.extras?[groupTitle]),
];

/// The titles of the songs that [queue] plays, and the place of the first of them.
List<Object>? played((List<Song>, int)? queue) =>
    queue == null ? null : [for (final song in queue.$1) song.title, queue.$2];

void main() {
  test('at the root, the car has four tabs: the home, the playlists, the albums and the artists, which open', () async {
    final tabs = await tree().children(AudioService.browsableRootId);
    expect(titles(tabs), [('Início', null), ('Playlists', null), ('Álbuns', null), ('Artistas', null)]);
    expect(tabs.every((tab) => tab.playable == false), isTrue);
  });

  test(
    'the home has the mixes, which play, then the rows of albums, each album in the first one that has it',
    () async {
      final home = await tree().children(BrowseTree.home);
      final mixes = home.where((item) => item.extras?[groupTitle] == 'Mixes').toList();
      expect(mixes, isNotEmpty);
      expect(mixes.every((mix) => mix.playable ?? false), isTrue);
      expect(home.take(mixes.length), mixes, reason: 'first');
      expect(mixes.map((mix) => mix.title), containsAll(['Rock', 'Jazz']));
      expect(mixes.firstWhere((mix) => mix.title == 'Jazz').artist, 'Miles Davis', reason: 'its first songs\' artists');
      expect(
        mixes.firstWhere((mix) => mix.title == 'Jazz').artUri,
        Uri.parse('cover:al-a3'),
        reason: 'its first song\'s',
      );

      expect(titles(home.skip(mixes.length).toList()), [
        ('Pump', 'Lançamentos'),
        ('Toys in the Attic', 'Lançamentos'),
        ('Kind of Blue', 'Lançamentos'),
      ]);
      expect(home.last.playable, isFalse, reason: 'an album opens');
      expect(home.last.artUri, Uri.parse('cover:al-a3'));
    },
  );

  test('out of reach, the home has the downloaded albums alone', () async {
    expect(titles(await tree(offline: true).children(BrowseTree.home)), [
      ('Kind of Blue', 'Baixados'),
      ('Pump', 'Baixados'),
    ]);
  });

  test('an album opens its radio, then its songs, each of which plays the album from it', () async {
    final browse = tree();
    final albums = await browse.children(BrowseTree.albums);
    expect(titles(albums).map((album) => album.$1), ['Kind of Blue', 'Pump', 'Toys in the Attic'], reason: 'by name');

    final songs = await browse.children(albums.last.id);
    expect(songs.map((song) => song.title), ['Rádio do álbum', 'Sweet Emotion', 'Walk This Way']);
    expect(songs.every((song) => song.playable ?? false), isTrue);
    expect(songs[1].artist, 'Aerosmith');
    expect(played(await browse.queueOf(songs.last.id)), ['Sweet Emotion', 'Walk This Way', 1]);
    expect(await browse.queueOf(albums.last.id), isNull, reason: 'an album opens, rather than play');
    expect(played(await browse.queueOf(songs.first.id)), [
      'Love in an Elevator',
      'So What',
      0,
    ], reason: 'songs like the album\'s');
  });

  test('the playlists have the favorite songs first, then the playlists by name, which play from a song', () async {
    final browse = tree();
    final playlists = await browse.children(BrowseTree.playlists);
    expect(titles(playlists).map((playlist) => playlist.$1), ['Músicas favoritas', 'chill', 'Road trip']);

    final favorite = await browse.children(playlists.first.id);
    expect(favorite.map((song) => song.title), ['Love in an Elevator']);
    expect(played(await browse.queueOf(favorite.single.id)), ['Love in an Elevator', 0]);

    final roadTrip = await browse.children(playlists.last.id);
    expect(roadTrip.map((song) => song.title), ['Walk This Way', 'So What']);
    expect(played(await browse.queueOf(roadTrip.last.id)), ['Walk This Way', 'So What', 1]);

    expect(titles(await tree(favorites: false).children(BrowseTree.playlists)).map((playlist) => playlist.$1), [
      'chill',
      'Road trip',
    ], reason: 'none, without favorite songs');
  });

  test('an artist opens their radio, which plays, then their albums', () async {
    final browse = tree();
    final artists = await browse.children(BrowseTree.artists);
    expect(artists.map((artist) => artist.title), ['Aerosmith', 'Miles Davis']);
    expect(artists.first.artUri, Uri.parse('cover:ar-ar1'));
    final items = await browse.children(artists.first.id);
    expect(items.map((item) => item.title), ['Rádio do artista', 'Toys in the Attic', 'Pump']);
    expect(items.map((item) => item.playable), [true, false, false]);
    expect(items.first.artUri, Uri.parse('cover:ar-ar1'));
    expect(played(await browse.queueOf(items.first.id)), ['So What', 0], reason: 'songs like theirs');
  });

  test('a mix plays its first songs, then more of its own', () async {
    final browse = tree();
    final jazz = (await browse.children(BrowseTree.home)).firstWhere((item) => item.title == 'Jazz');
    expect(played(await browse.queueOf(jazz.id)), ['So What', 0]);
  });

  test('a search typed in the car finds songs, which play alone, then albums and artists, which open', () async {
    final browse = tree();
    final found = await browse.search('a');
    expect(titles(found).where((item) => item.$2 == 'Músicas').map((song) => song.$1), [
      'Walk This Way',
      'Love in an Elevator',
      'So What',
    ]);
    expect(titles(found).where((item) => item.$2 == 'Álbuns'), isNotEmpty);
    expect(titles(found).where((item) => item.$2 == 'Artistas').map((artist) => artist.$1), [
      'Aerosmith',
      'Miles Davis',
    ]);

    final walk = found.firstWhere((item) => item.title == 'Walk This Way');
    expect(played(await browse.queueOf(walk.id)), ['Walk This Way', 0]);
  });

  group('said to the car', () {
    test('words that name an artist play their songs, mixed', () async {
      final queue = (await tree().queueForVoice('aerosmith'))!;
      expect(
        queue.$1.map((song) => song.title),
        unorderedEquals(['Sweet Emotion', 'Walk This Way', 'Love in an Elevator']),
      );
      expect(queue.$2, 0);
    });

    test('words that name an album play it, and a song\'s, the song alone', () async {
      expect(played(await tree().queueForVoice('Pump')), ['Love in an Elevator', 0]);
      expect(played(await tree().queueForVoice('so what')), ['So What', 0]);
      expect(played(await tree().queueForVoice('emotion')), ['Sweet Emotion', 0], reason: 'the song found first');
    });

    test('what Android took the words for goes first: an album, an artist, a song, a playlist, a genre', () async {
      expect(
        played(
          await tree().queueForVoice('toys', {
            'android.intent.extra.focus': 'vnd.android.cursor.item/album',
            'android.intent.extra.album': 'Toys in the Attic',
          }),
        ),
        ['Sweet Emotion', 'Walk This Way', 0],
      );
      expect(
        played(
          await tree().queueForVoice('miles davis', {
            'android.intent.extra.focus': 'vnd.android.cursor.item/artist',
            'android.intent.extra.artist': 'Miles Davis',
          }),
        ),
        ['So What', 0],
      );
      expect(
        played(
          await tree().queueForVoice('walk this way by aerosmith', {
            'android.intent.extra.title': 'Walk This Way',
            'android.intent.extra.artist': 'Aerosmith',
          }),
        ),
        ['Walk This Way', 0],
      );
      expect(
        played(
          await tree().queueForVoice('road trip', {
            'android.intent.extra.focus': 'vnd.android.cursor.item/playlist',
            'android.intent.extra.playlist': 'road trip',
          }),
        ),
        ['Walk This Way', 'So What', 0],
      );
      expect(
        played(
          await tree().queueForVoice('jazz', {
            'android.intent.extra.focus': 'vnd.android.cursor.item/genre',
            'android.intent.extra.genre': 'Jazz',
          }),
        ),
        ['So What', 0],
      );
    });

    test('nothing found, nothing plays; nothing said is said so', () async {
      expect(await tree().queueForVoice('zzz'), isNull);
      expect(BrowseTree.saysNothing(''), isTrue);
      expect(BrowseTree.saysNothing(' ', {'android.intent.extra.focus': 'vnd.android.cursor.item/*'}), isTrue);
      expect(BrowseTree.saysNothing('', {'android.intent.extra.artist': 'Aerosmith'}), isFalse);
      expect(BrowseTree.saysNothing('jazz'), isFalse);
      expect((await tree().anything())?.$1, hasLength(4), reason: 'songs at random');
    });
  });

  test('an id of another tree, or of nothing, has nothing under it, and plays nothing', () async {
    expect(await tree().children('nowhere'), isEmpty);
    expect(await tree().children('%'), isEmpty);
    expect(await tree().queueOf('album/a1/9'), isNull);
    expect(await tree().queueOf('mix/0'), isNull, reason: 'before the home has shown its mixes');
  });
}
