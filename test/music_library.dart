import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/subsonic/api.dart';

/// A Subsonic server with a small library, as the car browses it: three albums, two of Aerosmith's (Toys in the Attic,
/// a1, and Pump, a2) and one of Miles Davis's (Kind of Blue, a3), their songs (s1 to s4), the playlists Road trip (p1)
/// and chill (p2), a favorite song (Love in an Elevator), the genres Rock and Jazz, and a search that finds by name.
/// [asked] gets the endpoints asked for, with their queries.
SubsonicApi musicLibrary({List<(String, Map<String, String>)>? asked}) => SubsonicApi(
  Uri.parse('https://music.test'),
  const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
  client: MockClient((request) async {
    final endpoint = request.url.pathSegments.last.replaceAll('.view', '');
    final query = request.url.queryParameters;
    asked?.add((endpoint, query));
    final found = _answer(endpoint, query);

    return found == null
        ? http.Response('', 404)
        : http.Response(
            jsonEncode({
              'subsonic-response': {'status': 'ok', ...found},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
  }),
);

const _artists = {
  'ar1': {'id': 'ar1', 'name': 'Aerosmith', 'coverArt': 'ar-ar1'},
  'ar2': {'id': 'ar2', 'name': 'Miles Davis', 'coverArt': 'ar-ar2'},
};

const _albums = {
  'a1': {
    'id': 'a1',
    'name': 'Toys in the Attic',
    'artist': 'Aerosmith',
    'artistId': 'ar1',
    'coverArt': 'al-a1',
    'year': 1975,
    'genre': 'Rock',
    'playCount': 20,
  },
  'a2': {
    'id': 'a2',
    'name': 'Pump',
    'artist': 'Aerosmith',
    'artistId': 'ar1',
    'coverArt': 'al-a2',
    'year': 1989,
    'genre': 'Rock',
  },
  'a3': {
    'id': 'a3',
    'name': 'Kind of Blue',
    'artist': 'Miles Davis',
    'artistId': 'ar2',
    'coverArt': 'al-a3',
    'year': 1959,
    'genre': 'Jazz',
    'playCount': 5,
  },
};

const _songs = {
  's1': {'id': 's1', 'title': 'Sweet Emotion', 'artist': 'Aerosmith', 'albumId': 'a1', 'coverArt': 'al-a1'},
  's2': {'id': 's2', 'title': 'Walk This Way', 'artist': 'Aerosmith', 'albumId': 'a1', 'coverArt': 'al-a1'},
  's3': {'id': 's3', 'title': 'Love in an Elevator', 'artist': 'Aerosmith', 'albumId': 'a2', 'coverArt': 'al-a2'},
  's4': {'id': 's4', 'title': 'So What', 'artist': 'Miles Davis', 'albumId': 'a3', 'coverArt': 'al-a3'},
};

const _playlists = {
  'p1': {
    'id': 'p1',
    'name': 'Road trip',
    'coverArt': 'pl-p1',
    'owner': 'a',
    'entry': ['s2', 's4'],
  },
  'p2': {
    'id': 'p2',
    'name': 'chill',
    'owner': 'a',
    'entry': ['s4'],
  },
};

Map<String, Object?>? _answer(String endpoint, Map<String, String> query) {
  final id = query['id'];
  final text = query['query']?.toLowerCase() ?? '';
  List<Map<String, Object?>> albums(List<String> ids) => [for (final id in ids) _albums[id]!];
  List<Map<String, Object?>> songsOf(String album) => [
    for (final song in _songs.values)
      if (song['albumId'] == album) {...song, 'album': _albums[album]!['name']},
  ];
  Map<String, Object?> playlist(String id, {bool entries = false}) {
    final playlist = _playlists[id]!;
    final songs = playlist['entry']! as List<String>;

    return {
      for (final MapEntry(:key, :value) in playlist.entries)
        if (key != 'entry') key: value,
      'songCount': songs.length,
      if (entries) 'entry': [for (final song in songs) _songs[song]],
    };
  }

  return switch (endpoint) {
    'getAlbumList2' => {
      'albumList2': {
        'album': switch (query['type']) {
          'byYear' => albums(['a2', 'a1', 'a3']),
          'frequent' => albums(['a1', 'a3']),
          'newest' => albums(['a3', 'a2']),
          'alphabeticalByName' => albums(['a3', 'a2', 'a1']),
          _ => const <Map<String, Object?>>[],
        },
      },
    },
    'getGenres' => {
      'genres': {
        'genre': [
          {'value': 'Rock', 'albumCount': 2},
          {'value': 'Jazz', 'albumCount': 1},
        ],
      },
    },
    'getRandomSongs' => {
      'randomSongs': {
        'song': [
          for (final song in _songs.values)
            if (query['genre'] == null || _albums[song['albumId']]!['genre'] == query['genre']) song,
        ],
      },
    },
    'getAlbum' when _albums[id] != null => {
      'album': {..._albums[id]!, 'song': songsOf(id!)},
    },
    'getSong' when _songs[id] != null => {'song': _songs[id]},
    // Like an album, or an artist: the songs of the others.
    'getSimilarSongs2' => {
      'similarSongs2': {
        'song': [
          for (final song in _songs.values)
            if (song['albumId'] != id && _albums[song['albumId']]!['artistId'] != id) song,
        ],
      },
    },
    'getArtists' => {
      'artists': {
        'index': [
          {'name': 'A', 'artist': _artists.values.toList()},
        ],
      },
    },
    'getArtist' when _artists[id] != null => {
      'artist': {
        ..._artists[id]!,
        'album': [
          for (final album in _albums.values)
            if (album['artistId'] == id) album,
        ],
      },
    },
    'getPlaylists' => {
      'playlists': {
        'playlist': [for (final id in _playlists.keys) playlist(id)],
      },
    },
    'getPlaylist' when _playlists[id] != null => {'playlist': playlist(id!, entries: true)},
    'getStarred2' => {
      'starred2': {
        'song': [_songs['s3']],
      },
    },
    'search3' => {
      'searchResult3': {
        'artist': [
          for (final artist in _artists.values)
            if (artist['name']!.toLowerCase().contains(text)) artist,
        ],
        'album': [
          for (final album in _albums.values)
            if ((album['name']! as String).toLowerCase().contains(text)) album,
        ],
        'song': [
          for (final song in _songs.values)
            if (song['title']!.toLowerCase().contains(text)) song,
        ],
      },
    },
    _ => null,
  };
}
