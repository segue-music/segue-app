import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../segue/protocol.dart';
import '../server/models.dart';
import '../server/server.dart';

/// Subsonic token authentication: the password never leaves the device, only md5(password + salt).
class SubsonicCredentials implements Credentials {
  const SubsonicCredentials({required this.username, required this.token, required this.salt});

  factory SubsonicCredentials.fromPassword(String username, String password) {
    final random = Random.secure();
    final salt = List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
    return SubsonicCredentials(
      username: username,
      token: md5.convert(utf8.encode(password + salt)).toString(),
      salt: salt,
    );
  }

  @override
  final String username;
  final String token;
  final String salt;
}

/// The parts of the Subsonic API the app uses.
class SubsonicApi implements MediaServer {
  SubsonicApi(Uri server, this.credentials, {http.Client? client})
    : server = server.path.endsWith('/') ? server : server.replace(path: '${server.path}/'),
      _http = client ?? http.Client();

  final Uri server;
  @override
  final SubsonicCredentials credentials;
  final http.Client _http;

  // Whether the server has OpenSubsonic's transcodeOffset, once asked.
  Future<bool>? _transcodeOffset;

  @override
  Api get api => Api.subsonic;

  @override
  Auth get auth => Auth.subsonic(username: credentials.username, token: credentials.token, salt: credentials.salt);

  Future<void> ping() => _get('ping');

  /// Albums by name are getAlbumList2's alphabeticalByName; the latest added, its newest; by release
  /// date, its byYear over every year, which Navidrome sorts by the full date where it has one; the most
  /// played, its frequent.
  @override
  Future<List<Album>> albums({required AlbumOrder order, int size = 100, int offset = 0}) => _albumList(
    switch (order) {
      AlbumOrder.latest => {'type': 'newest'},
      AlbumOrder.name => {'type': 'alphabeticalByName'},
      // A range from a later year to an earlier one lists the latest first.
      AlbumOrder.released => {'type': 'byYear', 'fromYear': '9999', 'toYear': '0'},
      AlbumOrder.mostPlayed => {'type': 'frequent'},
    },
    size: size,
    offset: offset,
  );

  /// getAlbumList2's frequent, which takes no genre: a genre's most played are those of the genre among
  /// the 500 most played, as many as a list gives at once (Navidrome's limit).
  @override
  Future<List<Album>> mostPlayedAlbums({int size = 20, String? genre}) async {
    if (genre == null) {
      return albums(order: AlbumOrder.mostPlayed, size: size);
    }

    final mostPlayed = await _albumListItems({'type': 'frequent'}, size: 500);
    return [
      for (final json in mostPlayed)
        if (_albumGenres(json).contains(genre)) _album(json),
    ].take(size).toList();
  }

  /// Albums in a list of getAlbumList2, which [query] names: its type (newest, recent, frequent, byYear,
  /// alphabeticalByName…) and the type's parameters.
  Future<List<Album>> _albumList(Map<String, String> query, {required int size, int offset = 0}) async => [
    for (final json in await _albumListItems(query, size: size, offset: offset)) _album(json),
  ];

  /// The same albums, as the server sends them.
  Future<List<Map<String, dynamic>>> _albumListItems(
    Map<String, String> query, {
    required int size,
    int offset = 0,
  }) async {
    final body = await _get('getAlbumList2', {...query, 'size': '$size', 'offset': '$offset'});
    final list = (body['albumList2'] as Map<String, dynamic>?)?['album'] as List? ?? const [];
    return [for (final album in list) album as Map<String, dynamic>];
  }

  /// Every genre (getGenres), by its name: Subsonic has no ids for them.
  @override
  Future<List<Genre>> genres() async {
    final body = await _get('getGenres');
    final list = (body['genres'] as Map<String, dynamic>?)?['genre'] as List? ?? const [];
    return [for (final genre in list) _genre(genre as Map<String, dynamic>)];
  }

  /// getAlbumList2's byGenre, which Navidrome sorts by name.
  @override
  Future<List<Album>> genreAlbums(String id, {int size = 100, int offset = 0}) =>
      _albumList({'type': 'byGenre', 'genre': id}, size: size, offset: offset);

  /// Subsonic counts no plays by genre: a genre's are those of its albums among the 500 most played,
  /// added up. A server that doesn't say an album's plays counts it once.
  @override
  Future<List<Genre>> mostPlayedGenres({int size = 10}) async {
    final plays = <String, int>{};

    for (final album in await _albumListItems({'type': 'frequent'}, size: 500)) {
      for (final genre in _albumGenres(album)) {
        plays[genre] = (plays[genre] ?? 0) + ((album['playCount'] as num?)?.toInt() ?? 1);
      }
    }

    return [for (final name in rankedByCount(plays).take(size)) Genre(id: name, name: name)];
  }

  /// Subsonic lists no songs by plays: an artist's most played are the songs of their albums
  /// (getArtist), ranked by their plays, opening (getAlbum) only the albums that have played. A song of
  /// theirs on another artist's album isn't among them.
  @override
  Future<List<Song>> mostPlayedSongs(String artistId, {int size = 10}) async {
    final artist = (await _get('getArtist', {'id': artistId}))['artist'] as Map<String, dynamic>;
    final played = [
      for (final album in artist['album'] as List? ?? const [])
        if (_playCount(album as Map<String, dynamic>) > 0) album['id'] as String,
    ];
    final albums = await Future.wait([
      for (final id in played) _get('getAlbum', {'id': id}),
    ]);
    final plays = {
      for (final body in albums)
        for (final song in (body['album'] as Map<String, dynamic>)['song'] as List? ?? const [])
          if (_playCount(song as Map<String, dynamic>) > 0) _song(song): _playCount(song),
    };
    return rankedByCount(plays).take(size).toList();
  }

  /// getTopSongs, which asks by the artist's name: Navidrome learns the artist's top tracks from its agents (Last.fm's,
  /// where it's on) and gives those it has; none where no agent knows them.
  @override
  Future<List<Song>> popularSongs(Artist artist, {int size = 10}) async {
    if (artist.name.isEmpty) {
      return const [];
    }

    final body = await _get('getTopSongs', {'artist': artist.name, 'count': '$size'});
    return [
      for (final song in (body['topSongs'] as Map<String, dynamic>?)?['song'] as List? ?? const [])
        _song(song as Map<String, dynamic>),
    ];
  }

  @override
  Future<(Album, List<Song>)> album(String id) async {
    final json = (await _get('getAlbum', {'id': id}))['album'] as Map<String, dynamic>;
    final songs = json['song'] as List? ?? const [];
    return (_album(json), [for (final song in songs) _song(song as Map<String, dynamic>)]);
  }

  /// A song (getSong).
  @override
  Future<Song> song(String id) async => _song((await _get('getSong', {'id': id}))['song'] as Map<String, dynamic>);

  /// OpenSubsonic's getLyricsBySongId (its songLyrics extension, which Navidrome has, from the file's
  /// tags or a .lrc next to it): the first synced lyrics, else the first. Their offset shifts every line,
  /// a positive one sooner. They come from the server, by the name OpenSubsonic gives it (navidrome).
  @override
  Future<Lyrics?> lyrics(String songId) async {
    final body = await _get('getLyricsBySongId', {'id': songId});
    final all = [
      for (final json in (body['lyricsList'] as Map<String, dynamic>?)?['structuredLyrics'] as List? ?? const [])
        json as Map<String, dynamic>,
    ];
    final chosen = all.where((json) => json['synced'] == true).firstOrNull ?? all.firstOrNull;

    if (chosen == null) {
      return null;
    }

    final synced = chosen['synced'] == true;
    final offset = Duration(milliseconds: (chosen['offset'] as num?)?.toInt() ?? 0);
    final lines = [
      for (final json in chosen['line'] as List? ?? const [])
        if (json case {'value': final String text})
          LyricLine(
            text,
            start: synced && json['start'] is num
                ? Duration(milliseconds: (json['start'] as num).toInt()) - offset
                : null,
          ),
    ];
    final type = body['type'] as String? ?? '';
    return lines.isEmpty
        ? null
        : Lyrics(lines, provider: type.isEmpty ? null : '${type[0].toUpperCase()}${type.substring(1)}');
  }

  /// Artists, albums and songs whose name, title or artist matches [query] (search3).
  @override
  Future<SearchResults> search(String query, {int artists = 5, int albums = 10, int songs = 50}) async {
    final body = await _get('search3', {
      'query': query,
      'artistCount': '$artists',
      'albumCount': '$albums',
      'songCount': '$songs',
    });
    final result = body['searchResult3'] as Map<String, dynamic>? ?? const {};
    return (
      artists: [for (final artist in result['artist'] as List? ?? const []) _artist(artist as Map<String, dynamic>)],
      albums: [for (final album in result['album'] as List? ?? const []) _album(album as Map<String, dynamic>)],
      songs: [for (final song in result['song'] as List? ?? const []) _song(song as Map<String, dynamic>)],
    );
  }

  /// Every artist, by name (getArtists, which groups them by letter).
  @override
  Future<List<Artist>> artists() async {
    final body = await _get('getArtists');
    final index = (body['artists'] as Map<String, dynamic>?)?['index'] as List? ?? const [];
    return [
      for (final letter in index)
        for (final artist in (letter as Map<String, dynamic>)['artist'] as List? ?? const [])
          _artist(artist as Map<String, dynamic>),
    ];
  }

  /// Subsonic counts no plays by artist: an artist's are those of the albums they are an artist of among the 500 most
  /// played, added up, as a genre's are. One getArtists doesn't list is left out, as it is of the artists tab.
  @override
  Future<List<Artist>> mostPlayedArtists({int size = 100}) async {
    final plays = <String, int>{};

    for (final album in await _albumListItems({'type': 'frequent'}, size: 500)) {
      for (final artist in _albumArtists(album)) {
        plays[artist] = (plays[artist] ?? 0) + ((album['playCount'] as num?)?.toInt() ?? 1);
      }
    }

    if (plays.isEmpty) {
      return const [];
    }

    final artists = {for (final artist in await this.artists()) artist.id: artist};
    return [for (final id in rankedByCount(plays)) ?artists[id]].take(size).toList();
  }

  /// An artist and their albums (getArtist).
  @override
  Future<(Artist, List<Album>)> artist(String id) async {
    final json = (await _get('getArtist', {'id': id}))['artist'] as Map<String, dynamic>;
    final albums = json['album'] as List? ?? const [];
    return (_artist(json), [for (final album in albums) _album(album as Map<String, dynamic>)]);
  }

  /// The format of a transcoded song is the server's pick (Navidrome's is Opus).
  @override
  Uri streamUrl(String songId, {int? maxBitRate}) =>
      _url('stream', {'id': songId, 'maxBitRate': ?maxBitRate?.toString()});

  /// stream's timeOffset, on a server that has OpenSubsonic's transcodeOffset. Without it, a server may leave
  /// timeOffset out (the Subsonic API has it for videos only), and the player would take the start for that point.
  /// Navidrome starts a transcoded song there, but sends a song it doesn't transcode from its start: the player asks only
  /// for a stream that can't seek, which a file can.
  @override
  Future<Uri?> transcodedStreamUrl(String songId, {required int maxBitRate, required Duration from}) async =>
      await _startsTranscodesLater
      ? _url('stream', {'id': songId, 'maxBitRate': '$maxBitRate', 'timeOffset': '${from.inSeconds}'})
      : null;

  /// Whether the server has OpenSubsonic's transcodeOffset: asked once, unless it couldn't be (no network), and then
  /// asked again the next time.
  Future<bool> get _startsTranscodesLater => _transcodeOffset ??= _extensions().then(
    (extensions) => extensions.contains('transcodeOffset'),
    onError: (Object e) {
      // A server that answers with an error has no OpenSubsonic extensions; one that doesn't answer may.
      if (e is! ServerError) {
        _transcodeOffset = null;
      }

      return false;
    },
  );

  /// The names of the OpenSubsonic extensions the server has (getOpenSubsonicExtensions).
  Future<List<String>> _extensions() async {
    final extensions = (await _get('getOpenSubsonicExtensions'))['openSubsonicExtensions'] as List? ?? const [];
    return [for (final extension in extensions) (extension as Map<String, dynamic>)['name'] as String];
  }

  /// A scrobble's submission, which counts the play. What plays shows in the server's now playing
  /// through the hub instead, which counts nothing (SPEC.md, section 12).
  @override
  Future<void> scrobble(String songId, {required DateTime time}) =>
      _get('scrobble', {'id': songId, 'submission': 'true', 'time': '${time.millisecondsSinceEpoch}'});

  @override
  Uri coverArtUrl(String id, {int size = 300}) => _url('getCoverArt', {'id': id, 'size': '$size'});

  @override
  Future<Uint8List> coverArt(String id, {int size = 300}) async {
    final response = await _http.get(coverArtUrl(id, size: size));

    if (response.statusCode != 200 || !(response.headers['content-type'] ?? '').startsWith('image/')) {
      throw ServerError('no cover for $id (HTTP ${response.statusCode})');
    }

    return response.bodyBytes;
  }

  /// Subsonic keeps no sign-in: the token is good until the password changes.
  @override
  Future<void> signOut() async {}

  Uri _url(String endpoint, [Map<String, String> params = const {}]) => server
      .resolve('rest/$endpoint.view')
      .replace(
        queryParameters: {
          'u': credentials.username,
          't': credentials.token,
          's': credentials.salt,
          'v': '1.16.1',
          'c': clientName,
          'f': 'json',
          ...params,
        },
      );

  Future<Map<String, dynamic>> _get(String endpoint, [Map<String, String> params = const {}]) async {
    final response = await _http.get(_url(endpoint, params));

    if (response.statusCode != 200) {
      throw ServerError('${server.host}: HTTP ${response.statusCode}');
    }

    final body =
        (jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>)['subsonic-response']
            as Map<String, dynamic>;

    if (body['status'] != 'ok') {
      final error = body['error'] as Map<String, dynamic>?;
      final code = (error?['code'] as num?)?.toInt();
      // Code 40 is a wrong username or password.
      throw ServerError(error?['message'] as String? ?? 'request failed', isAuth: code == 40 || code == 41);
    }

    return body;
  }

  @override
  void close() => _http.close();
}

/// An album's record labels, release date and MusicBrainz id are OpenSubsonic's, which a plain Subsonic server doesn't
/// give. The release date is that of the album's edition, else the original one. Navidrome fills them from the tags
/// that say which date they are (a release date, an original date, or a date beside an original one); from a date tag
/// alone it gives only the year.
Album _album(Map<String, dynamic> json) => Album(
  id: json['id'] as String,
  name: json['name'] as String? ?? '',
  artist: json['artist'] as String?,
  coverArt: json['coverArt'] as String?,
  year: (json['year'] as num?)?.toInt(),
  songCount: (json['songCount'] as num?)?.toInt(),
  artistId: json['artistId'] as String?,
  releaseDate:
      _releaseDate(json['releaseDate'] as Map<String, dynamic>?) ??
      _releaseDate(json['originalReleaseDate'] as Map<String, dynamic>?),
  recordLabels: [
    for (final label in json['recordLabels'] as List? ?? const [])
      if ((label as Map<String, dynamic>)['name'] case final String name) name,
  ],
  musicBrainzId: switch (json['musicBrainzId']) {
    final String id when id.isNotEmpty => id,
    _ => null,
  },
  // In Navidrome, the files' MusicBrainz types, and whether they are tagged as a compilation.
  releaseType: json['isCompilation'] == true
      ? ReleaseType.compilation
      : ReleaseType.named([
          for (final type in json['releaseTypes'] as List? ?? const [])
            if (type is String) type,
        ]),
);

/// An OpenSubsonic ItemDate, as much of a date as the server knows; none without a year.
ReleaseDate? _releaseDate(Map<String, dynamic>? json) {
  int? part(String key) => switch (json?[key]) {
    final num value when value > 0 => value.toInt(),
    _ => null,
  };

  final year = part('year');
  return year == null ? null : ReleaseDate(year, month: part('month'), day: part('day'));
}

/// An album's genres: Subsonic's genre, its first, and OpenSubsonic's genres, all of them.
Set<String> _albumGenres(Map<String, dynamic> json) => {
  if (json['genre'] case final String genre) genre,
  for (final genre in json['genres'] as List? ?? const [])
    if ((genre as Map<String, dynamic>)['name'] case final String name) name,
};

/// The ids of an album's artists: Subsonic's artistId, and OpenSubsonic's artists, all of them.
Set<String> _albumArtists(Map<String, dynamic> json) => {
  if (json['artistId'] case final String id) id,
  for (final artist in json['artists'] as List? ?? const [])
    if ((artist as Map<String, dynamic>)['id'] case final String id) id,
};

/// How many times the user played an album or a song; none when the server doesn't say.
int _playCount(Map<String, dynamic> json) => (json['playCount'] as num?)?.toInt() ?? 0;

Song _song(Map<String, dynamic> json) => Song(
  id: json['id'] as String,
  title: json['title'] as String? ?? '',
  artist: json['artist'] as String?,
  album: json['album'] as String?,
  coverArt: json['coverArt'] as String?,
  duration: json['duration'] == null ? null : Duration(seconds: (json['duration'] as num).toInt()),
  albumId: json['albumId'] as String?,
  artists: _songArtists(json),
);

/// A song's artists: OpenSubsonic's artists, all of them, or else Subsonic's one, artistId, whom its artist names.
List<Artist> _songArtists(Map<String, dynamic> json) => switch (json['artists']) {
  final List<Object?> artists when artists.isNotEmpty => [
    for (final artist in artists) _artist(artist as Map<String, dynamic>),
  ],
  _ => [if (json['artistId'] case final String id) Artist(id: id, name: json['artist'] as String? ?? '')],
};

Genre _genre(Map<String, dynamic> json) => Genre(
  id: json['value'] as String,
  name: json['value'] as String,
  albumCount: (json['albumCount'] as num?)?.toInt(),
);

Artist _artist(Map<String, dynamic> json) => Artist(
  id: json['id'] as String,
  name: json['name'] as String? ?? '',
  coverArt: json['coverArt'] as String?,
  albumCount: (json['albumCount'] as num?)?.toInt(),
);
