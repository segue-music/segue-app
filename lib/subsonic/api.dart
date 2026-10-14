import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../segue/protocol.dart';
import '../server/models.dart';
import '../server/server.dart';
import 'navidrome_ids.dart';

final _log = Logger('SubsonicApi');

/// What a Subsonic server knows the user by: a token of their password ([SubsonicToken]), or, on an OpenSubsonic server
/// with apiKeyAuthentication, a key they made there ([SubsonicApiKey]), which they can take back there without changing
/// the password, and which a server may take alone (LMS; Navidrome's too, from the release after 0.64.2).
sealed class SubsonicCredentials implements Credentials {
  const factory SubsonicCredentials({required String username, required String token, required String salt}) =
      SubsonicToken;

  factory SubsonicCredentials.fromPassword(String username, String password) {
    final random = Random.secure();
    final salt = List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();

    return SubsonicToken(username: username, token: md5.convert(utf8.encode(password + salt)).toString(), salt: salt);
  }
}

/// Subsonic token authentication: the password never leaves the device, only md5(password + salt).
class SubsonicToken implements SubsonicCredentials {
  const SubsonicToken({required this.username, required this.token, required this.salt});

  @override
  final String username;
  final String token;
  final String salt;
}

/// An API key (OpenSubsonic's apiKeyAuthentication), and whose it is, as the server says (tokenInfo).
class SubsonicApiKey implements SubsonicCredentials {
  const SubsonicApiKey({required this.username, required this.apiKey});

  @override
  final String username;
  final String apiKey;
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

  // The names of the OpenSubsonic extensions the server has, once asked.
  Future<Set<String>>? _extensionNames;

  // The requests under way that more than one method makes ([_shared]), by their endpoint and the id they ask for.
  final _sharedRequests = <(String, String), Future<Map<String, dynamic>>>{};

  // The request under way for the 500 most played albums ([_mostPlayedAlbumItems]).
  Future<List<Map<String, dynamic>>>? _mostPlayedRequest;

  // Whether the server gives its items the ids Navidrome 0.64 gave them ([hasCanonicalIds]), as its last answer said.
  bool _canonicalIds = false;

  // Which server it is, as the log last had it ([_kindOf]).
  String? _kind;

  @override
  Api get api => Api.subsonic;

  /// The canonical id ([canonicalId], [canonicalCoverId]) once an answer has said the server is a Navidrome from 0.64;
  /// until then, and on another server, [id] itself: on a Navidrome from before 0.64, a canonical id finds nothing.
  @override
  String currentId(String id, {bool cover = false}) => switch ((_canonicalIds, cover)) {
    (false, _) => id,
    (true, false) => canonicalId(id),
    (true, true) => canonicalCoverId(id),
  };

  @override
  Auth get auth => switch (credentials) {
    SubsonicToken(:final username, :final token, :final salt) => Auth.subsonic(
      username: username,
      token: token,
      salt: salt,
    ),
    SubsonicApiKey(:final apiKey) => Auth.apiKey(apiKey: apiKey),
  };

  /// Whether the server takes API keys (OpenSubsonic's apiKeyAuthentication).
  Future<bool> takesApiKeys() => _has('apiKeyAuthentication');

  /// Whose the API key the app asks with is (tokenInfo), which it doesn't say itself.
  Future<String> keyUsername() async =>
      ((await _get('tokenInfo'))['tokenInfo'] as Map<String, dynamic>)['username'] as String;

  @override
  Future<void> ping() => _get('ping');

  /// Albums by name are getAlbumList2's alphabeticalByName; the latest added, its newest; by release
  /// date, its byYear over every year, which Navidrome sorts by the full date where it has one; the most
  /// played, its frequent; the recently played, its recent.
  @override
  Future<List<Album>> albums({required AlbumOrder order, int size = 100, int offset = 0}) => _albumList(
    switch (order) {
      AlbumOrder.latest => {'type': 'newest'},
      AlbumOrder.name => {'type': 'alphabeticalByName'},
      // A range from a later year to an earlier one lists the latest first.
      AlbumOrder.released => {'type': 'byYear', 'fromYear': '9999', 'toYear': '0'},
      AlbumOrder.mostPlayed => {'type': 'frequent'},
      AlbumOrder.recentlyPlayed => {'type': 'recent'},
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

    final mostPlayed = await _mostPlayedAlbumItems();

    return [
      for (final json in mostPlayed)
        if (_albumGenres(json).contains(genre)) _album(json),
    ].take(size).toList();
  }

  /// The 500 most played albums (getAlbumList2's frequent), as many as a list gives at once (Navidrome's limit), which
  /// the genres, the decades and the artists the user plays most are counted from, as the server sends them. The home
  /// asks for the genres and the decades at once: a request under way answers both. One that has answered isn't kept,
  /// as the plays change.
  Future<List<Map<String, dynamic>>> _mostPlayedAlbumItems() =>
      _mostPlayedRequest ??= _albumListItems({'type': 'frequent'}, size: 500).whenComplete(() {
        _mostPlayedRequest = null;
      });

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

    for (final album in await _mostPlayedAlbumItems()) {
      for (final genre in _albumGenres(album)) {
        plays[genre] = (plays[genre] ?? 0) + ((album['playCount'] as num?)?.toInt() ?? 1);
      }
    }

    return [for (final name in rankedByCount(plays).take(size)) Genre(id: name, name: name)];
  }

  /// A decade's plays are those of its albums, by their year, among the 500 most played, added up, as a genre's are. An
  /// album without a year is in none.
  @override
  Future<List<int>> mostPlayedDecades({int size = 10}) async {
    final plays = <int, int>{};

    for (final album in await _mostPlayedAlbumItems()) {
      if (album['year'] case final num year when year > 0) {
        final decade = year.toInt() ~/ 10 * 10;
        plays[decade] = (plays[decade] ?? 0) + ((album['playCount'] as num?)?.toInt() ?? 1);
      }
    }

    return rankedByCount(plays).take(size).toList();
  }

  /// getRandomSongs, which takes 500 at most, of the genre by its name, and from the songs' years.
  @override
  Future<List<Song>> randomSongs({int size = 100, String? genre, ({int from, int to})? years}) async {
    final body = await _get('getRandomSongs', {
      'size': '$size',
      'genre': ?genre,
      'fromYear': ?years?.from.toString(),
      'toYear': ?years?.to.toString(),
    });

    return [
      for (final json in (body['randomSongs'] as Map<String, dynamic>?)?['song'] as List? ?? const [])
        _song(json as Map<String, dynamic>),
    ];
  }

  /// Subsonic lists no songs by plays: an artist's most played are the songs of their albums
  /// (getArtist), ranked by their plays, opening (getAlbum) only the albums that have played. A song of
  /// theirs on another artist's album isn't among them.
  @override
  Future<List<Song>> mostPlayedSongs(String artistId, {int size = 10}) async {
    final artist = await _artistJson(artistId);
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

  /// getTopSongs: Navidrome learns the artist's top tracks from its agents (Last.fm's, where it's on) and gives those it
  /// has; none where no agent knows them. By the artist's id where the server has OpenSubsonic's topSongsByArtistId
  /// (Navidrome from 0.64), and otherwise by their name, which another artist may have too.
  @override
  Future<List<Song>> popularSongs(Artist artist, {int size = 10}) async {
    final byId = await _has('topSongsByArtistId');

    if (!byId && artist.name.isEmpty) {
      return const [];
    }

    final body = await _get('getTopSongs', {
      if (byId) 'id': artist.id,
      // With the id too, which goes first: the API names an artist so, and a server may still want it.
      if (artist.name.isNotEmpty) 'artist': artist.name,
      'count': '$size',
    });

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

  /// getPlaylists: the user's, and the public ones of other users.
  @override
  Future<List<Playlist>> playlists() async {
    final body = await _get('getPlaylists');
    final list = (body['playlists'] as Map<String, dynamic>?)?['playlist'] as List? ?? const [];

    return [for (final playlist in list) _playlist(playlist as Map<String, dynamic>, credentials.username)];
  }

  /// getPlaylist, whose entries are its songs.
  @override
  Future<(Playlist, List<Song>)> playlist(String id) async {
    final json = (await _get('getPlaylist', {'id': id}))['playlist'] as Map<String, dynamic>;
    final songs = json['entry'] as List? ?? const [];

    return (_playlist(json, credentials.username), [for (final song in songs) _song(song as Map<String, dynamic>)]);
  }

  @override
  Future<void> createPlaylist(String name, {List<String> songIds = const []}) =>
      _post('createPlaylist', {'name': name, 'songId': songIds});

  @override
  Future<void> renamePlaylist(String id, String name) => _get('updatePlaylist', {'playlistId': id, 'name': name});

  @override
  Future<void> deletePlaylist(String id) => _get('deletePlaylist', {'id': id});

  @override
  Future<void> addToPlaylist(String id, List<String> songIds) =>
      _post('updatePlaylist', {'playlistId': id, 'songIdToAdd': songIds});

  @override
  Future<void> removeFromPlaylist(String id, List<int> indexes) => _post('updatePlaylist', {
    'playlistId': id,
    'songIndexToRemove': [for (final index in indexes) '$index'],
  });

  /// Subsonic moves no song in a playlist: its songs go back in their new order, all of them, as getPlaylist gives them
  /// (createPlaylist, with the playlist's id, replaces them).
  @override
  Future<void> moveInPlaylist(String id, {required int from, required int to}) async {
    final (_, songs) = await playlist(id);
    final ids = [for (final song in songs) song.id];

    ids.insert(to, ids.removeAt(from));
    await _post('createPlaylist', {'playlistId': id, 'songId': ids});
  }

  /// getStarred2, whose items say when the user starred them (starred), by which they come here, the latest first.
  @override
  Future<FavoriteItems> favorites() async {
    final starred = (await _get('getStarred2'))['starred2'] as Map<String, dynamic>? ?? const {};

    List<Map<String, dynamic>> latestFirst(String key) {
      DateTime when(Map<String, dynamic> json) =>
          DateTime.tryParse(json['starred'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

      return [for (final json in starred[key] as List? ?? const []) json as Map<String, dynamic>]
        ..sort((a, b) => when(b).compareTo(when(a)));
    }

    return (
      artists: [for (final json in latestFirst('artist')) _artist(json)],
      albums: [for (final json in latestFirst('album')) _album(json)],
      songs: [for (final json in latestFirst('song')) _song(json)],
    );
  }

  /// star and unstar, which name an album and an artist by their own parameters.
  @override
  Future<void> setFavorite(FavoriteKind kind, String id, {required bool favorite}) =>
      _get(favorite ? 'star' : 'unstar', {
        switch (kind) {
          FavoriteKind.song => 'id',
          FavoriteKind.album => 'albumId',
          FavoriteKind.artist => 'artistId',
        }: id,
      });

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

    for (final album in await _mostPlayedAlbumItems()) {
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
    final json = await _artistJson(id);
    final albums = json['album'] as List? ?? const [];

    return (_artist(json), [for (final album in albums) _album(album as Map<String, dynamic>)]);
  }

  /// getArtistInfo2's biography: Navidrome's comes from its agents (Last.fm's, where it's on), as HTML.
  @override
  Future<Biography?> biography(String artistId) async =>
      Biography.fromHtml((await _artistInfo(artistId))['biography'] as String?);

  /// getArtistInfo2's similar artists, as many as it gives by default (20): Navidrome learns them from its agents
  /// (Last.fm's, where it's on) and gives those in the library.
  @override
  Future<List<Artist>> similarArtists(String artistId) async => [
    for (final artist in (await _artistInfo(artistId))['similarArtist'] as List? ?? const [])
      _artist(artist as Map<String, dynamic>),
  ];

  /// getSimilarSongs2 by the song's id, for which Navidrome mixes songs like it (from its agents: Last.fm's, or a
  /// plugin's), else its artist's ([radioSongs]).
  @override
  Future<List<Song>> similarSongs(Song song, {int size = 50}) =>
      radioSongs(song.id, artistId: song.artistId, size: size);

  /// getSimilarSongs2, which Navidrome takes a song's, an album's or an artist's id for (from 0.64 at least), mixing
  /// songs from its agents (Last.fm's, a plugin's) and topping them up with the item's own. The Subsonic API takes only
  /// an artist's id there: a server that refuses the item's is asked by [artistId], for songs of the artist and of those
  /// like them.
  @override
  Future<List<Song>> radioSongs(String id, {String? artistId, int size = 50}) async {
    Future<List<Song>> like(String id) async {
      final body = await _get('getSimilarSongs2', {'id': id, 'count': '$size'});

      return [
        for (final json in (body['similarSongs2'] as Map<String, dynamic>?)?['song'] as List? ?? const [])
          _song(json as Map<String, dynamic>),
      ];
    }

    try {
      return await like(id);
    } on ServerError catch (error) {
      if (error.isAuth || artistId == null || artistId == id) {
        rethrow;
      }

      return like(artistId);
    }
  }

  /// The artist whose id is [id] and their albums, as getArtist gives them. The artist page asks for the artist and for
  /// their most played songs at once, which both start here: a request under way answers both ([_shared]).
  Future<Map<String, dynamic>> _artistJson(String id) =>
      _shared('getArtist', id).then((body) => body['artist'] as Map<String, dynamic>);

  /// What getArtistInfo2 knows of the artist whose id is [id]. The artist page asks for their biography and the artists
  /// like them at once, which both start here: a request under way answers both ([_shared]).
  Future<Map<String, dynamic>> _artistInfo(String id) =>
      _shared('getArtistInfo2', id).then((body) => body['artistInfo2'] as Map<String, dynamic>? ?? const {});

  /// What [endpoint] answers for the id [id], asked once for all that ask while a request is under way. One that has
  /// answered isn't kept: what it says may have changed since (an artist's plays).
  Future<Map<String, dynamic>> _shared(String endpoint, String id) =>
      _sharedRequests[(endpoint, id)] ??= _get(endpoint, {'id': id}).whenComplete(() {
        // In braces: whenComplete waits for what this returns, and remove returns the request itself.
        _sharedRequests.remove((endpoint, id));
      });

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
      await _has('transcodeOffset')
      ? _url('stream', {'id': songId, 'maxBitRate': '$maxBitRate', 'timeOffset': '${from.inSeconds}'})
      : null;

  /// Whether the server has the OpenSubsonic extension named [name]: their names asked once, unless they couldn't be (no
  /// network), and then asked again the next time.
  Future<bool> _has(String name) async => (await (_extensionNames ??= _extensions().catchError((Object e) {
    // A server that answers with an error has no OpenSubsonic extensions; one that doesn't answer may.
    if (e is! ServerError) {
      _extensionNames = null;
    }

    return const <String>{};
  }))).contains(name);

  /// The names of the OpenSubsonic extensions the server has (getOpenSubsonicExtensions).
  Future<Set<String>> _extensions() async {
    final extensions = (await _get('getOpenSubsonicExtensions'))['openSubsonicExtensions'] as List? ?? const [];

    return {for (final extension in extensions) (extension as Map<String, dynamic>)['name'] as String};
  }

  /// A scrobble's submission, which counts the play. What plays shows in the server's now playing
  /// through the hub instead, which counts nothing (SPEC.md, section 12).
  @override
  Future<void> scrobble(String songId, {required DateTime time}) =>
      _get('scrobble', {'id': songId, 'submission': 'true', 'time': '${time.millisecondsSinceEpoch}'});

  /// As [scrobble]: the server counts it at [time], however long ago.
  @override
  Future<void> scrobbleMissed(String songId, {required DateTime time}) => scrobble(songId, time: time);

  /// The stream, which comes whole, transcoded or not.
  @override
  Uri downloadUrl(String songId, {int? maxBitRate}) => streamUrl(songId, maxBitRate: maxBitRate);

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

  /// The URL of [endpoint], with [params]: each a string, or a list of them for a parameter given once for each (a
  /// playlist's songs). The ids in them go as the server has them now ([currentId]): one the app kept from before its
  /// server gave its items new ones (the downloads', a play held, the home's, the last playback the hub kept) finds its
  /// item all the same.
  Uri _url(String endpoint, [Map<String, Object> params = const {}]) => server
      .resolve('rest/$endpoint.view')
      .replace(
        queryParameters: {
          ...switch (credentials) {
            SubsonicToken(:final username, :final token, :final salt) => {'u': username, 't': token, 's': salt},
            // The key alone: with the user's name too, the server refuses (OpenSubsonic's error 43).
            SubsonicApiKey(:final apiKey) => {'apiKey': apiKey},
          },
          'v': '1.16.1',
          'c': clientName,
          'f': 'json',
          for (final MapEntry(key: name, value: value) in params.entries)
            name: _idParameters.contains(name) ? _currentIds(value, cover: endpoint == 'getCoverArt') : value,
        },
      );

  /// The parameters that name items by their ids: a song's, an album's, an artist's or a playlist's, and getCoverArt's
  /// `id` a cover's.
  static const _idParameters = {'id', 'albumId', 'artistId', 'playlistId', 'songId', 'songIdToAdd'};

  /// [ids], an id or a list of them, as the server has them now.
  Object _currentIds(Object ids, {required bool cover}) => switch (ids) {
    final String id => currentId(id, cover: cover),
    final List<String> list => [for (final id in list) currentId(id, cover: cover)],
    _ => ids,
  };

  Future<Map<String, dynamic>> _get(String endpoint, [Map<String, Object> params = const {}]) async =>
      _decode(await _http.get(_url(endpoint, params)));

  /// [endpoint] with [params], whose lists can be long (a playlist's songs): in a form's body where the server takes one
  /// (OpenSubsonic's formPost, which Navidrome has), rather than in the URL, which a server or a proxy may cut short.
  Future<Map<String, dynamic>> _post(String endpoint, Map<String, Object> params) async {
    if (!await _has('formPost')) {
      return _get(endpoint, params);
    }

    final response = await _http.post(
      server.resolve('rest/$endpoint.view'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: _url(endpoint, params).query,
    );

    return _decode(response);
  }

  /// Which server an answer ([body]) is from, as it says: its name and version, where OpenSubsonic's tell them, and the
  /// API's (`navidrome 0.58.0 (13af8ed4), API 1.16.1, OpenSubsonic`).
  static String _kindOf(Map<String, dynamic> body) {
    final name = body['type'] as String? ?? 'a Subsonic server';
    final version = body['serverVersion'] as String?;

    return [
      if (version == null) name else '$name $version',
      if (body['version'] case final String api) 'API $api',
      if (body['openSubsonic'] == true) 'OpenSubsonic',
    ].join(', ');
  }

  /// The errors that refuse the credentials: a wrong user or password (40), a server that takes no token of a password
  /// (41), or not what the app sent at all (42), only an API key, say; a wrong API key (44).
  static const _authCodes = {40, 41, 42, 44};

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode != 200) {
      throw ServerError('${server.host}: HTTP ${response.statusCode}');
    }

    final body =
        (jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>)['subsonic-response']
            as Map<String, dynamic>;
    // Every answer says it, a refusal's too.
    _canonicalIds = hasCanonicalIds(type: body['type'] as String?, version: body['serverVersion'] as String?);

    final kind = _kindOf(body);

    // In the log once, as the first answer says it, for whoever reads it to know which server the app spoke to.
    if (kind != _kind) {
      _kind = kind;
      _log.info('${server.host}: $kind');
    }

    if (body['status'] != 'ok') {
      final error = body['error'] as Map<String, dynamic>?;
      final code = (error?['code'] as num?)?.toInt();

      throw ServerError(
        error?['message'] as String? ?? 'request failed',
        isAuth: _authCodes.contains(code),
        code: code,
      );
    }

    return body;
  }

  @override
  void close() => _http.close();
}

/// An album's record labels, release date, MusicBrainz id and discs' titles are OpenSubsonic's, which a plain Subsonic
/// server doesn't give. The release date is that of the album's edition, else the original one. Navidrome fills them from the tags
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
  genres: [for (final name in _albumGenres(json)) Genre(id: name, name: name)],
  discTitles: {
    for (final disc in json['discTitles'] as List? ?? const [])
      if (disc case {'disc': final num number, 'title': final String title} when title.isNotEmpty)
        number.toInt(): title,
  },
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

/// A song's MusicBrainz id, credits and ReplayGain are OpenSubsonic's: in Navidrome, its recording's id, its contributors
/// (a composer, a performer with their instrument, a producer) and its gains, from the file's tags.
Song _song(Map<String, dynamic> json) => Song(
  id: json['id'] as String,
  title: json['title'] as String? ?? '',
  artist: json['artist'] as String?,
  album: json['album'] as String?,
  coverArt: json['coverArt'] as String?,
  duration: json['duration'] == null ? null : Duration(seconds: (json['duration'] as num).toInt()),
  albumId: json['albumId'] as String?,
  artists: _songArtists(json),
  musicBrainzId: switch (json['musicBrainzId']) {
    final String id when id.isNotEmpty => id,
    _ => null,
  },
  credits: [
    for (final contributor in json['contributors'] as List? ?? const [])
      if (contributor case {'role': final String name, 'artist': final Map<String, dynamic> artist})
        if (CreditRole.named(name) case final role?)
          Credit(
            artist['name'] as String? ?? '',
            role,
            // The performer's instrument.
            part: switch (contributor['subRole']) {
              final String part when part.isNotEmpty => part,
              _ => null,
            },
            artistId: artist['id'] as String?,
            musicBrainzId: switch (artist['musicBrainzId']) {
              final String id when id.isNotEmpty => id,
              _ => null,
            },
          ),
  ],
  replayGain: _replayGain(json['replayGain']),
  track: (json['track'] as num?)?.toInt(),
  disc: (json['discNumber'] as num?)?.toInt(),
);

/// OpenSubsonic's replayGain, whose values are there only where the server knows them; null where it has no gain.
ReplayGain? _replayGain(Object? json) {
  if (json is! Map<String, dynamic>) {
    return null;
  }

  double? value(String key) => switch (json[key]) {
    final num value => value.toDouble(),
    _ => null,
  };

  final (trackGain, albumGain) = (value('trackGain'), value('albumGain'));

  return trackGain == null && albumGain == null
      ? null
      : ReplayGain(
          trackGain: trackGain,
          albumGain: albumGain,
          trackPeak: value('trackPeak'),
          albumPeak: value('albumPeak'),
        );
}

/// A song's artists: OpenSubsonic's artists, all of them, or else Subsonic's one, artistId, whom its artist names.
List<Artist> _songArtists(Map<String, dynamic> json) => switch (json['artists']) {
  final List<Object?> artists when artists.isNotEmpty => [
    for (final artist in artists) _artist(artist as Map<String, dynamic>),
  ],
  _ => [if (json['artistId'] case final String id) Artist(id: id, name: json['artist'] as String? ?? '')],
};

/// A playlist the user, [username], can change where OpenSubsonic doesn't say it's read-only (Navidrome says so of
/// another user's and of a smart playlist), or else where it is theirs.
Playlist _playlist(Map<String, dynamic> json, String username) => Playlist(
  id: json['id'] as String,
  name: json['name'] as String? ?? '',
  coverArt: json['coverArt'] as String?,
  songCount: (json['songCount'] as num?)?.toInt(),
  editable: switch (json['readonly']) {
    final bool readOnly => !readOnly,
    _ => json['owner'] == null || json['owner'] == username,
  },
);

Genre _genre(Map<String, dynamic> json) => Genre(
  id: json['value'] as String,
  name: json['value'] as String,
  albumCount: (json['albumCount'] as num?)?.toInt(),
);

/// An artist's MusicBrainz id is OpenSubsonic's.
Artist _artist(Map<String, dynamic> json) => Artist(
  id: json['id'] as String,
  name: json['name'] as String? ?? '',
  coverArt: json['coverArt'] as String?,
  albumCount: (json['albumCount'] as num?)?.toInt(),
  musicBrainzId: switch (json['musicBrainzId']) {
    final String id when id.isNotEmpty => id,
    _ => null,
  },
);
