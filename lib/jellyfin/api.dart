import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../segue/protocol.dart';
import '../server/models.dart';
import '../server/server.dart';

final _log = Logger('JellyfinApi');

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
      return _signedIn(server, _decode(server, response), deviceId, deviceName, httpClient);
    } on Object {
      if (client == null) {
        httpClient.close();
      }

      rethrow;
    }
  }

  /// Starts signing this device in by Quick Connect, Jellyfin's own way of signing a device in from one signed in
  /// already: the code the user authorizes there ([authorizeQuickConnect]), and the secret that this device signs in
  /// with once they have ([quickConnectAuthorized], [signInWithQuickConnect]). Refused where the server has Quick
  /// Connect off ([ServerError.isAuth]); Navidrome's Jellyfin API has none ([ServerError]).
  static Future<({String code, String secret})> initiateQuickConnect(
    Uri server, {
    required String deviceId,
    required String deviceName,
    http.Client? client,
  }) => _withClient(client, (httpClient) async {
    final url = _withSlash(server).resolve('QuickConnect/Initiate');
    final headers = {'Authorization': _authorization(deviceId, deviceName)};
    var response = await httpClient.post(url, headers: headers);

    // Jellyfin 10.8 starts it with a GET.
    if (response.statusCode == 404 || response.statusCode == 405) {
      response = await httpClient.get(url, headers: headers);
    }

    final json = _decode(server, response) as Map<String, dynamic>;

    return (code: '${json['Code']}', secret: json['Secret'] as String);
  });

  /// Whether the user has authorized the Quick Connect of [secret] ([initiateQuickConnect]).
  static Future<bool> quickConnectAuthorized(
    Uri server,
    String secret, {
    required String deviceId,
    required String deviceName,
    http.Client? client,
  }) => _withClient(client, (httpClient) async {
    final response = await httpClient.get(
      _withSlash(server).resolve('QuickConnect/Connect').replace(queryParameters: {'secret': secret}),
      headers: {'Authorization': _authorization(deviceId, deviceName)},
    );

    return (_decode(server, response) as Map<String, dynamic>)['Authenticated'] == true;
  });

  /// Signs this device in by the Quick Connect of [secret], once authorized ([quickConnectAuthorized]): a sign-in of its
  /// own, as by its password.
  static Future<JellyfinApi> signInWithQuickConnect(
    Uri server,
    String secret, {
    required String deviceId,
    required String deviceName,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final response = await httpClient.post(
        _withSlash(server).resolve('Users/AuthenticateWithQuickConnect'),
        headers: {'Authorization': _authorization(deviceId, deviceName), 'Content-Type': 'application/json'},
        body: jsonEncode({'Secret': secret}),
      );

      return _signedIn(server, _decode(server, response), deviceId, deviceName, httpClient);
    } on Object {
      if (client == null) {
        httpClient.close();
      }

      rethrow;
    }
  }

  /// Authorizes, as this sign-in's user, another device's Quick Connect by its [code] ([initiateQuickConnect]).
  Future<void> authorizeQuickConnect(String code) async {
    final response = await _http.post(
      _withSlash(server)
          .resolve('QuickConnect/Authorize')
          .replace(queryParameters: {'code': code, 'userId': credentials.userId}),
      headers: _headers,
    );

    _decode(server, response);
  }

  /// [run] with [client], or with one of its own, closed after.
  static Future<T> _withClient<T>(http.Client? client, Future<T> Function(http.Client client) run) async {
    final httpClient = client ?? http.Client();

    try {
      return await run(httpClient);
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// The API of a sign-in's answer, [json]: the user, and their token.
  static JellyfinApi _signedIn(Uri server, Object? json, String deviceId, String deviceName, http.Client client) {
    final answer = json as Map<String, dynamic>;
    final user = answer['User'] as Map<String, dynamic>;

    return JellyfinApi(
      server,
      JellyfinCredentials(
        username: user['Name'] as String,
        userId: user['Id'] as String,
        token: answer['AccessToken'] as String,
      ),
      deviceId: deviceId,
      deviceName: deviceName,
      client: client,
    );
  }

  final Uri server;
  @override
  final JellyfinCredentials credentials;
  final String deviceId;
  final String deviceName;
  final http.Client _http;

  // The request under way for the user's most played songs with their genres ([_mostPlayedSongsWithGenres]).
  Future<List<Map<String, dynamic>>>? _mostPlayedRequest;

  // Which server it is, as the log last had it ([ping]).
  String? _kind;

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
      // Not Jellyfin's, which keeps plays by song alone: see [_mostPlayedAlbums] and [_recentlyPlayedAlbums].
      AlbumOrder.mostPlayed || AlbumOrder.recentlyPlayed => null,
    };

    if (sort == null) {
      return order == AlbumOrder.mostPlayed
          ? _mostPlayedAlbums(size: size, offset: offset)
          : _recentlyPlayedAlbums(size: size, offset: offset);
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

    return _albumsByIds(rankedByCount(plays).skip(offset).take(size).toList());
  }

  /// Jellyfin keeps when a song last played (DatePlayed), not an album: the albums of the user's songs played last, in
  /// that order, each once. A page past the first goes through them again, and takes its part.
  Future<List<Album>> _recentlyPlayedAlbums({required int size, int offset = 0}) async {
    final ids = <String>{};

    for (final song in await _items({
      'IncludeItemTypes': 'Audio',
      'Filters': 'IsPlayed',
      'SortBy': 'DatePlayed',
      'SortOrder': 'Descending',
      'Limit': '1000',
    })) {
      if (song['AlbumId'] case final String album) {
        ids.add(album);
      }
    }

    return _albumsByIds(ids.skip(offset).take(size).toList());
  }

  /// The albums whose ids are [ids], in that order.
  Future<List<Album>> _albumsByIds(List<String> ids) async {
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

    for (final song in await _mostPlayedSongsWithGenres()) {
      for (final genre in song['GenreItems'] as List? ?? const []) {
        if (genre case {'Id': final String id, 'Name': final String name}) {
          plays[id] = (plays[id] ?? 0) + _playCount(song);
          names[id] = name;
        }
      }
    }

    return [for (final id in rankedByCount(plays).take(size)) Genre(id: id, name: names[id]!)];
  }

  /// A decade's plays are those of its songs, by their year (ProductionYear), added up, among the user's most played
  /// songs, as a genre's are. A song without a year is in none.
  @override
  Future<List<int>> mostPlayedDecades({int size = 10}) async {
    final plays = <int, int>{};

    for (final song in await _mostPlayedSongsWithGenres()) {
      if (song['ProductionYear'] case final num year when year > 0) {
        final decade = year.toInt() ~/ 10 * 10;
        plays[decade] = (plays[decade] ?? 0) + _playCount(song);
      }
    }

    return rankedByCount(plays).take(size).toList();
  }

  /// The user's songs at random (SortBy Random), of the genre by its id (GenreIds), and from each of [years] (Years).
  @override
  Future<List<Song>> randomSongs({int size = 100, String? genre, ({int from, int to})? years}) async => [
    for (final json in await _items({
      'IncludeItemTypes': 'Audio',
      'SortBy': 'Random',
      'Limit': '$size',
      'GenreIds': ?genre,
      if (years != null) 'Years': [for (var year = years.from; year <= years.to; year++) year].join(','),
    }))
      _song(json),
  ];

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
  /// among its other ids (ProviderIds), only when asked (Fields), as it does the songs' credits (People) and
  /// MusicBrainz ids. The album's normalization gain is its songs' album gain, which a Jellyfin before 12.0 doesn't
  /// give with each song.
  @override
  Future<(Album, List<Song>)> album(String id) async {
    // Future.wait throws the first failure as it came, where a record's wait would wrap it.
    final [albums, songs] = await Future.wait([
      _items({'Ids': id, 'Fields': 'Studios,ProviderIds'}),
      _items({
        'ParentId': id,
        'IncludeItemTypes': 'Audio',
        'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
        'Fields': 'People,ProviderIds',
      }),
    ]);
    final album = _only(albums, id);

    return (_album(album), [for (final json in songs) _song(json, albumGain: _number(album['NormalizationGain']))]);
  }

  @override
  Future<Song> song(String id) async => _song(_only(await _items({'Ids': id}), id));

  /// The playlists of music, but for those of videos, which Jellyfin keeps among them.
  @override
  Future<List<Playlist>> playlists() async => [
    for (final json in await _items({'IncludeItemTypes': 'Playlist', 'Fields': 'ChildCount'}))
      if (json['MediaType'] != 'Video') _playlist(json),
  ];

  @override
  Future<(Playlist, List<Song>)> playlist(String id) async {
    final [playlists, songs] = await Future.wait([
      _items({'Ids': id, 'Fields': 'ChildCount'}),
      _playlistItems(id),
    ]);

    return (_playlist(_only(playlists, id)), [for (final json in songs) _song(json)]);
  }

  /// A playlist's songs, in its order (Playlists/{id}/Items), each with the id of its entry in it (PlaylistItemId), which
  /// taking it out and moving it go by: a song can be in a playlist more than once.
  Future<List<Map<String, dynamic>>> _playlistItems(String id) =>
      _list('Playlists/${Uri.encodeComponent(id)}/Items', {});

  /// The id of a playlist's entry, as [_playlistItems] gives it.
  static String _entryId(Map<String, dynamic> json) =>
      json['PlaylistItemId'] as String? ?? (throw ServerError('no playlist entry for ${json['Id']}'));

  @override
  Future<void> createPlaylist(String name, {List<String> songIds = const []}) => _send(
    'POST',
    'Playlists',
    body: {'Name': name, 'Ids': songIds, 'UserId': credentials.userId, 'MediaType': 'Audio'},
  );

  /// Playlists/{id}, which Jellyfin has from 10.9 on.
  @override
  Future<void> renamePlaylist(String id, String name) =>
      _send('POST', 'Playlists/${Uri.encodeComponent(id)}', body: {'Name': name});

  @override
  Future<void> deletePlaylist(String id) => _send('DELETE', 'Items/${Uri.encodeComponent(id)}');

  @override
  Future<void> addToPlaylist(String id, List<String> songIds) => _send(
    'POST',
    'Playlists/${Uri.encodeComponent(id)}/Items',
    query: {'ids': songIds.join(','), 'userId': credentials.userId},
  );

  /// By their entries' ids, as the playlist's songs come now.
  @override
  Future<void> removeFromPlaylist(String id, List<int> indexes) async {
    final entries = await _playlistItems(id);

    await _send(
      'DELETE',
      'Playlists/${Uri.encodeComponent(id)}/Items',
      query: {
        'entryIds': [for (final index in indexes) _entryId(entries[index])].join(','),
      },
    );
  }

  /// By its entry's id, as the playlist's songs come now.
  @override
  Future<void> moveInPlaylist(String id, {required int from, required int to}) async {
    final entry = _entryId((await _playlistItems(id))[from]);

    await _send('POST', 'Playlists/${Uri.encodeComponent(id)}/Items/${Uri.encodeComponent(entry)}/Move/$to');
  }

  /// The items the user marked as favorites (IsFavorite), by name: Jellyfin doesn't say when they were. Artists of any
  /// kind (Artists), not only album artists: a song's artist can be one too. With their MusicBrainz ids, as [search] has
  /// them.
  @override
  Future<FavoriteItems> favorites() async {
    final [artists, albums, songs] = await Future.wait([
      _list('Artists', {'IsFavorite': 'true', 'SortBy': 'SortName', 'Fields': 'ProviderIds'}),
      _items({'IncludeItemTypes': 'MusicAlbum', 'Filters': 'IsFavorite', 'SortBy': 'SortName'}),
      _items({'IncludeItemTypes': 'Audio', 'Filters': 'IsFavorite', 'SortBy': 'SortName'}),
    ]);

    return (
      artists: [for (final json in artists) _artist(json)],
      albums: [for (final json in albums) _album(json)],
      songs: [for (final json in songs) _song(json)],
    );
  }

  /// UserFavoriteItems/{id}, whatever the item is: a POST makes it a favorite, a DELETE no longer one.
  @override
  Future<void> setFavorite(FavoriteKind kind, String id, {required bool favorite}) => _send(
    favorite ? 'POST' : 'DELETE',
    'UserFavoriteItems/${Uri.encodeComponent(id)}',
    query: {'userId': credentials.userId},
  );

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

  /// The artists with their MusicBrainz ids (ProviderIds, which come only when asked for), for fanart.tv's picture of
  /// one Jellyfin has none of.
  @override
  Future<SearchResults> search(String query, {int artists = 5, int albums = 10, int songs = 50}) async {
    final [foundArtists, foundAlbums, foundSongs] = await Future.wait([
      _albumArtists({'searchTerm': query, 'Limit': '$artists', 'Fields': 'ProviderIds'}),
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
  /// and their albums' genres, which their page shows, come only when asked for (Fields).
  @override
  Future<(Artist, List<Album>)> artist(String id) async {
    final [artists, albums] = await Future.wait([
      _items({'Ids': id, 'Fields': 'ProviderIds'}),
      _items({
        'AlbumArtistIds': id,
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': 'ProductionYear,SortName',
        'Fields': 'Genres',
      }),
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
  /// themselves, should it count them; with their MusicBrainz ids, as [search] has them.
  @override
  Future<List<Artist>> similarArtists(String artistId) async => [
    for (final json in await _list('Artists/${Uri.encodeComponent(artistId)}/Similar', {
      'Limit': '20',
      'Fields': 'ProviderIds',
    }))
      if (json['Id'] != artistId) _artist(json),
  ];

  /// Items/{id}/InstantMix: Jellyfin's instant mix of a song, the song itself and others of its genres, at random.
  @override
  Future<List<Song>> similarSongs(Song song, {int size = 50}) => radioSongs(song.id, size: size);

  /// Items/{id}/InstantMix, which takes any item: a song, an album, an artist. Each has an id of its own, so
  /// [artistId] goes unused.
  @override
  Future<List<Song>> radioSongs(String id, {String? artistId, int size = 50}) async => [
    for (final json in await _list('Items/${Uri.encodeComponent(id)}/InstantMix', {'Limit': '$size'})) _song(json),
  ];

  /// Jellyfin has no public links.
  @override
  bool get canShare => false;

  @override
  Future<Uri> share(String id) async => throw const SharingOff();

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

  /// The file as it is, or, within [maxBitRate], universal's answer over plain HTTP rather than HLS: the file where it is
  /// within it, and otherwise MP3, as one file.
  @override
  Uri downloadUrl(String songId, {int? maxBitRate}) => maxBitRate == null
      ? streamUrl(songId)
      : _url('Audio/$songId/universal', {
          'MaxStreamingBitrate': '${maxBitRate * 1000}',
          'Container': 'opus,webm|opus,ogg,mp3,aac,m4a|aac,m4a|alac,m4b|aac,flac,webma,webm|webma,wav',
          'TranscodingContainer': 'mp3',
          'TranscodingProtocol': 'http',
          'AudioCodec': 'mp3',
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

  /// Marks the song played at [time] (UserPlayedItems), which counts a play of it: the hub reported none.
  @override
  Future<void> scrobbleMissed(String songId, {required DateTime time}) => _send(
    'POST',
    'UserPlayedItems/$songId',
    query: {'userId': credentials.userId, 'datePlayed': time.toUtc().toIso8601String()},
  );

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

  /// System/Info/Public, which answers without a sign-in, as System/Ping does, and says which server it is, for the log,
  /// once (`Jellyfin Server 10.10.7`).
  @override
  Future<void> ping() async {
    final info = await _get('System/Info/Public', const {});
    final kind = info is Map<String, dynamic>
        ? [info['ProductName'] ?? 'a Jellyfin server', ?info['Version']].join(' ')
        : 'a Jellyfin server';

    if (kind != _kind) {
      _kind = kind;
      _log.info('${server.host}: $kind');
    }
  }

  /// [id] itself: Jellyfin's stay, and Navidrome's Jellyfin API came with its new ones.
  @override
  String currentId(String id, {bool cover = false}) => id;

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

  /// The user's most played songs, with their genres, which the genres and the decades the user plays most are counted
  /// from. The home asks for both at once: a request under way answers both. One that has answered isn't kept, as the
  /// plays change.
  Future<List<Map<String, dynamic>>> _mostPlayedSongsWithGenres() =>
      _mostPlayedRequest ??= _mostPlayedSongs({'Fields': 'Genres'}).whenComplete(() {
        _mostPlayedRequest = null;
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

  /// A request that changes something on the server, as [method] (POST, DELETE), with [query] and a JSON [body]: the
  /// server answers it with nothing, or with what it made.
  Future<void> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final request = http.Request(method, _url(path, query))..headers.addAll(_headers);

    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    final response = await http.Response.fromStream(await _http.send(request));

    switch (response.statusCode) {
      case 401:
        throw const ServerError(
          'the server refused the sign-in',
          isAuth: true,
          reason: ServerErrorReason.signInRefused,
        );
      case 403:
        throw const ServerError('the server doesn\'t let this user change it', reason: ServerErrorReason.notAllowed);
      case < 200 || >= 300:
        throw ServerError('${server.host}: HTTP ${response.statusCode}', statusCode: response.statusCode);
    }
  }

  Uri _url(String path, [Map<String, String>? query]) => server.resolve(path).replace(queryParameters: query);

  static Object? _decode(Uri server, http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ServerError('the server refused the sign-in', isAuth: true, reason: ServerErrorReason.signInRefused);
    }

    if (response.statusCode != 200) {
      throw ServerError('${server.host}: HTTP ${response.statusCode}', statusCode: response.statusCode);
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

/// A number Jellyfin gives, as a double; null where it gives none.
double? _number(Object? json) => switch (json) {
  final num number => number.toDouble(),
  _ => null,
};

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
  // Only where asked for (Fields: Genres).
  genres: [
    for (final genre in json['GenreItems'] as List? ?? const [])
      if (genre case {'Id': final String id, 'Name': final String name}) Genre(id: id, name: name),
  ],
);

/// A song's cover is its own image or else its album's, as Jellyfin's apps show it. Its artists are
/// the album's when it has none of its own, both in its artist's name and in its list of artists. Its MusicBrainz id
/// and its credits come only where asked for (Fields: ProviderIds, People): the people Jellyfin reads from the file's
/// tags (a composer, a conductor, a producer), whose ids are people's, not artists'. Its ReplayGain is its
/// normalization gain, with no peak, and its album's (AlbumNormalizationGain, which Jellyfin gives from 12.0 on, as
/// does Navidrome's Jellyfin API), or else [albumGain], the album's own.
Song _song(Map<String, dynamic> json, {double? albumGain}) => Song(
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
  musicBrainzId: switch (json['ProviderIds']) {
    {'MusicBrainzRecording': final String id} when id.isNotEmpty => id,
    {'MusicBrainzTrack': final String id} when id.isNotEmpty => id,
    _ => null,
  },
  credits: [
    for (final person in json['People'] as List? ?? const [])
      if (person case {'Name': final String name, 'Type': final String type})
        if (CreditRole.named(type) case final role?) Credit(name, role),
  ],
  replayGain: switch ((_number(json['NormalizationGain']), _number(json['AlbumNormalizationGain']) ?? albumGain)) {
    (null, null) => null,
    (final trackGain, final albumGain) => ReplayGain(trackGain: trackGain, albumGain: albumGain),
  },
  track: (json['IndexNumber'] as num?)?.toInt(),
  disc: (json['ParentIndexNumber'] as num?)?.toInt(),
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

/// Jellyfin doesn't say whether the user can change a playlist shared with them: the server refuses where they can't.
Playlist _playlist(Map<String, dynamic> json) => Playlist(
  id: json['Id'] as String,
  name: json['Name'] as String? ?? '',
  coverArt: _primaryImage(json),
  songCount: (json['ChildCount'] as num?)?.toInt(),
);

Genre _genre(Map<String, dynamic> json) => Genre(
  id: json['Id'] as String,
  name: json['Name'] as String? ?? '',
  albumCount: (json['AlbumCount'] as num?)?.toInt(),
);
