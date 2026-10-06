import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/server/server.dart';
import 'package:segue/subsonic/api.dart';

http.Response subsonic(Map<String, Object?> body) =>
    http.Response(jsonEncode({'subsonic-response': body}), 200, headers: {'content-type': 'application/json'});

void main() {
  const credentials = SubsonicCredentials(username: 'alice', token: '26719a1196d2a940705a59634eb18eab', salt: 'c19b2d');

  test('the token is md5(password + salt), as in the Subsonic docs', () {
    final fresh = SubsonicCredentials.fromPassword('alice', 'sesame');
    expect(fresh.token, md5.convert(utf8.encode('sesame${fresh.salt}')).toString());
    expect(md5.convert(utf8.encode('sesamec19b2d')).toString(), credentials.token);
  });

  test('requests carry the token, never the password, under the app name', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test:4533'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({'status': 'ok'});
      }),
    );
    await api.ping();
    expect(asked.path, '/rest/ping.view');
    expect(asked.queryParameters, containsPair('t', credentials.token));
    expect(asked.queryParameters, containsPair('s', credentials.salt));
    expect(asked.queryParameters, containsPair('c', 'Segue'));
    expect(asked.queryParameters.containsKey('p'), isFalse);
  });

  test('a server under a path keeps it', () {
    final api = SubsonicApi(Uri.parse('https://example.test/music'), credentials);
    expect(api.streamUrl('s1').path, '/music/rest/stream.view');
  });

  test('wrong credentials are an auth error', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient(
        (_) async => subsonic({
          'status': 'failed',
          'error': {'code': 40, 'message': 'Wrong username or password'},
        }),
      ),
    );
    await expectLater(api.ping(), throwsA(isA<ServerError>().having((e) => e.isAuth, 'isAuth', isTrue)));
  });

  test('albums and an album with its songs', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        if (request.url.path.endsWith('getAlbumList2.view')) {
          return subsonic({
            'status': 'ok',
            'albumList2': {
              'album': [
                {
                  'id': 'a1',
                  'name': 'Aerosmith',
                  'artist': 'Aerosmith',
                  'artistId': 'ar1',
                  'coverArt': 'al-a1',
                  'year': 1973,
                },
              ],
            },
          });
        }

        return subsonic({
          'status': 'ok',
          'album': {
            'id': 'a1',
            'name': 'Aerosmith',
            'song': [
              {'id': 's1', 'title': 'Dream On', 'artist': 'Aerosmith', 'duration': 268},
            ],
          },
        });
      }),
    );
    final albums = await api.albums(order: AlbumOrder.latest);
    expect(albums.single.name, 'Aerosmith');
    expect(albums.single.year, 1973);
    expect(albums.single.artistId, 'ar1');
    final (_, songs) = await api.album('a1');
    expect(songs.single.title, 'Dream On');
    expect(songs.single.duration, const Duration(seconds: 268));
    expect(songs.single.toQueueItem().durationMs, 268000);
  });

  test('a song comes with the ids of its album and its artist (getSong)', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({
          'status': 'ok',
          'song': {
            'id': 's1',
            'title': 'Dream On',
            'artist': 'Aerosmith',
            'album': 'Aerosmith',
            'albumId': 'a1',
            'artistId': 'ar1',
          },
        });
      }),
    );
    final song = await api.song('s1');
    expect(asked.path, '/rest/getSong.view');
    expect(asked.queryParameters, containsPair('id', 's1'));
    expect((song.title, song.albumId, song.artistId), ('Dream On', 'a1', 'ar1'));
  });

  test('albums by name are getAlbumList2\'s alphabeticalByName, and the latest added its newest', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);
        return subsonic({'status': 'ok', 'albumList2': <String, Object?>{}});
      }),
    );
    await api.albums(order: AlbumOrder.name, size: 200, offset: 400);
    await api.albums(order: AlbumOrder.latest, size: 20);
    expect(asked.first.queryParameters, containsPair('type', 'alphabeticalByName'));
    expect(asked.first.queryParameters, containsPair('size', '200'));
    expect(asked.first.queryParameters, containsPair('offset', '400'));
    expect(asked.last.queryParameters, containsPair('type', 'newest'));
  });

  test('lyrics are OpenSubsonic\'s getLyricsBySongId: the synced ones first, shifted by their offset', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({
          'status': 'ok',
          'type': 'navidrome', // OpenSubsonic's name of the server
          'lyricsList': {
            'structuredLyrics': [
              {
                'lang': 'eng',
                'synced': false,
                'line': [
                  {'value': 'Plain'},
                ],
              },
              {
                'lang': 'eng',
                'synced': true,
                'offset': 100, // they show 100 ms sooner
                'line': [
                  {'start': 1000, 'value': 'First'},
                  {'start': 2500, 'value': 'Second'},
                ],
              },
            ],
          },
        });
      }),
    );
    final lyrics = (await api.lyrics('s1'))!;
    expect(asked.path, '/rest/getLyricsBySongId.view');
    expect(asked.queryParameters, containsPair('id', 's1'));
    expect(lyrics.synced, isTrue);
    expect(
      [for (final line in lyrics.lines) (line.start, line.text)],
      [(const Duration(milliseconds: 900), 'First'), (const Duration(milliseconds: 2400), 'Second')],
    );
    expect(lyrics.provider, 'Navidrome', reason: 'the server, by its name');
  });

  test('a song without lyrics has none, and lyrics that aren\'t synced come as they are', () async {
    var body = <String, Object?>{'lyricsList': <String, Object?>{}};
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => subsonic({'status': 'ok', ...body})),
    );
    expect(await api.lyrics('s1'), isNull);

    body = {
      'lyricsList': {
        'structuredLyrics': [
          {
            'synced': false,
            'line': [
              {'value': 'One'},
              {'value': 'Two'},
            ],
          },
        ],
      },
    };
    final plain = (await api.lyrics('s1'))!;
    expect(plain.synced, isFalse);
    expect([for (final line in plain.lines) (line.start, line.text)], [(null, 'One'), (null, 'Two')]);
    expect(plain.provider, isNull, reason: 'a server that doesn\'t say its name');
  });

  test('albums by most played are getAlbumList2\'s frequent, a page at a time', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({'status': 'ok', 'albumList2': <String, Object?>{}});
      }),
    );
    await api.albums(order: AlbumOrder.mostPlayed, size: 200, offset: 200);
    expect(asked.path, '/rest/getAlbumList2.view');
    expect(asked.queryParameters, containsPair('type', 'frequent'));
    expect(asked.queryParameters, containsPair('size', '200'));
    expect(asked.queryParameters, containsPair('offset', '200'));
  });

  test('albums by release date are getAlbumList2\'s byYear, from the farthest year back to the first', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({'status': 'ok', 'albumList2': <String, Object?>{}});
      }),
    );
    await api.albums(order: AlbumOrder.released, size: 20, offset: 40);
    expect(asked.path, '/rest/getAlbumList2.view');
    expect(asked.queryParameters, containsPair('type', 'byYear'));
    expect(asked.queryParameters, containsPair('fromYear', '9999'));
    expect(asked.queryParameters, containsPair('toYear', '0'));
    expect(asked.queryParameters, containsPair('size', '20'));
    expect(asked.queryParameters, containsPair('offset', '40'));
  });

  test('genres are getGenres\', named by their value, and a genre\'s albums getAlbumList2\'s byGenre', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        if (request.url.path.endsWith('getGenres.view')) {
          return subsonic({
            'status': 'ok',
            'genres': {
              'genre': [
                {'value': 'Hard Rock', 'songCount': 30, 'albumCount': 3},
              ],
            },
          });
        }

        return subsonic({
          'status': 'ok',
          'albumList2': {
            'album': [
              {'id': 'a1', 'name': 'Toys in the Attic', 'artist': 'Aerosmith'},
            ],
          },
        });
      }),
    );
    final genre = (await api.genres()).single;
    expect((genre.id, genre.name, genre.albumCount), ('Hard Rock', 'Hard Rock', 3));

    final albums = await api.genreAlbums(genre.id, size: 20, offset: 40);
    expect(albums.single.name, 'Toys in the Attic');
    expect(asked.last.path, '/rest/getAlbumList2.view');
    expect(asked.last.queryParameters, containsPair('type', 'byGenre'));
    expect(asked.last.queryParameters, containsPair('genre', 'Hard Rock'));
    expect(asked.last.queryParameters, containsPair('size', '20'));
    expect(asked.last.queryParameters, containsPair('offset', '40'));
  });

  test('the most played albums are getAlbumList2\'s frequent', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({
          'status': 'ok',
          'albumList2': {
            'album': [
              {'id': 'a2', 'name': 'Pump', 'artist': 'Aerosmith', 'year': 1989},
            ],
          },
        });
      }),
    );
    final albums = await api.mostPlayedAlbums(size: 12);
    expect(asked.path, '/rest/getAlbumList2.view');
    expect(asked.queryParameters, containsPair('type', 'frequent'));
    expect(asked.queryParameters, containsPair('size', '12'));
    expect(albums.single.name, 'Pump');
  });

  test(
    'a genre\'s most played albums are those of the genre among the 500 most played: frequent takes no genre',
    () async {
      late Uri asked;
      final api = SubsonicApi(
        Uri.parse('https://music.test'),
        credentials,
        client: MockClient((request) async {
          asked = request.url;
          return subsonic({
            'status': 'ok',
            'albumList2': {
              'album': [
                {
                  'id': 'a1',
                  'name': 'Pump',
                  'genre': 'Rock',
                  'genres': [
                    {'name': 'Rock'},
                  ],
                },
                {'id': 'a2', 'name': 'Honky Tonk Blues', 'genre': 'Blues'},
                // Its first genre, and its others in OpenSubsonic's genres.
                {
                  'id': 'a3',
                  'name': 'Toys in the Attic',
                  'genre': 'Blues',
                  'genres': [
                    {'name': 'Blues'},
                    {'name': 'Rock'},
                  ],
                },
                // From a server without OpenSubsonic's genres.
                {'id': 'a4', 'name': 'Rocks', 'genre': 'Rock'},
                {'id': 'a5', 'name': 'Get a Grip', 'genre': 'Rock'},
              ],
            },
          });
        }),
      );
      final albums = await api.mostPlayedAlbums(size: 3, genre: 'Rock');
      expect(asked.queryParameters, containsPair('type', 'frequent'));
      expect(asked.queryParameters, containsPair('size', '500'));
      expect([for (final album in albums) album.name], ['Pump', 'Toys in the Attic', 'Rocks']);
    },
  );

  test('the most played genres add up the plays of the 500 most played albums, by each of their genres', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({
          'status': 'ok',
          'albumList2': {
            'album': [
              {
                'id': 'a1',
                'name': 'Pump',
                'playCount': 10,
                'genres': [
                  {'name': 'Rock'},
                ],
              },
              {'id': 'a2', 'name': 'Kind of Blue', 'playCount': 8, 'genre': 'Jazz'},
              {
                'id': 'a3',
                'name': 'Toys in the Attic',
                'playCount': 6,
                'genre': 'Blues',
                'genres': [
                  {'name': 'Blues'},
                  {'name': 'Rock'},
                ],
              },
              // A server that doesn't say counts each album once.
              {'id': 'a4', 'name': 'Thriller', 'genre': 'Pop'},
            ],
          },
        });
      }),
    );
    final genres = await api.mostPlayedGenres(size: 3);
    expect(asked.queryParameters, containsPair('type', 'frequent'));
    expect(asked.queryParameters, containsPair('size', '500'));
    expect(
      [for (final genre in genres) (genre.id, genre.name)],
      [('Rock', 'Rock'), ('Jazz', 'Jazz'), ('Blues', 'Blues')],
    );
    expect(await api.mostPlayedGenres(), hasLength(4));
  });

  test('search asks for artists, albums and songs', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({
          'status': 'ok',
          'searchResult3': {
            'artist': [
              {'id': 'ar1', 'name': 'Aerosmith', 'coverArt': 'ar-ar1', 'albumCount': 2},
            ],
            'album': [
              {'id': 'a1', 'name': 'Aerosmith', 'artist': 'Aerosmith'},
            ],
            'song': [
              {'id': 's1', 'title': 'Dream On', 'artist': 'Aerosmith', 'album': 'Aerosmith', 'coverArt': 'mf-s1'},
            ],
          },
        });
      }),
    );
    final (:artists, :albums, :songs) = await api.search('dream on');
    expect(asked.path, '/rest/search3.view');
    expect(asked.queryParameters, containsPair('query', 'dream on'));
    expect(int.parse(asked.queryParameters['artistCount']!), greaterThan(0));
    expect(artists.single.name, 'Aerosmith');
    expect(artists.single.albumCount, 2);
    expect(albums.single.id, 'a1');
    expect(songs.single.coverArt, 'mf-s1');
  });

  test('artists come in name order, from every letter of the index', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({
          'status': 'ok',
          'artists': {
            'ignoredArticles': 'The',
            'index': [
              {
                'name': 'A',
                'artist': [
                  {'id': 'ar1', 'name': 'Aerosmith', 'coverArt': 'ar-ar1', 'albumCount': 5},
                ],
              },
              {
                'name': 'C',
                'artist': [
                  {'id': 'ar2', 'name': 'Cheap Trick', 'albumCount': 1},
                ],
              },
            ],
          },
        });
      }),
    );
    final artists = await api.artists();
    expect(asked.path, '/rest/getArtists.view');
    expect(artists.map((artist) => artist.name), ['Aerosmith', 'Cheap Trick']);
    expect(artists.first.coverArt, 'ar-ar1');
    expect(artists.first.albumCount, 5);
  });

  test('an artist comes with their albums', () async {
    late Uri asked;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;
        return subsonic({
          'status': 'ok',
          'artist': {
            'id': 'ar1',
            'name': 'Aerosmith',
            'albumCount': 2,
            'album': [
              {'id': 'a1', 'name': 'Aerosmith', 'artist': 'Aerosmith', 'year': 1973},
              {'id': 'a2', 'name': 'Toys in the Attic', 'artist': 'Aerosmith', 'year': 1975},
            ],
          },
        });
      }),
    );
    final (artist, albums) = await api.artist('ar1');
    expect(asked.path, '/rest/getArtist.view');
    expect(asked.queryParameters, containsPair('id', 'ar1'));
    expect(artist.name, 'Aerosmith');
    expect(albums.map((album) => album.name), ['Aerosmith', 'Toys in the Attic']);
  });

  test('a search that finds nothing', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => subsonic({'status': 'ok', 'searchResult3': <String, Object?>{}})),
    );
    final (artists: _, :albums, :songs) = await api.search('zzz');
    expect(albums, isEmpty);
    expect(songs, isEmpty);
  });
}
