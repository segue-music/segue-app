import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:segue/server/models.dart';
import 'package:segue/server/server.dart';
import 'package:segue/subsonic/api.dart';

http.Response subsonic(Map<String, Object?> body) =>
    http.Response(jsonEncode({'subsonic-response': body}), 200, headers: {'content-type': 'application/json'});

void main() {
  const credentials = SubsonicToken(username: 'alice', token: '26719a1196d2a940705a59634eb18eab', salt: 'c19b2d');

  test('the token is md5(password + salt), as in the Subsonic docs', () {
    final fresh = SubsonicCredentials.fromPassword('alice', 'sesame') as SubsonicToken;

    expect(fresh.token, md5.convert(utf8.encode('sesame${fresh.salt}')).toString());
    expect(md5.convert(utf8.encode('sesamec19b2d')).toString(), credentials.token);
  });

  test('the first answer says in the log which server it is, and only a server that changes says it again', () async {
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    var answer = {
      'status': 'ok',
      'version': '1.16.1',
      'type': 'navidrome',
      'serverVersion': '0.58.0 (13af8ed4)',
      'openSubsonic': true,
    };
    final api = SubsonicApi(
      Uri.parse('https://music.test:4533'),
      credentials,
      client: MockClient((_) async => subsonic(answer)),
    );

    addTearDown(subscription.cancel);
    await api.ping();
    await api.ping();
    answer = {'status': 'ok', 'version': '1.16.1'};
    await api.ping();
    expect(
      [for (final record in records) '${record.loggerName}: ${record.message}'],
      [
        'SubsonicApi: music.test: navidrome 0.58.0 (13af8ed4), API 1.16.1, OpenSubsonic',
        'SubsonicApi: music.test: a Subsonic server, API 1.16.1',
      ],
    );
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

  test('a Navidrome from 0.64 is asked for an item by the id it has now, given the one it had before; one from before '
      '0.64 by the id as it is', () async {
    var version = '0.63.2 (1a2b3c4)';
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return subsonic({'status': 'ok', 'type': 'navidrome', 'serverVersion': version, 'openSubsonic': true});
      }),
    );
    // A song's and an album's id in a library older than Navidrome 0.55, and a playlist's UUID.
    const song = '000000000000000000000000000000ff', album = 'e3b7fc2ae9447bbec37a13bf916e3cf6';
    const playlist = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
    await api.ping();
    await api.setFavorite(FavoriteKind.album, album, favorite: true);
    expect(asked.last.queryParameters, containsPair('albumId', album));
    expect(api.streamUrl(song).queryParameters, containsPair('id', song));
    expect(api.currentId(song), song);

    version = '0.64.2 (1a2b3c4)';
    await api.ping();
    expect(api.currentId(song), '0000000000000000000047');
    expect(api.currentId('al-${album}_0', cover: true), 'al-6VHl3uR4kss6sUPKA8Cwnk_0');
    await api.setFavorite(FavoriteKind.album, album, favorite: true);
    expect(asked.last.queryParameters, containsPair('albumId', '6VHl3uR4kss6sUPKA8Cwnk'));
    expect(api.streamUrl(song).queryParameters, containsPair('id', '0000000000000000000047'));
    expect(api.coverArtUrl('al-${album}_0').queryParameters, containsPair('id', 'al-6VHl3uR4kss6sUPKA8Cwnk_0'));
    await api.scrobbleMissed(song, time: DateTime(2026, 9));
    expect(asked.last.queryParameters, containsPair('id', '0000000000000000000047'), reason: 'a play held from before');
    await api.addToPlaylist(playlist, [song, '0000000000000000000048']);
    expect(asked.last.queryParameters, containsPair('playlistId', '7rke2SAWaicSeSYzkhww6R'));
    expect(asked.last.queryParametersAll['songIdToAdd'], [
      '0000000000000000000047',
      '0000000000000000000048',
    ], reason: 'one it has now, as it is');
  });

  test(
    'with an API key, requests carry it alone, without the user\'s name or a token; the hub\'s hello, the key',
    () async {
      late Uri asked;

      final api = SubsonicApi(
        Uri.parse('https://music.test'),
        const SubsonicApiKey(username: 'alice', apiKey: 'k3y'),
        client: MockClient((request) async {
          asked = request.url;

          return subsonic({
            'status': 'ok',
            'tokenInfo': {'username': 'alice'},
          });
        }),
      );

      await api.ping();
      expect(asked.queryParameters, containsPair('apiKey', 'k3y'));
      expect(asked.queryParameters.keys, isNot(anyOf(contains('u'), contains('t'), contains('s'), contains('p'))));
      expect(api.streamUrl('s1').queryParameters, containsPair('apiKey', 'k3y'));
      expect(api.auth.toJson(), {'scheme': 'apiKey', 'apiKey': 'k3y'});
      expect(await api.keyUsername(), 'alice');
      expect(asked.path, '/rest/tokenInfo.view');
    },
  );

  test(
    'a server that takes no password, but API keys, refuses it so (41, 42), as it refuses a key it doesn\'t know (44) '
    'and a wrong password (40)',
    () async {
      for (final (code, wantsApiKey) in [(41, true), (42, true), (44, false), (40, false)]) {
        final api = SubsonicApi(
          Uri.parse('https://music.test'),
          credentials,
          client: MockClient(
            (_) async => subsonic({
              'status': 'failed',
              'error': {'code': code, 'message': 'refused'},
            }),
          ),
        );

        await expectLater(
          api.ping(),
          throwsA(isA<ServerError>().having((e) => (e.isAuth, e.wantsApiKey), 'refusal', (true, wantsApiKey))),
          reason: '$code',
        );
      }
    },
  );

  test('a server under a path keeps it', () {
    final api = SubsonicApi(Uri.parse('https://example.test/music'), credentials);

    expect(api.streamUrl('s1').path, '/music/rest/stream.view');
  });

  test('a stream within a bitrate, and from a point on where the server has transcodeOffset, asked once', () async {
    var asked = 0;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked++;
        expect(request.url.path, '/rest/getOpenSubsonicExtensions.view');

        return subsonic({
          'status': 'ok',
          'openSubsonicExtensions': [
            {
              'name': 'transcodeOffset',
              'versions': [1],
            },
          ],
        });
      }),
    );

    expect(api.streamUrl('s1', maxBitRate: 160).queryParameters, containsPair('maxBitRate', '160'));
    expect(api.streamUrl('s1').queryParameters.containsKey('maxBitRate'), isFalse, reason: 'the file as it is');

    final later = await api.transcodedStreamUrl(
      's1',
      maxBitRate: 160,
      from: const Duration(seconds: 42, milliseconds: 900),
    );

    expect(later?.path, '/rest/stream.view');
    expect(later?.queryParameters, containsPair('id', 's1'));
    expect(later?.queryParameters, containsPair('maxBitRate', '160'));
    expect(later?.queryParameters, containsPair('timeOffset', '42'));
    await api.transcodedStreamUrl('s1', maxBitRate: 160, from: const Duration(seconds: 50));
    expect(asked, 1);
  });

  test('a server without transcodeOffset starts no stream later; one that couldn\'t be asked, for the network or as it '
      'failed for now, is asked again', () async {
    var online = false;
    var failing = true;
    var asked = 0;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked++;

        if (!online) {
          throw http.ClientException('no network');
        }

        if (failing) {
          failing = false;
          return http.Response('Bad Gateway', 502);
        }

        // A server with no OpenSubsonic extensions.
        return subsonic({
          'status': 'failed',
          'error': {'code': 70, 'message': 'not found'},
        });
      }),
    );
    Future<Uri?> later() => api.transcodedStreamUrl('s1', maxBitRate: 96, from: const Duration(seconds: 42));

    expect(await later(), isNull);
    online = true;
    expect(await later(), isNull);
    expect(await later(), isNull);
    expect(await later(), isNull);
    expect(asked, 3, reason: 'again after no network and after a 502, not after the server answered');
  });

  test('a server that has no such request (HTTP 501) has no extensions, asked once', () async {
    var asked = 0;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked++;
        return http.Response('Not Implemented', 501);
      }),
    );

    for (var i = 0; i < 3; i++) {
      expect(await api.transcodedStreamUrl('s1', maxBitRate: 96, from: const Duration(seconds: 42)), isNull);
    }

    expect(asked, 1);
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
            'recordLabels': [
              {'name': 'Columbia'},
            ],
            'musicBrainzId': 'r1',
            // Subsonic's first, and OpenSubsonic's all.
            'genre': 'Hard Rock',
            'genres': [
              {'name': 'Hard Rock'},
              {'name': 'Blues Rock'},
            ],
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

    final (album, songs) = await api.album('a1');

    expect(album.recordLabels, ['Columbia'], reason: 'OpenSubsonic\'s recordLabels');
    expect(album.musicBrainzId, 'r1');
    expect(albums.single.musicBrainzId, isNull);
    expect(
      [for (final genre in album.genres) (genre.id, genre.name)],
      [('Hard Rock', 'Hard Rock'), ('Blues Rock', 'Blues Rock')],
      reason: 'by name, Subsonic\'s id of a genre',
    );
    expect(albums.single.genres, isEmpty);
    expect(songs.single.title, 'Dream On');
    expect(songs.single.duration, const Duration(seconds: 268));
    expect(songs.single.toQueueItem().durationMs, 268000);
  });

  test(
    'an album\'s release date is OpenSubsonic\'s, its edition\'s or else the original, as precise as it is',
    () async {
      Future<(int?, int?, int?)> released(Map<String, Object?> dates) async {
        final api = SubsonicApi(
          Uri.parse('https://music.test'),
          credentials,
          client: MockClient(
            (_) async => subsonic({
              'status': 'ok',
              'album': {'id': 'a1', 'name': 'Rocks', 'year': 1976, ...dates},
            }),
          ),
        );
        final date = (await api.album('a1')).$1.releaseDate;

        return (date?.year, date?.month, date?.day);
      }

      expect(
        await released({
          'releaseDate': {'year': 1993, 'month': 9, 'day': 7},
          'originalReleaseDate': {'year': 1976, 'month': 5, 'day': 14},
        }),
        (1993, 9, 7),
      );
      expect(
        await released({
          'releaseDate': <String, Object?>{},
          'originalReleaseDate': {'year': 1976, 'month': 5},
        }),
        (1976, 5, null),
      );
      expect(await released({'releaseDate': <String, Object?>{}}), (null, null, null), reason: 'only the year');
    },
  );

  test('an album\'s type is OpenSubsonic\'s releaseTypes, in any case, or a compilation where isCompilation', () async {
    Future<ReleaseType?> type(Map<String, Object?> types) async {
      final api = SubsonicApi(
        Uri.parse('https://music.test'),
        credentials,
        client: MockClient(
          (_) async => subsonic({
            'status': 'ok',
            'album': {'id': 'a1', 'name': 'Rocks', ...types},
          }),
        ),
      );

      return (await api.album('a1')).$1.releaseType;
    }

    expect(
      await type({
        'releaseTypes': ['EP'],
      }),
      ReleaseType.ep,
    );
    expect(
      await type({
        'releaseTypes': ['single'],
      }),
      ReleaseType.single,
      reason: 'as a file\'s tag has it',
    );
    expect(
      await type({
        'releaseTypes': ['album', 'compilation'],
      }),
      ReleaseType.compilation,
      reason: 'over album',
    );
    expect(
      await type({
        'releaseTypes': ['album; live'],
      }),
      ReleaseType.album,
      reason: 'two in one tag',
    );
    expect(
      await type({
        'releaseTypes': ['album'],
        'isCompilation': true,
      }),
      ReleaseType.compilation,
    );
    expect(
      await type({
        'releaseTypes': ['broadcast'],
      }),
      isNull,
    );
    expect(await type({}), isNull, reason: 'a server that doesn\'t say');
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

  test('a song\'s artists are OpenSubsonic\'s, all of them, or else the one of its artistId', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient(
        (request) async => subsonic({
          'status': 'ok',
          'song': switch (request.url.queryParameters['id']) {
            's1' => {
              'id': 's1',
              'title': 'Walk This Way',
              'artist': 'Run-DMC; Aerosmith',
              'artistId': 'ar2',
              'artists': [
                {'id': 'ar2', 'name': 'Run-DMC'},
                {'id': 'ar1', 'name': 'Aerosmith', 'coverArt': 'ar-ar1'},
              ],
            },
            _ => {'id': 's2', 'title': 'Dream On', 'artist': 'Aerosmith', 'artistId': 'ar1'},
          },
        }),
      ),
    );
    final duet = await api.song('s1');

    expect(duet.artists.map((artist) => (artist.id, artist.name, artist.coverArt)), [
      ('ar2', 'Run-DMC', null),
      ('ar1', 'Aerosmith', 'ar-ar1'),
    ]);
    expect(duet.artistId, 'ar2');
    expect((await api.song('s2')).artists.map((artist) => (artist.id, artist.name)), [('ar1', 'Aerosmith')]);
  });

  test(
    'a song\'s credits are OpenSubsonic\'s contributors, a performer with their instrument, and its MusicBrainz id its '
    'recording\'s; roles the credits don\'t show are left out, and a plain Subsonic server\'s song has none',
    () async {
      final api = SubsonicApi(
        Uri.parse('https://music.test'),
        credentials,
        client: MockClient(
          (request) async => subsonic({
            'status': 'ok',
            'song': switch (request.url.queryParameters['id']) {
              's1' => {
                'id': 's1',
                'title': 'Walk This Way',
                'musicBrainzId': 'rec1',
                'contributors': [
                  {
                    'role': 'composer',
                    'artist': {'id': 'ar3', 'name': 'Steven Tyler', 'musicBrainzId': 'mb3'},
                  },
                  {
                    'role': 'performer',
                    'subRole': 'harmonica',
                    'artist': {'id': 'ar3', 'name': 'Steven Tyler', 'musicBrainzId': 'mb3'},
                  },
                  {
                    'role': 'performer',
                    'subRole': '',
                    'artist': {'id': 'ar4', 'name': 'Joe Perry'},
                  },
                  {
                    'role': 'djmixer',
                    'artist': {'id': 'ar5', 'name': 'Jam Master Jay', 'musicBrainzId': ''},
                  },
                  {
                    'role': 'director',
                    'artist': {'id': 'ar6', 'name': 'Marty Callner'},
                  },
                ],
              },
              _ => {'id': 's2', 'title': 'Dream On', 'musicBrainzId': ''},
            },
          }),
        ),
      );
      final song = await api.song('s1');

      expect(song.musicBrainzId, 'rec1');
      expect(
        [
          for (final credit in song.credits)
            (credit.name, credit.role, credit.part, credit.artistId, credit.musicBrainzId),
        ],
        [
          ('Steven Tyler', CreditRole.composer, null, 'ar3', 'mb3'),
          ('Steven Tyler', CreditRole.performer, 'harmonica', 'ar3', 'mb3'),
          ('Joe Perry', CreditRole.performer, null, 'ar4', null),
          ('Jam Master Jay', CreditRole.djMixer, null, 'ar5', null),
        ],
      );

      final plain = await api.song('s2');

      expect(plain.musicBrainzId, isNull);
      expect(plain.credits, isEmpty);
    },
  );

  test(
    'a song\'s ReplayGain is OpenSubsonic\'s replayGain, with only the values it has; one without a gain, or a plain '
    'Subsonic server\'s, has none',
    () async {
      final api = SubsonicApi(
        Uri.parse('https://music.test'),
        credentials,
        client: MockClient(
          (request) async => subsonic({
            'status': 'ok',
            'song': {
              'id': request.url.queryParameters['id'],
              'title': 'Dream On',
              'replayGain': ?switch (request.url.queryParameters['id']) {
                's1' => {'trackGain': -7.5, 'albumGain': -6, 'trackPeak': 0.98, 'albumPeak': 1},
                's2' => {'albumGain': -6.2},
                's3' => {'trackPeak': 1, 'albumPeak': 1},
                _ => null,
              },
            },
          }),
        ),
      );
      final tagged = (await api.song('s1')).replayGain!;

      expect((tagged.trackGain, tagged.albumGain, tagged.trackPeak, tagged.albumPeak), (-7.5, -6, 0.98, 1));

      final albumOnly = (await api.song('s2')).replayGain!;

      expect((albumOnly.trackGain, albumOnly.albumGain, albumOnly.trackPeak), (null, -6.2, null));
      expect((await api.song('s3')).replayGain, isNull, reason: 'peaks, but no gain');
      expect((await api.song('s4')).replayGain, isNull);
    },
  );

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

  test('a song says its number on its disc and which disc it is on; an album, its discs\' titles', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient(
        (request) async => subsonic({
          'status': 'ok',
          'album': {
            'id': 'a1',
            'name': 'Alive!',
            'discTitles': [
              {'disc': 1, 'title': ''},
              {'disc': 2, 'title': 'Encore'},
            ],
            'song': [
              {'id': 's1', 'title': 'Deuce', 'track': 3, 'discNumber': 2},
              {'id': 's2', 'title': 'Untagged'},
            ],
          },
        }),
      ),
    );
    final (album, songs) = await api.album('a1');

    expect(album.discTitles, {2: 'Encore'}, reason: 'none for a disc whose title is empty');
    expect((songs.first.track, songs.first.disc), (3, 2));
    expect((songs.last.track, songs.last.disc), (null, null));
  });

  test('albums played last are getAlbumList2\'s recent', () async {
    late Uri asked;

    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked = request.url;

        return subsonic({'status': 'ok', 'albumList2': <String, Object?>{}});
      }),
    );

    await api.albums(order: AlbumOrder.recentlyPlayed, size: 30);
    expect(asked.queryParameters, allOf(containsPair('type', 'recent'), containsPair('size', '30')));
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

  test('playlists are getPlaylists\', and a playlist\'s songs getPlaylist\'s entries, in its order', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);
        const playlist = {'id': 'p1', 'name': 'Road trip', 'songCount': 2, 'duration': 494, 'coverArt': 'pl-p1'};

        if (request.url.path.endsWith('getPlaylists.view')) {
          return subsonic({
            'status': 'ok',
            'playlists': {
              'playlist': [playlist],
            },
          });
        }

        return subsonic({
          'status': 'ok',
          'playlist': {
            ...playlist,
            'entry': [
              {'id': 's2', 'title': 'Sweet Emotion', 'artist': 'Aerosmith', 'albumId': 'a1', 'duration': 274},
              {'id': 's1', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'albumId': 'a1', 'duration': 220},
            ],
          },
        });
      }),
    );
    final playlist = (await api.playlists()).single;

    expect((playlist.id, playlist.name, playlist.songCount, playlist.coverArt), ('p1', 'Road trip', 2, 'pl-p1'));
    expect(asked.single.path, '/rest/getPlaylists.view');

    final (found, songs) = await api.playlist('p1');

    expect(found.name, 'Road trip');
    expect([for (final song in songs) song.title], ['Sweet Emotion', 'Walk This Way']);
    expect(songs.first.duration, const Duration(seconds: 274));
    expect(asked.last.path, '/rest/getPlaylist.view');
    expect(asked.last.queryParameters, containsPair('id', 'p1'));
  });

  test(
    'a playlist can be changed where OpenSubsonic doesn\'t say it\'s read-only, or else where it\'s the user\'s',
    () async {
      final api = SubsonicApi(
        Uri.parse('https://music.test'),
        credentials,
        client: MockClient(
          (_) async => subsonic({
            'status': 'ok',
            'playlists': {
              'playlist': [
                {'id': 'p1', 'name': 'Mine', 'owner': 'alice', 'readonly': false},
                {'id': 'p2', 'name': 'Smart', 'owner': 'alice', 'readonly': true},
                {'id': 'p3', 'name': 'Bob\'s', 'owner': 'bob'},
                {'id': 'p4', 'name': 'Alice\'s', 'owner': 'alice'},
              ],
            },
          }),
        ),
      );

      expect([for (final playlist in await api.playlists()) playlist.editable], [true, false, false, true]);
    },
  );

  /// An API whose server has [extensions], and answers anything else with ok; [asked] gets every request.
  SubsonicApi changing(List<http.Request> asked, {List<String> extensions = const []}) => SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((request) async {
      asked.add(request);

      return switch (request.url.pathSegments.last) {
        'getOpenSubsonicExtensions.view' => subsonic({
          'status': 'ok',
          'openSubsonicExtensions': [
            for (final name in extensions)
              {
                'name': name,
                'versions': [1],
              },
          ],
        }),
        'getPlaylist.view' => subsonic({
          'status': 'ok',
          'playlist': {
            'id': 'p1',
            'name': 'Road trip',
            'entry': [
              {'id': 's1', 'title': 'Walk This Way'},
              {'id': 's2', 'title': 'Sweet Emotion'},
              {'id': 's3', 'title': 'Dream On'},
            ],
          },
        }),
        _ => subsonic({'status': 'ok'}),
      };
    }),
  );

  /// The parameters of [request], in its URL or, posted, in its body: each name with its values, in order.
  Map<String, List<String>> params(http.Request request) =>
      request.method == 'POST' ? Uri(query: request.body).queryParametersAll : request.url.queryParametersAll;

  test('a playlist is made (createPlaylist), renamed and given songs (updatePlaylist), and deleted', () async {
    final asked = <http.Request>[];
    final api = changing(asked);

    await api.createPlaylist('Road trip', songIds: ['s2', 's1']);
    expect(asked.last.url.path, '/rest/createPlaylist.view');
    expect(params(asked.last)['name'], ['Road trip']);
    expect(params(asked.last)['songId'], ['s2', 's1']);

    await api.renamePlaylist('p1', 'Night drive');
    expect(asked.last.url.path, '/rest/updatePlaylist.view');
    expect(params(asked.last), allOf(containsPair('playlistId', ['p1']), containsPair('name', ['Night drive'])));

    await api.addToPlaylist('p1', ['s3', 's4']);
    expect(asked.last.url.path, '/rest/updatePlaylist.view');
    expect(params(asked.last)['songIdToAdd'], ['s3', 's4']);

    await api.removeFromPlaylist('p1', [0, 2]);
    expect(params(asked.last)['songIndexToRemove'], ['0', '2']);

    await api.deletePlaylist('p1');
    expect(asked.last.url.path, '/rest/deletePlaylist.view');
    expect(params(asked.last)['id'], ['p1']);
  });

  test('a song moves in a playlist as its songs go back in their new order, all of them', () async {
    final asked = <http.Request>[];

    await changing(asked).moveInPlaylist('p1', from: 2, to: 0);
    expect(asked.last.url.path, '/rest/createPlaylist.view');
    expect(params(asked.last)['playlistId'], ['p1']);
    expect(params(asked.last)['songId'], ['s3', 's1', 's2']);
    expect(params(asked.last).containsKey('name'), isFalse, reason: 'it keeps its name');
  });

  test(
    'on a server with formPost, the songs go in a form\'s body, credentials and all, rather than in the URL',
    () async {
      final asked = <http.Request>[];
      final api = changing(asked, extensions: ['formPost']);

      await api.addToPlaylist('p1', ['s3', 's4']);
      await api.addToPlaylist('p1', ['s5']);

      final posted = asked.where((request) => request.method == 'POST').toList();

      expect(posted, hasLength(2));
      expect(posted.first.url.query, isEmpty);
      expect(posted.first.headers['content-type'], startsWith('application/x-www-form-urlencoded'));
      expect(
        params(posted.first),
        allOf(containsPair('songIdToAdd', ['s3', 's4']), containsPair('t', [credentials.token])),
      );
      expect(
        asked.where((request) => request.url.path.endsWith('getOpenSubsonicExtensions.view')),
        hasLength(1),
        reason: 'asked once',
      );
    },
  );

  test('a playlist with no songs has none', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient(
        (_) async => subsonic({
          'status': 'ok',
          'playlist': {'id': 'p1', 'name': 'Empty', 'songCount': 0},
        }),
      ),
    );
    final (_, songs) = await api.playlist('p1');

    expect(songs, isEmpty);
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

  test('the most played decades add up the plays of the 500 most played albums, by their years', () async {
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
              {'id': 'a1', 'name': 'Pump', 'year': 1989, 'playCount': 10},
              {'id': 'a2', 'name': 'Toys in the Attic', 'year': 1975, 'playCount': 6},
              {'id': 'a3', 'name': 'Aerosmith', 'year': 1973, 'playCount': 5},
              // Without a year, in none.
              {'id': 'a4', 'name': 'Live Bootleg', 'playCount': 30},
              // A server that doesn't say counts each album once.
              {'id': 'a5', 'name': 'Just Push Play', 'year': 2001},
            ],
          },
        });
      }),
    );

    expect(await api.mostPlayedDecades(), [1970, 1980, 2000]);
    expect(asked.queryParameters, containsPair('type', 'frequent'));
    expect(asked.queryParameters, containsPair('size', '500'));
    expect(await api.mostPlayedDecades(size: 1), [1970]);
  });

  test('the most played genres and decades, asked at once, share one list of the most played albums, which is asked '
      'again later', () async {
    var asked = 0;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked++;

        return subsonic({
          'status': 'ok',
          'albumList2': {
            'album': [
              {'id': 'a1', 'name': 'Pump', 'year': 1989, 'genre': 'Rock', 'playCount': 10},
            ],
          },
        });
      }),
    );
    final (genres, decades) = await (api.mostPlayedGenres(), api.mostPlayedDecades()).wait;

    expect([for (final genre in genres) genre.name], ['Rock']);
    expect(decades, [1980]);
    expect(asked, 1);

    await api.mostPlayedGenres();
    expect(asked, 2, reason: 'the plays change');
  });

  test('songs at random are getRandomSongs\', of a genre by its name and from a range of years', () async {
    final asked = <Map<String, String>>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        expect(request.url.path, '/rest/getRandomSongs.view');
        asked.add(request.url.queryParameters);

        return subsonic({
          'status': 'ok',
          'randomSongs': {
            'song': [
              {'id': 's1', 'title': 'Sweet Emotion', 'artist': 'Aerosmith', 'albumId': 'a2', 'coverArt': 'al-a2'},
              {'id': 's2', 'title': 'Love in an Elevator', 'artist': 'Aerosmith', 'albumId': 'a1'},
            ],
          },
        });
      }),
    );
    final songs = await api.randomSongs(size: 50, genre: 'Rock', years: (from: 1970, to: 1979));

    expect([for (final song in songs) song.title], ['Sweet Emotion', 'Love in an Elevator']);
    expect(songs.first.coverArt, 'al-a2');
    expect(asked.single, allOf(containsPair('size', '50'), containsPair('genre', 'Rock')));
    expect(asked.single, allOf(containsPair('fromYear', '1970'), containsPair('toYear', '1979')));

    await api.randomSongs();
    expect(asked.last, containsPair('size', '100'));
    expect(asked.last.keys, isNot(anyOf(contains('genre'), contains('fromYear'), contains('toYear'))));
  });

  test('a server with no songs at random has none', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async => subsonic({'status': 'ok', 'randomSongs': <String, Object?>{}})),
    );

    expect(await api.randomSongs(genre: 'Polka'), isEmpty);
  });

  test('an artist\'s most played songs are their albums\' songs, by plays, from the albums that have played', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        final id = request.url.queryParameters['id'];

        if (request.url.path.endsWith('getArtist.view')) {
          return subsonic({
            'status': 'ok',
            'artist': {
              'id': id,
              'name': 'Aerosmith',
              'album': [
                {'id': 'a1', 'name': 'Toys in the Attic', 'playCount': 9},
                // Never played: without a count, or with 0.
                {'id': 'a0', 'name': 'Aerosmith'},
                {'id': 'a2', 'name': 'Pump', 'playCount': 0},
                {'id': 'a3', 'name': 'Rocks', 'playCount': 4},
              ],
            },
          });
        }

        final songs = switch (id) {
          'a1' => [
            {'id': 's1', 'title': 'Walk This Way', 'playCount': 5},
            {'id': 's2', 'title': 'Big Ten Inch Record'},
            {'id': 's3', 'title': 'Sweet Emotion', 'playCount': 4},
          ],
          _ => [
            {'id': 's4', 'title': 'Back in the Saddle', 'playCount': 4},
          ],
        };

        return subsonic({
          'status': 'ok',
          'album': {'id': id, 'name': 'Album $id', 'song': songs},
        });
      }),
    );
    final songs = await api.mostPlayedSongs('ar1');

    expect(asked.first.queryParameters, containsPair('id', 'ar1'));
    expect(
      [for (final url in asked.skip(1)) url.queryParameters['id']],
      unorderedEquals(['a1', 'a3']),
      reason: 'the played albums alone, at once',
    );
    expect(
      [for (final song in songs) song.title],
      ['Walk This Way', 'Sweet Emotion', 'Back in the Saddle'],
      reason: 'a tie keeps the albums\' order',
    );
    expect(await api.mostPlayedSongs('ar1', size: 1), hasLength(1));
  });

  test('an artist none of whose albums has played has no most played songs, and no albums to open', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return subsonic({
          'status': 'ok',
          'artist': {
            'id': 'ar1',
            'name': 'Aerosmith',
            'album': [
              {'id': 'a1', 'name': 'Toys in the Attic'},
            ],
          },
        });
      }),
    );

    expect(await api.mostPlayedSongs('ar1'), isEmpty);
    expect(asked.single.path, '/rest/getArtist.view');
  });

  test('an artist and their most played songs, asked at once, share one getArtist', () async {
    final asked = <String>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url.path);

        if (request.url.path.endsWith('getArtist.view')) {
          return subsonic({
            'status': 'ok',
            'artist': {
              'id': 'ar1',
              'name': 'Aerosmith',
              'album': [
                {'id': 'a1', 'name': 'Toys in the Attic', 'playCount': 9},
              ],
            },
          });
        }

        return subsonic({
          'status': 'ok',
          'album': {
            'id': 'a1',
            'name': 'Toys in the Attic',
            'song': [
              {'id': 's1', 'title': 'Walk This Way', 'playCount': 5},
            ],
          },
        });
      }),
    );
    final ((artist, albums), songs) = await (api.artist('ar1'), api.mostPlayedSongs('ar1')).wait;

    expect(artist.name, 'Aerosmith');
    expect([for (final album in albums) album.name], ['Toys in the Attic']);
    expect([for (final song in songs) song.title], ['Walk This Way']);
    expect(asked, ['/rest/getArtist.view', '/rest/getAlbum.view']);

    // One that has answered isn't kept: the plays may have changed since.
    await api.artist('ar1');
    expect(asked.where((path) => path.endsWith('getArtist.view')), hasLength(2));
  });

  test('an artist\'s biography is getArtistInfo2\'s, as text, Last.fm\'s link to the rest saying where it comes from', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return subsonic({
          'status': 'ok',
          'artistInfo2': {
            // As Navidrome gives it: Last.fm's summary, sanitized, its lines run together.
            'biography':
                'Aerosmith is an American rock band formed in Boston in 1970. The group&#39;s members are Steven Tyler '
                '&amp; Joe Perry. <a target=\'_blank\' href="https://www.last.fm/music/Aerosmith" rel="nofollow">Read '
                'more on Last.fm</a>',
            'lastFmUrl': 'https://www.last.fm/music/Aerosmith',
          },
        });
      }),
    );
    final biography = (await api.biography('ar1'))!;

    expect(asked.single.path, '/rest/getArtistInfo2.view');
    expect(asked.single.queryParameters, containsPair('id', 'ar1'));
    expect(biography.paragraphs, [
      'Aerosmith is an American rock band formed in Boston in 1970. The group\'s members are Steven Tyler & Joe Perry.',
    ]);
    expect(biography.source, 'Last.fm');
  });

  test('an artist without a biography, or with only the link to one, has none', () async {
    for (final info in <Map<String, Object?>>[
      {},
      {'biography': ''},
      {'biography': ' <a target=\'_blank\' href="https://www.last.fm/music/Nobody">Read more on Last.fm</a>'},
    ]) {
      final api = SubsonicApi(
        Uri.parse('https://music.test'),
        credentials,
        client: MockClient((_) async => subsonic({'status': 'ok', 'artistInfo2': info})),
      );

      expect(await api.biography('ar1'), isNull, reason: '$info');
    }
  });

  test('the artists like one are getArtistInfo2\'s similar artists, in its order; one without them has none', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return subsonic({
          'status': 'ok',
          'artistInfo2': {
            // As Navidrome gives them: those of the library, from Last.fm.
            'similarArtist': [
              {'id': 'ar2', 'name': 'Cheap Trick', 'coverArt': 'ar-ar2', 'albumCount': 3, 'musicBrainzId': 'mb2'},
              {'id': 'ar3', 'name': 'Ramones', 'albumCount': 1},
            ],
          },
        });
      }),
    );
    final similar = await api.similarArtists('ar1');

    expect(asked.single.path, '/rest/getArtistInfo2.view');
    expect(asked.single.queryParameters, containsPair('id', 'ar1'));
    expect([for (final artist in similar) artist.id], ['ar2', 'ar3']);
    expect(similar.first.name, 'Cheap Trick');
    expect(similar.first.coverArt, 'ar-ar2');
    expect(similar.first.albumCount, 3);
    expect(similar.first.musicBrainzId, 'mb2');

    final none = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((_) async => subsonic({'status': 'ok', 'artistInfo2': <String, Object?>{}})),
    );

    expect(await none.similarArtists('ar1'), isEmpty);
  });

  test('an artist\'s biography and the artists like them, asked at once, share one getArtistInfo2', () async {
    final asked = <String>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url.path);

        return subsonic({
          'status': 'ok',
          'artistInfo2': {
            'biography': 'Aerosmith is an American rock band.',
            'similarArtist': [
              {'id': 'ar2', 'name': 'Cheap Trick'},
            ],
          },
        });
      }),
    );
    final (biography, similar) = await (api.biography('ar1'), api.similarArtists('ar1')).wait;

    expect(biography!.paragraphs, ['Aerosmith is an American rock band.']);
    expect([for (final artist in similar) artist.name], ['Cheap Trick']);
    expect(asked, ['/rest/getArtistInfo2.view']);

    // One that has answered isn't kept, as getArtist's isn't.
    await api.biography('ar1');
    expect(asked, hasLength(2));
  });

  test('an artist\'s popular songs are getTopSongs\', asked by their name', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return subsonic({
          'status': 'ok',
          'topSongs': {
            'song': [
              {'id': 's3', 'title': 'Dream On', 'album': 'Aerosmith', 'artistId': 'ar1'},
              {'id': 's1', 'title': 'Walk This Way', 'album': 'Toys in the Attic', 'artistId': 'ar1'},
            ],
          },
        });
      }),
    );
    final songs = await api.popularSongs(const Artist(id: 'ar1', name: 'Aerosmith'), size: 5);

    expect([for (final song in songs) song.title], ['Dream On', 'Walk This Way'], reason: 'in the server\'s order');
    expect(songs.first.album, 'Aerosmith');
    expect(asked.last.path, '/rest/getTopSongs.view');
    expect(asked.last.queryParameters, containsPair('artist', 'Aerosmith'));
    expect(asked.last.queryParameters, containsPair('count', '5'));
    expect(asked.last.queryParameters.containsKey('id'), isFalse, reason: 'a server without topSongsByArtistId');
  });

  test('on a server with topSongsByArtistId, an artist\'s popular songs are asked by their id, which another artist\'s '
      'name can\'t be', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return request.url.path.endsWith('getOpenSubsonicExtensions.view')
            ? subsonic({
                'status': 'ok',
                'openSubsonicExtensions': [
                  {
                    'name': 'topSongsByArtistId',
                    'versions': [1],
                  },
                ],
              })
            : subsonic({
                'status': 'ok',
                'topSongs': {
                  'song': [
                    {'id': 's3', 'title': 'Dream On', 'artistId': 'ar1'},
                  ],
                },
              });
      }),
    );

    expect(await api.popularSongs(const Artist(id: 'ar1', name: 'Aerosmith')), hasLength(1));
    expect(asked.last.queryParameters, allOf(containsPair('id', 'ar1'), containsPair('artist', 'Aerosmith')));
    expect(
      await api.popularSongs(const Artist(id: 'ar1', name: '')),
      hasLength(1),
      reason: 'its id is enough',
    );
    expect(asked.last.queryParameters.containsKey('artist'), isFalse);
  });

  test('an artist the server knows no popular songs of has none; one without a name isn\'t asked about', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return subsonic({'status': 'ok', 'topSongs': <String, Object?>{}});
      }),
    );

    expect(await api.popularSongs(const Artist(id: 'ar1', name: 'Aerosmith')), isEmpty);
    expect(await api.popularSongs(const Artist(id: 'ar2', name: '')), isEmpty);
    expect(
      [for (final url in asked) url.pathSegments.last],
      ['getOpenSubsonicExtensions.view', 'getTopSongs.view'],
      reason: 'the server\'s extensions asked once',
    );
  });

  test('the songs like one are getSimilarSongs2\'s, by the song\'s id, or by its artist\'s where the server refuses '
      'it', () async {
    final asked = <Uri>[];
    var songIds = true;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return request.url.queryParameters['id'] == 's1' && !songIds
            ? subsonic({
                'status': 'failed',
                'error': {'code': 70, 'message': 'Artist not found'},
              })
            : subsonic({
                'status': 'ok',
                'similarSongs2': {
                  'song': [
                    {'id': 's2', 'title': 'Dream On', 'artist': 'Aerosmith', 'artistId': 'ar1'},
                    {'id': 's3', 'title': 'Surrender', 'artist': 'Cheap Trick', 'artistId': 'ar2'},
                  ],
                },
              });
      }),
    );
    const song = Song(
      id: 's1',
      title: 'Walk This Way',
      artists: [Artist(id: 'ar1', name: 'Aerosmith')],
    );
    final similar = await api.similarSongs(song, size: 20);

    expect([for (final found in similar) found.title], ['Dream On', 'Surrender'], reason: 'in the server\'s order');
    expect(similar.last.artistId, 'ar2');
    expect(asked.single.path, '/rest/getSimilarSongs2.view');
    expect(asked.single.queryParameters, allOf(containsPair('id', 's1'), containsPair('count', '20')));

    // A server that takes only an artist's id, as the Subsonic API has it.
    songIds = false;
    asked.clear();
    expect(await api.similarSongs(song), hasLength(2));
    expect([for (final url in asked) url.queryParameters['id']], ['s1', 'ar1']);
    expect(asked.last.queryParameters, containsPair('count', '50'));

    // A song with no artist's id, as one another device sent, has none to ask by.
    await expectLater(api.similarSongs(const Song(id: 's1', title: 'Walk This Way')), throwsA(isA<ServerError>()));
  });

  test('a radio is getSimilarSongs2\'s by the album\'s or the artist\'s id, which Navidrome takes, or by the album\'s '
      'artist\'s where the server refuses an album\'s', () async {
    final asked = <Map<String, String>>[];
    var albumIds = true;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url.queryParameters);

        return request.url.queryParameters['id'] == 'al1' && !albumIds
            ? subsonic({
                'status': 'failed',
                'error': {'code': 70, 'message': 'Artist not found'},
              })
            : subsonic({
                'status': 'ok',
                'similarSongs2': {
                  'song': [
                    {'id': 's2', 'title': 'Dream On', 'artist': 'Aerosmith', 'artistId': 'ar1'},
                  ],
                },
              });
      }),
    );

    expect(await api.radioSongs('al1', artistId: 'ar1', size: 100), hasLength(1));
    expect(asked.single, allOf(containsPair('id', 'al1'), containsPair('count', '100')));
    asked.clear();
    expect(await api.radioSongs('ar1'), hasLength(1));
    expect(asked.single, containsPair('id', 'ar1'));

    albumIds = false;
    asked.clear();
    expect(await api.radioSongs('al1', artistId: 'ar1'), hasLength(1));
    expect([for (final query in asked) query['id']], ['al1', 'ar1']);
    await expectLater(api.radioSongs('al1'), throwsA(isA<ServerError>()), reason: 'no artist to ask by');
  });

  test('a public link is createShare\'s, of the item\'s id, where getUser says the user may share; none where it '
      'says not, createShare unasked', () async {
    final asked = <Uri>[];
    var shareRole = true;
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return switch (request.url.pathSegments.last) {
          'getUser.view' => subsonic({
            'status': 'ok',
            'user': {'username': 'alice', 'shareRole': shareRole},
          }),
          'createShare.view' => subsonic({
            'status': 'ok',
            'shares': {
              'share': [
                {'id': 'sh1', 'url': 'https://music.test/share/sh1', 'username': 'alice', 'visitCount': 0},
              ],
            },
          }),
          _ => http.Response('', 404),
        };
      }),
    );

    expect(api.canShare, isTrue);
    expect(await api.share('al1'), Uri.parse('https://music.test/share/sh1'));
    expect([for (final url in asked) url.path], ['/rest/getUser.view', '/rest/createShare.view']);
    expect(asked.first.queryParameters, containsPair('username', 'alice'));
    expect(asked.last.queryParameters, containsPair('id', 'al1'));

    shareRole = false;
    asked.clear();
    await expectLater(api.share('al1'), throwsA(isA<SharingOff>()));
    expect([for (final url in asked) url.path], ['/rest/getUser.view']);
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

  test('the most played artists add up the plays of the 500 most played albums, by each of their artists, and come as '
      'getArtists lists them', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        if (request.url.path.endsWith('getArtists.view')) {
          return subsonic({
            'status': 'ok',
            'artists': {
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
                {
                  'name': 'M',
                  'artist': [
                    {'id': 'ar3', 'name': 'Miles Davis', 'albumCount': 3},
                  ],
                },
              ],
            },
          });
        }

        return subsonic({
          'status': 'ok',
          'albumList2': {
            'album': [
              {'id': 'a1', 'name': 'Pump', 'playCount': 10, 'artistId': 'ar1'},
              {'id': 'a2', 'name': 'Kind of Blue', 'playCount': 8, 'artistId': 'ar3'},
              {
                'id': 'a3',
                'name': 'Together',
                'playCount': 6,
                'artistId': 'ar2',
                'artists': [
                  {'id': 'ar2', 'name': 'Cheap Trick'},
                  {'id': 'ar1', 'name': 'Aerosmith'},
                ],
              },
              // A server that doesn't say counts each album once.
              {'id': 'a4', 'name': 'In Color', 'artistId': 'ar2'},
              // getArtists doesn't list them.
              {'id': 'a5', 'name': 'Anthology', 'playCount': 30, 'artistId': 'ar9'},
            ],
          },
        });
      }),
    );
    final artists = await api.mostPlayedArtists();

    expect(asked.first.path, '/rest/getAlbumList2.view');
    expect(asked.first.queryParameters, containsPair('type', 'frequent'));
    expect(asked.first.queryParameters, containsPair('size', '500'));
    expect(asked.last.path, '/rest/getArtists.view');
    expect(artists.map((artist) => artist.name), ['Aerosmith', 'Miles Davis', 'Cheap Trick']);
    expect(artists.first.coverArt, 'ar-ar1');
    expect(artists.first.albumCount, 5);
    expect((await api.mostPlayedArtists(size: 2)).map((artist) => artist.id), ['ar1', 'ar3']);
  });

  test('with nothing played yet there are no most played artists, and no artists to ask for', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return subsonic({'status': 'ok', 'albumList2': <String, Object?>{}});
      }),
    );

    expect(await api.mostPlayedArtists(), isEmpty);
    expect(asked.single.path, '/rest/getAlbumList2.view');
  });

  test('an artist comes with their albums, and their MusicBrainz id', () async {
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
            'musicBrainzId': 'mb1',
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
    expect(artist.musicBrainzId, 'mb1', reason: 'OpenSubsonic\'s');
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

  test('the favorites are getStarred2\'s, of each kind the latest starred first', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        expect(request.url.path, '/rest/getStarred2.view');

        return subsonic({
          'status': 'ok',
          'starred2': {
            'artist': [
              {'id': 'ar1', 'name': 'Aerosmith', 'starred': '2026-01-02T10:00:00Z'},
            ],
            'album': [
              {'id': 'a1', 'name': 'Toys in the Attic', 'starred': '2025-06-01T10:00:00Z'},
              {'id': 'a2', 'name': 'Rocks', 'starred': '2026-03-01T10:00:00.123Z'},
            ],
            'song': [
              {'id': 's1', 'title': 'Walk This Way', 'starred': '2026-02-01T10:00:00Z'},
              {'id': 's2', 'title': 'Sweet Emotion', 'starred': '2026-09-01T10:00:00Z'},
              {'id': 's3', 'title': 'Dream On'},
            ],
          },
        });
      }),
    );
    final (:artists, :albums, :songs) = await api.favorites();

    expect([for (final artist in artists) artist.name], ['Aerosmith']);
    expect([for (final album in albums) album.id], ['a2', 'a1']);
    expect([for (final song in songs) song.id], ['s2', 's1', 's3'], reason: 'one that doesn\'t say when, last');
  });

  test('none starred, there are no favorites', () async {
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async => subsonic({'status': 'ok', 'starred2': <String, Object?>{}})),
    );
    final (:artists, :albums, :songs) = await api.favorites();

    expect([artists, albums, songs], everyElement(isEmpty));
  });

  test('a favorite is starred, and unstarred, by the parameter of its kind', () async {
    final asked = <Uri>[];
    final api = SubsonicApi(
      Uri.parse('https://music.test'),
      credentials,
      client: MockClient((request) async {
        asked.add(request.url);

        return subsonic({'status': 'ok'});
      }),
    );

    await api.setFavorite(FavoriteKind.song, 's1', favorite: true);
    await api.setFavorite(FavoriteKind.album, 'a1', favorite: true);
    await api.setFavorite(FavoriteKind.artist, 'ar1', favorite: false);
    expect([for (final url in asked) url.path], ['/rest/star.view', '/rest/star.view', '/rest/unstar.view']);
    expect(asked[0].queryParameters, containsPair('id', 's1'));
    expect(asked[1].queryParameters, containsPair('albumId', 'a1'));
    expect(asked[2].queryParameters, containsPair('artistId', 'ar1'));
    expect(asked[1].queryParameters.containsKey('id'), isFalse);
  });
}
