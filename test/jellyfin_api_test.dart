import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/jellyfin/api.dart';
import 'package:segue/server/models.dart';
import 'package:segue/server/server.dart';

const credentials = JellyfinCredentials(username: 'alice', userId: 'u1', token: 'tok');

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

http.Response items(List<Map<String, Object?>> items) => json({'Items': items, 'TotalRecordCount': items.length});

/// An API whose server answers with [answer]; [asked] gets every request.
JellyfinApi jellyfin(http.Response Function(http.Request request) answer, [List<http.Request>? asked]) => JellyfinApi(
  Uri.parse('https://music.test/jellyfin'),
  credentials,
  deviceId: 'd1',
  deviceName: 'laptop',
  client: MockClient((request) async {
    asked?.add(request);
    return answer(request);
  }),
);

const album = {
  'Id': 'a1',
  'Name': 'Toys in the Attic',
  'Type': 'MusicAlbum',
  'AlbumArtist': 'Aerosmith',
  'AlbumArtists': [
    {'Name': 'Aerosmith', 'Id': 'ar1'},
  ],
  'ProductionYear': 1975,
  'ChildCount': 9,
  'ImageTags': {'Primary': 'tag'},
};

const song = {
  'Id': 's1',
  'Name': 'Walk This Way',
  'Type': 'Audio',
  'Artists': ['Aerosmith'],
  'ArtistItems': [
    {'Name': 'Aerosmith', 'Id': 'ar1'},
  ],
  'AlbumArtist': 'Aerosmith',
  'AlbumArtists': [
    {'Name': 'Aerosmith', 'Id': 'ar1'},
  ],
  'Album': 'Toys in the Attic',
  'AlbumId': 'a1',
  'AlbumPrimaryImageTag': 'tag',
  'RunTimeTicks': 2210000000,
  'ImageTags': <String, String>{},
};

const artist = {
  'Id': 'ar1',
  'Name': 'Aerosmith',
  'Type': 'MusicArtist',
  'ImageTags': {'Primary': 'tag'},
};

void main() {
  test('requests carry the token in the Authorization header, as this device', () async {
    final asked = <http.Request>[];
    await jellyfin((_) => items([]), asked).albums(order: AlbumOrder.latest);
    expect(
      asked.single.headers['Authorization'],
      'MediaBrowser Client="Segue", Device="laptop", DeviceId="d1", Version="$appVersion", Token="tok"',
    );
    expect(asked.single.url.path, '/jellyfin/Items');
    expect(asked.single.url.queryParameters, containsPair('userId', 'u1'));
  });

  test('albums: the latest added first, with their covers, artist, year and number of songs', () async {
    final asked = <http.Request>[];
    final albums = await jellyfin((_) => items([album]), asked).albums(order: AlbumOrder.latest, size: 20, offset: 40);
    final query = asked.single.url.queryParameters;
    expect(query, containsPair('IncludeItemTypes', 'MusicAlbum'));
    expect(query, containsPair('Recursive', 'true'));
    expect(query['SortBy'], startsWith('DateCreated'));
    expect(query, containsPair('SortOrder', 'Descending'));
    expect(query, containsPair('Limit', '20'));
    expect(query, containsPair('StartIndex', '40'));
    final first = albums.single;
    expect(
      (first.id, first.name, first.artist, first.year, first.songCount),
      ('a1', 'Toys in the Attic', 'Aerosmith', 1975, 9),
    );
    expect(first.coverArt, 'a1');
  });

  test('albums by name', () async {
    final asked = <http.Request>[];
    await jellyfin((_) => items([album]), asked).albums(order: AlbumOrder.name, size: 200, offset: 400);
    final query = asked.single.url.queryParameters;
    expect(query, containsPair('IncludeItemTypes', 'MusicAlbum'));
    expect(query['SortBy'], startsWith('SortName'));
    expect(query, containsPair('SortOrder', 'Ascending'));
    expect(query, containsPair('Limit', '200'));
    expect(query, containsPair('StartIndex', '400'));
  });

  test('albums by release date: the latest year first, and in a year the latest date', () async {
    final asked = <http.Request>[];
    await jellyfin((_) => items([album]), asked).albums(order: AlbumOrder.released, size: 20, offset: 40);
    final query = asked.single.url.queryParameters;
    expect(query, containsPair('IncludeItemTypes', 'MusicAlbum'));
    expect(query['SortBy'], startsWith('ProductionYear,PremiereDate'));
    expect(query, containsPair('SortOrder', 'Descending'));
    expect(query, containsPair('Limit', '20'));
    expect(query, containsPair('StartIndex', '40'));
  });

  test('genres are the music genres, with their number of albums, and a genre\'s albums those of its id', () async {
    final asked = <http.Request>[];
    final api = jellyfin(
      (request) => request.url.path.endsWith('MusicGenres')
          ? items([
              {'Id': 'g1', 'Name': 'Hard Rock', 'Type': 'MusicGenre', 'AlbumCount': 3},
            ])
          : items([album]),
      asked,
    );
    final genre = (await api.genres()).single;
    expect((genre.id, genre.name, genre.albumCount), ('g1', 'Hard Rock', 3));
    expect(asked.single.url.path, '/jellyfin/MusicGenres');
    expect(asked.single.url.queryParameters, containsPair('userId', 'u1'));
    expect(asked.single.url.queryParameters, containsPair('Fields', 'ItemCounts'));

    final albums = await api.genreAlbums('g1', size: 20, offset: 40);
    expect(albums.single.name, 'Toys in the Attic');
    final query = asked.last.url.queryParameters;
    expect(asked.last.url.path, '/jellyfin/Items');
    expect(query, containsPair('GenreIds', 'g1'));
    expect(query, containsPair('IncludeItemTypes', 'MusicAlbum'));
    expect(query['SortBy'], startsWith('SortName'));
    expect(query, containsPair('SortOrder', 'Ascending'));
    expect(query, containsPair('Limit', '20'));
    expect(query, containsPair('StartIndex', '40'));
  });

  test('a genre without its number of albums has none', () async {
    final genres = await jellyfin(
      (_) => items([
        {'Id': 'g1', 'Name': 'Hard Rock', 'Type': 'MusicGenre'},
      ]),
    ).genres();
    expect(genres.single.albumCount, isNull);
  });

  test('an album comes with the id of its album artist, or its first artist\'s when it has none', () async {
    final untagged = {
      ...album,
      'Id': 'a2',
      'AlbumArtists': <Object>[],
      'Artists': ['Run-DMC'],
      'ArtistItems': [
        {'Name': 'Run-DMC', 'Id': 'ar2'},
      ],
    }..remove('AlbumArtist');
    final albums = await jellyfin((_) => items([album, untagged])).albums(order: AlbumOrder.name);
    expect(albums.map((album) => (album.artist, album.artistId)), [('Aerosmith', 'ar1'), ('Run-DMC', 'ar2')]);
  });

  test('most played albums: Jellyfin counts plays by song, so they add up by album', () async {
    Map<String, Object?> played(String id, String? albumId, int plays) => {
      ...song,
      'Id': id,
      'AlbumId': albumId,
      'UserData': {'PlayCount': plays, 'Played': true},
    };

    final asked = <http.Request>[];
    final albums = await jellyfin((request) {
      final query = request.url.queryParameters;

      if (query['IncludeItemTypes'] == 'Audio') {
        return items([
          played('s0', null, 20), // a song in no album
          played('s1', 'a1', 9),
          played('s2', 'a2', 6),
          played('s3', 'a2', 5),
          played('s4', 'a3', 1),
        ]);
      }

      // Asked by id, in whatever order the server likes.
      final ids = query['Ids']?.split(',') ?? const [];
      return items([
        for (final id in ids.reversed) {...album, 'Id': id, 'Name': 'Album $id'},
      ]);
    }, asked).mostPlayedAlbums(size: 2);
    expect([for (final album in albums) album.name], ['Album a2', 'Album a1']);
    final songs = asked.first.url.queryParameters;
    expect(songs, containsPair('Recursive', 'true'));
    expect(songs, containsPair('Filters', 'IsPlayed'));
    expect(songs, containsPair('SortBy', 'PlayCount'));
    expect(songs, containsPair('SortOrder', 'Descending'));
    expect(songs, contains('Limit'));
    expect(asked.last.url.queryParameters, containsPair('Ids', 'a2,a1'));
  });

  test('lyrics are Audio/{id}/Lyrics, their starts in ticks; a song without them has none', () async {
    final asked = <http.Request>[];
    final api = jellyfin(
      (request) =>
          switch (request.url.pathSegments.last == 'Lyrics' ? request.url.pathSegments.reversed.elementAt(1) : '') {
            's1' => json({
              'Metadata': {'IsSynced': true},
              'Lyrics': [
                {'Text': 'First', 'Start': 10000000},
                {'Text': 'Second', 'Start': 25000000},
              ],
            }),
            's2' => json({
              'Metadata': {'IsSynced': false},
              'Lyrics': [
                {'Text': 'One'},
                {'Text': 'Two'},
              ],
            }),
            _ => json({}, 404),
          },
      asked,
    );
    final synced = (await api.lyrics('s1'))!;
    expect(asked.single.url.path, '/jellyfin/Audio/s1/Lyrics');
    expect(synced.synced, isTrue);
    expect(synced.provider, 'Jellyfin');
    expect(
      [for (final line in synced.lines) (line.start, line.text)],
      [(const Duration(seconds: 1), 'First'), (const Duration(milliseconds: 2500), 'Second')],
    );
    final plain = (await api.lyrics('s2'))!;
    expect(plain.synced, isFalse);
    expect([for (final line in plain.lines) (line.start, line.text)], [(null, 'One'), (null, 'Two')]);
    expect(await api.lyrics('s3'), isNull, reason: 'Jellyfin answers 404');
  });

  test('albums by most played are the most played albums, a page at a time', () async {
    Map<String, Object?> played(String id, String albumId, int plays) => {
      ...song,
      'Id': id,
      'AlbumId': albumId,
      'UserData': {'PlayCount': plays, 'Played': true},
    };

    final asked = <http.Request>[];
    final api = jellyfin((request) {
      final query = request.url.queryParameters;

      if (query['IncludeItemTypes'] == 'Audio') {
        return items([played('s1', 'a1', 9), played('s2', 'a2', 6), played('s3', 'a3', 1)]);
      }

      return items([
        for (final id in query['Ids']?.split(',') ?? const <String>[]) {...album, 'Id': id, 'Name': 'Album $id'},
      ]);
    }, asked);
    final page = await api.albums(order: AlbumOrder.mostPlayed, size: 1, offset: 1);
    expect([for (final album in page) album.name], ['Album a2']);
    expect(asked.last.url.queryParameters, containsPair('Ids', 'a2'));

    asked.clear();
    expect(await api.albums(order: AlbumOrder.mostPlayed, size: 2, offset: 3), isEmpty, reason: 'past the last');
    expect(asked, hasLength(1), reason: 'the songs alone: no albums to ask for');
  });

  test('a genre\'s most played albums add up the plays of its songs', () async {
    final asked = <http.Request>[];
    await jellyfin((_) => items([]), asked).mostPlayedAlbums(genre: 'g1');
    final songs = asked.single.url.queryParameters;
    expect(songs, containsPair('IncludeItemTypes', 'Audio'));
    expect(songs, containsPair('GenreIds', 'g1'));
    expect(songs, containsPair('SortBy', 'PlayCount'));
  });

  test('the most played genres add up the plays of the most played songs, by each of their genres', () async {
    Map<String, Object?> played(String id, int plays, List<(String, String)> genres) => {
      ...song,
      'Id': id,
      'GenreItems': [
        for (final (id, name) in genres) {'Id': id, 'Name': name},
      ],
      'UserData': {'PlayCount': plays, 'Played': true},
    };

    final asked = <http.Request>[];
    final genres = await jellyfin(
      (_) => items([
        played('s1', 12, [('g3', 'Jazz')]),
        played('s2', 9, [('g1', 'Rock')]),
        played('s3', 5, [('g2', 'Blues'), ('g1', 'Rock')]),
        played('s4', 1, []),
      ]),
      asked,
    ).mostPlayedGenres(size: 2);
    expect([for (final genre in genres) (genre.id, genre.name)], [('g1', 'Rock'), ('g3', 'Jazz')]);
    final songs = asked.single.url.queryParameters;
    expect(songs, containsPair('IncludeItemTypes', 'Audio'));
    expect(songs, containsPair('Filters', 'IsPlayed'));
    expect(songs, containsPair('SortBy', 'PlayCount'));
    expect(songs['Fields'], contains('Genres'));
  });

  test('an artist\'s most played songs are the most played songs they are an artist or the album artist of', () async {
    final asked = <http.Request>[];
    final songs = await jellyfin(
      (_) => items([
        {
          ...song,
          'UserData': {'PlayCount': 5, 'Played': true},
        },
      ]),
      asked,
    ).mostPlayedSongs('ar1');
    expect(songs.single.title, 'Walk This Way');
    expect(songs.single.album, 'Toys in the Attic');
    final query = asked.single.url.queryParameters;
    expect(query, containsPair('IncludeItemTypes', 'Audio'));
    expect(query, containsPair('ArtistIds', 'ar1'));
    expect(query, containsPair('Filters', 'IsPlayed'));
    expect(query, containsPair('SortBy', 'PlayCount'));
    expect(query, containsPair('SortOrder', 'Descending'));
    expect(query, containsPair('Limit', '10'));
  });

  test('an artist has no popular songs: Jellyfin knows no one\'s plays but its users\'', () async {
    final asked = <http.Request>[];
    expect(await jellyfin((_) => items([]), asked).popularSongs(const Artist(id: 'ar1', name: 'Aerosmith')), isEmpty);
    expect(asked, isEmpty);
  });

  test('a scrobble asks nothing of the server: the hub\'s Sessions/Playing counts the play', () async {
    final asked = <http.Request>[];
    await jellyfin((_) => items([]), asked).scrobble('s1', time: DateTime(2026, 10, 6));
    expect(asked, isEmpty);
  });

  test('with nothing played yet there are no most played albums, and no albums to ask for', () async {
    final asked = <http.Request>[];
    expect(await jellyfin((_) => items([]), asked).mostPlayedAlbums(), isEmpty);
    expect(asked, hasLength(1));
  });

  test('an album and its songs, in order; a song without an image of its own shows its album\'s', () async {
    final asked = <http.Request>[];
    final (found, songs) = await jellyfin((request) {
      final query = request.url.queryParameters;

      if (query['Ids'] == 'a1') {
        return items([
          {
            ...album,
            if (query['Fields']?.split(',').contains('Studios') ?? false)
              'Studios': [
                {'Name': 'Columbia', 'Id': 'st1'},
              ],
            if (query['Fields']?.split(',').contains('ProviderIds') ?? false)
              'ProviderIds': {'MusicBrainzAlbum': 'r1', 'MusicBrainzReleaseGroup': 'rg1'},
          },
        ]);
      }

      if (query['ParentId'] == 'a1') {
        return items([song]);
      }

      return http.Response('', 404);
    }, asked).album('a1');
    expect(found.name, 'Toys in the Attic');
    expect(found.recordLabels, ['Columbia'], reason: 'its studios, which come only when asked for');
    expect(found.musicBrainzId, 'r1', reason: 'its release\'s, among its other ids, which come only when asked for');
    final tracks = asked.firstWhere((request) => request.url.queryParameters['ParentId'] == 'a1').url.queryParameters;
    expect(tracks, containsPair('IncludeItemTypes', 'Audio'));
    expect(tracks['SortBy'], startsWith('ParentIndexNumber,IndexNumber'));
    final first = songs.single;
    expect(
      (first.id, first.title, first.artist, first.album),
      ('s1', 'Walk This Way', 'Aerosmith', 'Toys in the Attic'),
    );
    expect(first.duration, const Duration(seconds: 221));
    expect(first.coverArt, 'a1');
  });

  test(
    'an album\'s release date is its PremiereDate; on the first of January, which a year alone gets, its year',
    () async {
      Future<(int?, int?, int?)> released(String premiere) async {
        final (found, _) = await jellyfin(
          (request) => items([
            if (request.url.queryParameters['Ids'] == 'a1') {...album, 'PremiereDate': premiere},
          ]),
        ).album('a1');
        final date = found.releaseDate;
        return (date?.year, date?.month, date?.day);
      }

      expect(await released('1976-05-14T00:00:00.0000000Z'), (1976, 5, 14));
      expect(await released('1976-01-01T00:00:00.0000000Z'), (1976, null, null));
    },
  );

  test('a song comes with the ids of its album and its first artist, or its album artist\'s', () async {
    final duet = {
      ...song,
      'Artists': ['Run-DMC', 'Aerosmith'],
      'ArtistItems': [
        {'Name': 'Run-DMC', 'Id': 'ar2'},
        {'Name': 'Aerosmith', 'Id': 'ar1'},
      ],
    };
    final untagged = {...song, 'Artists': <String>[], 'ArtistItems': <Object>[]};
    final api = jellyfin(
      (request) => switch (request.url.queryParameters['Ids']) {
        's1' => items([duet]),
        's2' => items([untagged]),
        _ => items([]),
      },
    );
    final found = await api.song('s1');
    expect((found.title, found.artist), ('Walk This Way', 'Run-DMC, Aerosmith'));
    expect((found.albumId, found.artistId), ('a1', 'ar2'));
    expect((await api.song('s2')).artistId, 'ar1', reason: 'its artist shows as the album artist');
    await expectLater(api.song('s3'), throwsA(isA<ServerError>()));
  });

  test('search: artists, albums and songs that match', () async {
    final asked = <http.Request>[];
    final (:artists, :albums, :songs) = await jellyfin((request) {
      // Artists from their own endpoint: Jellyfin's Items doesn't list them.
      if (request.url.path == '/jellyfin/Artists/AlbumArtists') {
        return items([artist]);
      }

      return switch (request.url.queryParameters['IncludeItemTypes']) {
        'MusicAlbum' => items([album]),
        'Audio' => items([song]),
        _ => http.Response('', 404),
      };
    }, asked).search('aero');
    expect(asked.map((request) => request.url.queryParameters['searchTerm']), everyElement('aero'));
    expect(asked.map((request) => request.url.queryParameters['Limit']), unorderedEquals(['5', '10', '50']));
    expect(artists.single.name, 'Aerosmith');
    expect(artists.single.coverArt, 'ar1');
    expect(albums.single.name, 'Toys in the Attic');
    expect(songs.single.title, 'Walk This Way');
  });

  test('artists: the album artists, by name', () async {
    final asked = <http.Request>[];
    final artists = await jellyfin((_) => items([artist]), asked).artists();
    expect(asked.single.url.path, '/jellyfin/Artists/AlbumArtists');
    expect(asked.single.url.queryParameters, containsPair('SortBy', 'SortName'));
    expect(artists.single.id, 'ar1');
  });

  test('the most played artists add up the plays of the most played songs, by each of their album artists, and come as '
      'the album artists do', () async {
    Map<String, Object?> played(String id, int plays, List<String> artists) => {
      ...song,
      'Id': id,
      'AlbumArtists': [
        for (final id in artists) {'Name': 'Artist $id', 'Id': id},
      ],
      'UserData': {'PlayCount': plays, 'Played': true},
    };

    final asked = <http.Request>[];
    final artists = await jellyfin((request) {
      if (request.url.path == '/jellyfin/Artists/AlbumArtists') {
        return items([
          {...artist, 'Id': 'ar1', 'Name': 'Aerosmith'},
          {...artist, 'Id': 'ar2', 'Name': 'Cheap Trick'},
          {...artist, 'Id': 'ar3', 'Name': 'Miles Davis'},
        ]);
      }

      return items([
        played('s1', 12, ['ar2']),
        played('s2', 9, ['ar1']),
        played('s3', 5, ['ar1', 'ar3']),
        // Of an album artist the album artists don't list.
        played('s4', 7, ['ar9']),
        played('s5', 1, []),
      ]);
    }, asked).mostPlayedArtists(size: 3);
    expect(
      [for (final artist in artists) (artist.id, artist.name)],
      [('ar1', 'Aerosmith'), ('ar2', 'Cheap Trick'), ('ar3', 'Miles Davis')],
    );
    expect(artists.first.coverArt, 'ar1');
    final songs = asked.first.url.queryParameters;
    expect(songs, containsPair('IncludeItemTypes', 'Audio'));
    expect(songs, containsPair('Filters', 'IsPlayed'));
    expect(songs, containsPair('SortBy', 'PlayCount'));
    expect(asked.last.url.path, '/jellyfin/Artists/AlbumArtists');
  });

  test('with nothing played yet there are no most played artists, and no artists to ask for', () async {
    final asked = <http.Request>[];
    expect(await jellyfin((_) => items([]), asked).mostPlayedArtists(), isEmpty);
    expect(asked, hasLength(1));
  });

  test('an artist and their albums', () async {
    final (found, albums) = await jellyfin((request) {
      final query = request.url.queryParameters;

      if (query['Ids'] == 'ar1') {
        return items([artist]);
      }

      if (query['AlbumArtistIds'] == 'ar1' && query['IncludeItemTypes'] == 'MusicAlbum') {
        return items([album]);
      }

      return http.Response('', 404);
    }).artist('ar1');
    expect(found.name, 'Aerosmith');
    expect(found.albumCount, 1);
    expect(albums.single.id, 'a1');
  });

  test('audio and covers come from URLs a player can open, the token in the stream\'s', () {
    final api = jellyfin((_) => http.Response('', 404));
    final stream = api.streamUrl('s1');
    expect(stream.path, '/jellyfin/Audio/s1/stream');
    expect(stream.queryParameters, containsPair('static', 'true'));
    expect(stream.queryParameters, containsPair('ApiKey', 'tok'));
    final cover = api.coverArtUrl('a1', size: 96);
    expect(cover.path, '/jellyfin/Items/a1/Images/Primary');
    expect(cover.queryParameters, containsPair('maxWidth', '96'));
  });

  test('within a bitrate, a song comes through universal: as it is where it fits, otherwise as HLS', () async {
    final api = jellyfin((_) => http.Response('', 404));
    final stream = api.streamUrl('s1', maxBitRate: 160);
    expect(stream.path, '/jellyfin/Audio/s1/universal');
    expect(stream.queryParameters, containsPair('MaxStreamingBitrate', '160000'));
    expect(stream.queryParameters, containsPair('TranscodingProtocol', 'hls'));
    expect(stream.queryParameters, containsPair('UserId', 'u1'));
    expect(stream.queryParameters, containsPair('DeviceId', 'd1'));
    expect(stream.queryParameters, containsPair('ApiKey', 'tok'));
    expect(
      await api.transcodedStreamUrl('s1', maxBitRate: 160, from: const Duration(seconds: 42)),
      isNull,
      reason: 'HLS can seek',
    );
  });

  test('a sign-in the server forgot is an auth error, also from pages that ask for two things at once', () async {
    final forgot = jellyfin((_) => http.Response('', 401));

    for (final request in [
      () => forgot.albums(order: AlbumOrder.name),
      () => forgot.album('a1'),
      () => forgot.search('aero'),
    ]) {
      await expectLater(request(), throwsA(isA<ServerError>().having((e) => e.isAuth, 'isAuth', isTrue)));
    }
  });

  test('signing out ends the sign-in on the server, and never fails', () async {
    final asked = <http.Request>[];
    await jellyfin((_) => http.Response('', 204), asked).signOut();
    expect((asked.single.method, asked.single.url.path), ('POST', '/jellyfin/Sessions/Logout'));
    expect(asked.single.headers['Authorization'], contains('Token="tok"'));
    await jellyfin((_) => throw http.ClientException('offline')).signOut();
  });
}
