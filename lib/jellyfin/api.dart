import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../segue/protocol.dart';
import '../server/models.dart';
import '../server/server.dart';

/// A Jellyfin sign-in: the access token the server gave this device for the user. The password
/// isn't kept.
class JellyfinCredentials implements Credentials {
  const JellyfinCredentials({required this.username, required this.userId, required this.token});

  @override
  final String username;
  final String userId;
  final String token;
}

/// The parts of the Jellyfin API the app uses. Jellyfin keeps a sign-in per device, so requests say
/// which device they come from.
class JellyfinApi implements MediaServer {
  JellyfinApi(Uri server, this.credentials, {required this.deviceId, required this.deviceName, http.Client? client})
    : server = _withSlash(server),
      _http = client ?? http.Client();

  /// Signs in as [username] with [password] (Users/AuthenticateByName), as this device.
  static Future<JellyfinApi> signIn(
    Uri server,
    String username,
    String password, {
    required String deviceId,
    required String deviceName,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final response = await httpClient.post(
        _withSlash(server).resolve('Users/AuthenticateByName'),
        headers: {'Authorization': _authorization(deviceId, deviceName), 'Content-Type': 'application/json'},
        body: jsonEncode({'Username': username, 'Pw': password}),
      );
      final json = _decode(server, response) as Map<String, dynamic>;
      final user = json['User'] as Map<String, dynamic>;
      return JellyfinApi(
        server,
        JellyfinCredentials(
          username: user['Name'] as String,
          userId: user['Id'] as String,
          token: json['AccessToken'] as String,
        ),
        deviceId: deviceId,
        deviceName: deviceName,
        client: httpClient,
      );
    } on Object {
      if (client == null) {
        httpClient.close();
      }

      rethrow;
    }
  }

  final Uri server;
  @override
  final JellyfinCredentials credentials;
  final String deviceId;
  final String deviceName;
  final http.Client _http;

  @override
  Api get api => Api.jellyfin;

  @override
  Auth get auth => Auth.jellyfin(token: credentials.token);

  @override
  Future<List<Album>> albums({required AlbumOrder order, int size = 100, int offset = 0}) async {
    final sort = switch (order) {
      AlbumOrder.latest => {'SortBy': 'DateCreated,SortName', 'SortOrder': 'Descending'},
      AlbumOrder.name => {'SortBy': 'SortName', 'SortOrder': 'Ascending'},
      // The year first: an album may have one without a full date.
      AlbumOrder.released => {'SortBy': 'ProductionYear,PremiereDate,SortName', 'SortOrder': 'Descending'},
      // Not one of Jellyfin's: see [_mostPlayedAlbums].
      AlbumOrder.mostPlayed => null,
    };

    if (sort == null) {
      return _mostPlayedAlbums(size: size, offset: offset);
    }

    return [
      for (final json in await _items({
        'IncludeItemTypes': 'MusicAlbum',
        ...sort,
        'Limit': '$size',
        'StartIndex': '$offset',
      }))
        _album(json),
    ];
  }

  @override
  Future<List<Album>> mostPlayedAlbums({int size = 20, String? genre}) => _mostPlayedAlbums(size: size, genre: genre);

  /// Jellyfin counts plays only by song: an album's are those of its songs, added up, among the user's
  /// most played songs (a genre's: of that genre). A tie goes to the album with the more played song. A
  /// page past the first ranks them all again, and takes its part.
  Future<List<Album>> _mostPlayedAlbums({required int size, int offset = 0, String? genre}) async {
    final plays = <String, int>{};

    for (final song in await _mostPlayedSongs({'GenreIds': ?genre})) {
      final album = song['AlbumId'] as String?;

      if (album != null) {
        plays[album] = (plays[album] ?? 0) + _playCount(song);
      }
    }

    final ids = rankedByCount(plays).skip(offset).take(size).toList();

    if (ids.isEmpty) {
      return const [];
    }

    // Asked by id, they come in whatever order.
    final albums = {
      for (final json in await _items({'Ids': ids.join(',')})) json['Id'] as String: _album(json),
    };
    return [for (final id in ids) ?albums[id]];
  }

  /// A genre's plays are those of its songs, added up, among the user's most played songs, as an
  /// album's are.
  @override
  Future<List<Genre>> mostPlayedGenres({int size = 10}) async {
    final plays = <String, int>{};
    final names = <String, String>{};

    for (final song in await _mostPlayedSongs({'Fields': 'Genres'})) {
      for (final genre in song['GenreItems'] as List? ?? const []) {
        if (genre case {'Id': final String id, 'Name': final String name}) {
          plays[id] = (plays[id] ?? 0) + _playCount(song);
          names[id] = name;
        }
      }
    }

    return [for (final id in rankedByCount(plays).take(size)) Genre(id: id, name: names[id]!)];
  }

  /// The user's most played songs that have the artist among their artists or as their album artist
  /// (ArtistIds), also on another artist's album.
  @override
  Future<List<Song>> mostPlayedSongs(String artistId, {int size = 10}) async => [
    for (final json in await _mostPlayedSongs({'ArtistIds': artistId, 'Limit': '$size'})) _song(json),
  ];

  /// Jellyfin knows no one's plays but its users'.
  @override
  Future<List<Song>> popularSongs(Artist artist, {int size = 10}) async => const [];

  /// Every music genre, with how many albums it has. MusicGenres, which Jellyfin keeps next to Genres:
  /// that one lists the music genres only under a music library's id.
  @override
  Future<List<Genre>> genres() async => [
    for (final json in await _list('MusicGenres', {'Fields': 'ItemCounts'})) _genre(json),
  ];

  @override
  Future<List<Album>> genreAlbums(String id, {int size = 100, int offset = 0}) async => [
    for (final json in await _items({
      'IncludeItemTypes': 'MusicAlbum',
      'GenreIds': id,
      'SortBy': 'SortName',
      'SortOrder': 'Ascending',
      'Limit': '$size',
      'StartIndex': '$offset',
    }))
      _album(json),
  ];

  /// An album and its songs. Jellyfin has no record labels: an album's studios stand for them, where someone set them
  /// (it reads no label from the tags of songs, only of audiobooks). It gives them, and the album's MusicBrainz id
  /// among its other ids (ProviderIds), only when asked (Fields).
  @override
  Future<(Album, List<Song>)> album(String id) async {
    // Future.wait throws the first failure as it came, where a record's wait would wrap it.
    final [albums, songs] = await Future.wait([
      _items({'Ids': id, 'Fields': 'Studios,ProviderIds'}),
      _items({'ParentId': id, 'IncludeItemTypes': 'Audio', 'SortBy': 'ParentIndexNumber,IndexNumber,SortName'}),
    ]);
    return (_album(_only(albums, id)), [for (final json in songs) _song(json)]);
  }

  @override
  Future<Song> song(String id) async => _song(_only(await _items({'Ids': id}), id));

  /// Jellyfin's lyrics of a song (Audio/{id}/Lyrics), from the file's tags or a .lrc next to it: a 404
  /// when it has none. Their starts are in ticks, of 100 ns.
  @override
  Future<Lyrics?> lyrics(String songId) async {
    final response = await _http.get(_url('Audio/${Uri.encodeComponent(songId)}/Lyrics'), headers: _headers);

    if (response.statusCode == 404) {
      return null;
    }

    final json = _decode(server, response) as Map<String, dynamic>;
    final synced = (json['Metadata'] as Map<String, dynamic>?)?['IsSynced'] != false;
    final lines = [
      for (final line in json['Lyrics'] as List? ?? const [])
        if (line case {'Text': final String text})
          LyricLine(
            text,
            start: synced && line['Start'] is num ? Duration(microseconds: (line['Start'] as num).toInt() ~/ 10) : null,
          ),
    ];
    return lines.isEmpty ? null : Lyrics(lines, provider: 'Jellyfin');
  }

  @override
  Future<SearchResults> search(String query, {int artists = 5, int albums = 10, int songs = 50}) async {
    final [foundArtists, foundAlbums, foundSongs] = await Future.wait([
      _albumArtists({'searchTerm': query, 'Limit': '$artists'}),
      _items({'searchTerm': query, 'IncludeItemTypes': 'MusicAlbum', 'Limit': '$albums'}),
      _items({'searchTerm': query, 'IncludeItemTypes': 'Audio', 'Limit': '$songs'}),
    ]);
    return (
      artists: [for (final json in foundArtists) _artist(json)],
      albums: [for (final json in foundAlbums) _album(json)],
      songs: [for (final json in foundSongs) _song(json)],
    );
  }

  /// Every album artist, by name, as Subsonic's getArtists lists them, with their MusicBrainz ids, which a band's
  /// biography finds its members in the library by (ProviderIds, which come only when asked for).
  @override
  Future<List<Artist>> artists() async => [
    for (final json in await _albumArtists({'SortBy': 'SortName', 'Fields': 'ProviderIds'})) _artist(json),
  ];

  /// An artist's plays are those of the songs they are an album artist of, added up, among the user's most played
  /// songs, as an album's are. One [artists] doesn't list is left out, as it is of the artists tab.
  @override
  Future<List<Artist>> mostPlayedArtists({int size = 100}) async {
    final plays = <String, int>{};

    for (final song in await _mostPlayedSongs({})) {
      for (final artist in song['AlbumArtists'] as List? ?? const []) {
        if (artist case {'Id': final String id}) {
          plays[id] = (plays[id] ?? 0) + _playCount(song);
        }
      }
    }

    if (plays.isEmpty) {
      return const [];
    }

    final artists = {for (final artist in await this.artists()) artist.id: artist};
    return [for (final id in rankedByCount(plays)) ?artists[id]].take(size).toList();
  }

  /// An artist and the albums they are the album artist of. Their MusicBrainz id, among their other ids (ProviderIds),
  /// comes only when asked for (Fields).
  @override
  Future<(Artist, List<Album>)> artist(String id) async {
    final [artists, albums] = await Future.wait([
      _items({'Ids': id, 'Fields': 'ProviderIds'}),
      _items({'AlbumArtistIds': id, 'IncludeItemTypes': 'MusicAlbum', 'SortBy': 'ProductionYear,SortName'}),
    ]);
    final found = _artist(_only(artists, id));
    return (
      Artist(
        id: found.id,
        name: found.name,
        coverArt: found.coverArt,
        albumCount: albums.length,
        musicBrainzId: found.musicBrainzId,
      ),
      [for (final json in albums) _album(json)],
    );
  }

  /// Its Overview, which only comes when asked for (Fields).
  @override
  Future<Biography?> biography(String artistId) async {
    final artist = _only(await _items({'Ids': artistId, 'Fields': 'Overview'}), artistId);
    return Biography.fromHtml(artist['Overview'] as String?);
  }

  /// Artists/{id}/Similar, which Jellyfin finds by what their metadata shares (genres, tags), but the artist
  /// themselves, should it count them.
  @override
  Future<List<Artist>> similarArtists(String artistId) async => [
    for (final json in await _list('Artists/${Uri.encodeComponent(artistId)}/Similar', {'Limit': '20'}))
      if (json['Id'] != artistId) _artist(json),
  ];

  /// The file as it is (static), with the token in the URL: the player can't send headers. With [maxBitRate],
  /// Audio/{id}/universal, which sends the file as it is where its bitrate is within it, and otherwise transcodes it into
  /// AAC over HLS, which the player can seek in, unlike a stream transcoded as it goes.
  @override
  Uri streamUrl(String songId, {int? maxBitRate}) => maxBitRate == null
      ? _url('Audio/$songId/stream', {'static': 'true', 'ApiKey': credentials.token})
      : _url('Audio/$songId/universal', {
          'MaxStreamingBitrate': '${maxBitRate * 1000}',
          // What the player plays as it is: any of these, within the bitrate.
          'Container': 'opus,webm|opus,ogg,mp3,aac,m4a|aac,m4a|alac,m4b|aac,flac,webma,webm|webma,wav',
          'TranscodingContainer': 'ts',
          'TranscodingProtocol': 'hls',
          'AudioCodec': 'aac',
          'UserId': credentials.userId,
          'DeviceId': deviceId,
          'ApiKey': credentials.token,
        });

  /// Never: a transcoded song comes as HLS, which can seek.
  @override
  Future<Uri?> transcodedStreamUrl(String songId, {required int maxBitRate, required Duration from}) async => null;

  /// Nothing: Jellyfin counts a play as a playback starts (Sessions/Playing), which the hub reports for
  /// the device (SPEC.md, section 12), and counting it here too would count it twice.
  @override
  Future<void> scrobble(String songId, {required DateTime time}) async {}

  /// Jellyfin serves images without a sign-in.
  @override
  Uri coverArtUrl(String id, {int size = 300}) =>
      _url('Items/$id/Images/Primary', {'maxWidth': '$size', 'maxHeight': '$size', 'quality': '90'});

  @override
  Future<Uint8List> coverArt(String id, {int size = 300}) async {
    final response = await _http.get(coverArtUrl(id, size: size));

    if (response.statusCode != 200 || !(response.headers['content-type'] ?? '').startsWith('image/')) {
      throw ServerError('no cover for $id (HTTP ${response.statusCode})');
    }

    return response.bodyBytes;
  }

  /// Ends this device's sign-in (Sessions/Logout), so that its token stops working.
  @override
  Future<void> signOut() async {
    try {
      await _http.post(_url('Sessions/Logout'), headers: _headers).timeout(const Duration(seconds: 5));
    } on Object {
      // offline, or the server forgot the sign-in already
    }
  }

  @override
  void close() => _http.close();

  Map<String, String> get _headers => {'Authorization': _authorization(deviceId, deviceName, credentials.token)};

  /// The user's items, at any depth, that match [query]; or by their ids (Ids), which every version
  /// takes, unlike Items/{id}.
  Future<List<Map<String, dynamic>>> _items(Map<String, String> query) =>
      _list('Items', {'Recursive': 'true', ...query});

  /// The user's most played songs, the most played first, that match [query]; as many as 1000 where it
  /// gives no Limit. Songs are where Jellyfin keeps the plays.
  Future<List<Map<String, dynamic>>> _mostPlayedSongs(Map<String, String> query) => _items({
    'IncludeItemTypes': 'Audio',
    'Filters': 'IsPlayed',
    'SortBy': 'PlayCount',
    'SortOrder': 'Descending',
    'Limit': '1000',
    ...query,
  });

  /// Artists come from their own endpoint: Jellyfin's Items doesn't list them.
  Future<List<Map<String, dynamic>>> _albumArtists(Map<String, String> query) => _list('Artists/AlbumArtists', query);

  Future<List<Map<String, dynamic>>> _list(String path, Map<String, String> query) async {
    final json = await _get(path, {'userId': credentials.userId, ...query});
    return [for (final item in (json as Map<String, dynamic>)['Items'] as List? ?? const []) item];
  }

  static Map<String, dynamic> _only(List<Map<String, dynamic>> items, String id) =>
      items.isEmpty ? throw ServerError('no item $id') : items.first;

  Future<Object?> _get(String path, Map<String, String> query) async =>
      _decode(server, await _http.get(_url(path, query), headers: _headers));

  Uri _url(String path, [Map<String, String>? query]) => server.resolve(path).replace(queryParameters: query);

  static Object? _decode(Uri server, http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ServerError('the server refused the sign-in', isAuth: true);
    }

    if (response.statusCode != 200) {
      throw ServerError('${server.host}: HTTP ${response.statusCode}');
    }

    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Uri _withSlash(Uri server) => server.path.endsWith('/') ? server : server.replace(path: '${server.path}/');

  /// The header that tells Jellyfin which app and device a request comes from, and with which sign-in.
  /// The values are URL-encoded, as Jellyfin's own clients do.
  static String _authorization(String deviceId, String deviceName, [String? token]) {
    final fields = {
      'Client': clientName,
      'Device': deviceName,
      'DeviceId': deviceId,
      'Version': appVersion,
      'Token': ?token,
    };
    final pairs = [for (final MapEntry(:key, :value) in fields.entries) '$key="${Uri.encodeComponent(value)}"'];
    return 'MediaBrowser ${pairs.join(', ')}';
  }
}

String? _primaryImage(Map<String, dynamic> json) =>
    (json['ImageTags'] as Map<String, dynamic>?)?['Primary'] == null ? null : json['Id'] as String;

String? _joined(Object? names) => names is List && names.isNotEmpty ? names.join(', ') : null;

/// The id of the first of a list of names with ids, as ArtistItems and AlbumArtists are.
String? _firstId(Object? items) =>
    items is List && items.isNotEmpty ? (items.first as Map<String, dynamic>)['Id'] as String? : null;

/// The artists of a list of names with ids, as ArtistItems and AlbumArtists are.
List<Artist> _namesWithIds(Object? items) => [
  for (final item in items as List? ?? const [])
    if ((item as Map<String, dynamic>)['Id'] case final String id) Artist(id: id, name: item['Name'] as String? ?? ''),
];

/// How many times the user played an item.
int _playCount(Map<String, dynamic> json) =>
    ((json['UserData'] as Map<String, dynamic>?)?['PlayCount'] as num?)?.toInt() ?? 0;

Duration? _duration(Map<String, dynamic> json) {
  final ticks = json['RunTimeTicks'] as num?; // 10 million to the second
  return ticks == null ? null : Duration(microseconds: ticks.toInt() ~/ 10);
}

/// When an album came out, by its PremiereDate, a day. The first of January stands for its year only: that's the date
/// Jellyfin gives music whose tags have only a year.
ReleaseDate? _releaseDate(String? premiere) {
  final date = premiere == null ? null : DateTime.tryParse(premiere);

  if (date == null) {
    return null;
  }

  return date.month == 1 && date.day == 1
      ? ReleaseDate(date.year)
      : ReleaseDate(date.year, month: date.month, day: date.day);
}

/// An album's artist is its album artist, or its artists when it has none, as is its artist id.
Album _album(Map<String, dynamic> json) => Album(
  id: json['Id'] as String,
  name: json['Name'] as String? ?? '',
  artist: json['AlbumArtist'] as String? ?? _joined(json['Artists']),
  coverArt: _primaryImage(json),
  year: (json['ProductionYear'] as num?)?.toInt(),
  songCount: (json['ChildCount'] as num?)?.toInt(),
  artistId: _firstId(json['AlbumArtists']) ?? _firstId(json['ArtistItems']),
  releaseDate: _releaseDate(json['PremiereDate'] as String?),
  recordLabels: [
    for (final studio in json['Studios'] as List? ?? const [])
      if ((studio as Map<String, dynamic>)['Name'] case final String name) name,
  ],
  musicBrainzId: switch ((json['ProviderIds'] as Map<String, dynamic>?)?['MusicBrainzAlbum']) {
    final String id when id.isNotEmpty => id,
    _ => null,
  },
);

/// A song's cover is its own image or else its album's, as Jellyfin's apps show it. Its artists are
/// the album's when it has none of its own, both in its artist's name and in its list of artists.
Song _song(Map<String, dynamic> json) => Song(
  id: json['Id'] as String,
  title: json['Name'] as String? ?? '',
  artist: _joined(json['Artists']) ?? json['AlbumArtist'] as String?,
  album: json['Album'] as String?,
  coverArt: _primaryImage(json) ?? (json['AlbumPrimaryImageTag'] == null ? null : json['AlbumId'] as String?),
  duration: _duration(json),
  albumId: json['AlbumId'] as String?,
  artists: switch (_namesWithIds(json['ArtistItems'])) {
    [] => _namesWithIds(json['AlbumArtists']),
    final artists => artists,
  },
);

Artist _artist(Map<String, dynamic> json) => Artist(
  id: json['Id'] as String,
  name: json['Name'] as String? ?? '',
  coverArt: _primaryImage(json),
  albumCount: (json['AlbumCount'] as num?)?.toInt(),
  musicBrainzId: switch ((json['ProviderIds'] as Map<String, dynamic>?)?['MusicBrainzArtist']) {
    final String id when id.isNotEmpty => id,
    _ => null,
  },
);

Genre _genre(Map<String, dynamic> json) => Genre(
  id: json['Id'] as String,
  name: json['Name'] as String? ?? '',
  albumCount: (json['AlbumCount'] as num?)?.toInt(),
);
