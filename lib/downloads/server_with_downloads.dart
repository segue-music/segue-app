import 'dart:async';
import 'dart:typed_data';

import '../segue/protocol.dart';
import '../server/models.dart';
import '../server/reachability.dart';
import '../server/server.dart';
import 'downloads.dart';
import 'pending_plays.dart';

/// The media server as the app sees it, with what the user downloaded ([downloads]). A downloaded song plays from its
/// file and a downloaded cover shows from its own, the server in reach or not; with it out of reach ([reachability]),
/// what the app asks of it comes from the downloads: their albums and playlists, and the artists and genres of these;
/// what they can't say (the most played, a biography, lyrics) is none, and what changes the server fails at once.
///
/// A request that fails for the network tells [reachability], which then keeps the next ones from waiting on a server
/// that doesn't answer, until it answers again. The plays this device makes meanwhile are kept ([pendingPlays]), and
/// counted as it is back ([MediaServer.scrobbleMissed]).
class ServerWithDownloads implements MediaServer {
  ServerWithDownloads(this.server, this.downloads, this.reachability, {this.pendingPlays}) {
    reachability.addListener(_reachabilityChanged);
    _reachabilityChanged();
  }

  /// The media server itself.
  final MediaServer server;

  final Downloads downloads;
  final Reachability reachability;

  /// The plays made out of reach; null, they go uncounted.
  final PendingPlays? pendingPlays;

  /// In reach again: the plays made meanwhile go to the server.
  void _reachabilityChanged() {
    final pendingPlays = this.pendingPlays;

    if (reachability.value && pendingPlays != null && pendingPlays.plays.isNotEmpty) {
      unawaited(_sendPendingPlays(pendingPlays));
    }
  }

  Future<void> _sendPendingPlays(PendingPlays pendingPlays) async {
    if (!await pendingPlays.send((play) => server.scrobbleMissed(play.songId, time: play.time))) {
      // Out of reach again, unless another send had them.
      if (pendingPlays.plays.isNotEmpty) {
        reachability.lost();
      }
    }
  }

  /// What a request needing the server fails with while it is out of reach.
  static const unreachable = ServerError('no connection to the media server');

  /// [request] of the server, in reach; out of reach, or as a request fails for the network, [downloaded].
  Future<T> _either<T>(Future<T> Function() request, FutureOr<T> Function() downloaded) async {
    if (!reachability.value) {
      return downloaded();
    }

    try {
      return await request();
    } on Object catch (error) {
      if (!isNetworkFailure(error)) {
        rethrow;
      }

      reachability.lost();
      return downloaded();
    }
  }

  /// [request] of the server, which nothing downloaded stands in for: out of reach, it fails at once.
  Future<T> _only<T>(Future<T> Function() request) => _either(request, () => throw unreachable);

  List<Album> get _albums => [for (final download in downloads.all) ?download.album];

  @override
  Api get api => server.api;

  @override
  Credentials get credentials => server.credentials;

  @override
  Auth get auth => server.auth;

  @override
  Future<void> ping() => server.ping();

  @override
  Future<List<Album>> albums({required AlbumOrder order, int size = 100, int offset = 0}) => _either(
    () => server.albums(order: order, size: size, offset: offset),
    () => _page(_sorted(_albums, order), size: size, offset: offset),
  );

  /// [albums] in [order]: the latest downloaded first for the latest added, and none for the most played, which the
  /// downloads can't tell.
  static List<Album> _sorted(List<Album> albums, AlbumOrder order) => switch (order) {
    AlbumOrder.latest => albums,
    AlbumOrder.name => [...albums]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    AlbumOrder.released => [...albums]..sort((a, b) => _released(b).compareTo(_released(a))),
    AlbumOrder.mostPlayed => const [],
  };

  /// When [album] came out, as a number that sorts as the dates do; 0 where it isn't known.
  static int _released(Album album) => switch (album.releaseDate) {
    final date? => date.year * 10000 + (date.month ?? 0) * 100 + (date.day ?? 0),
    null => (album.year ?? 0) * 10000,
  };

  static List<T> _page<T>(List<T> items, {required int size, required int offset}) =>
      items.skip(offset).take(size).toList();

  @override
  Future<List<Genre>> genres() => _either(server.genres, () {
    final counts = <String, ({Genre genre, int albums})>{};

    for (final album in _albums) {
      for (final genre in album.genres) {
        counts[genre.id] = (genre: genre, albums: (counts[genre.id]?.albums ?? 0) + 1);
      }
    }

    return [for (final (:genre, :albums) in counts.values) Genre(id: genre.id, name: genre.name, albumCount: albums)];
  });

  @override
  Future<List<Album>> genreAlbums(String id, {int size = 100, int offset = 0}) => _either(
    () => server.genreAlbums(id, size: size, offset: offset),
    () => _page(
      _sorted([
        for (final album in _albums)
          if (album.genres.any((genre) => genre.id == id)) album,
      ], AlbumOrder.name),
      size: size,
      offset: offset,
    ),
  );

  @override
  Future<List<Album>> mostPlayedAlbums({int size = 20, String? genre}) =>
      _either(() => server.mostPlayedAlbums(size: size, genre: genre), () => const []);

  @override
  Future<List<Genre>> mostPlayedGenres({int size = 10}) =>
      _either(() => server.mostPlayedGenres(size: size), () => const []);

  @override
  Future<List<int>> mostPlayedDecades({int size = 10}) =>
      _either(() => server.mostPlayedDecades(size: size), () => const []);

  /// Out of reach, the songs of the downloaded albums of the genre and from the years, by the album's: a downloaded
  /// playlist says neither of its songs.
  @override
  Future<List<Song>> randomSongs({int size = 100, String? genre, ({int from, int to})? years}) =>
      _either(() => server.randomSongs(size: size, genre: genre, years: years), () {
        bool chosen(Album album) {
          final year = album.year ?? album.releaseDate?.year;
          return (genre == null || album.genres.any((other) => other.id == genre)) &&
              (years == null || (year != null && year >= years.from && year <= years.to));
        }

        final songs = [
          for (final download in downloads.all)
            if (download.album case final album? when chosen(album)) ...download.songs,
        ]..shuffle();
        return songs.take(size).toList();
      });

  @override
  Future<List<Song>> mostPlayedSongs(String artistId, {int size = 10}) =>
      _either(() => server.mostPlayedSongs(artistId, size: size), () => const []);

  @override
  Future<List<Song>> popularSongs(Artist artist, {int size = 10}) =>
      _either(() => server.popularSongs(artist, size: size), () => const []);

  @override
  Future<(Album, List<Song>)> album(String id) => _either(() => server.album(id), () {
    final download = downloads.ofAlbum(id) ?? (throw unreachable);
    return (download.album!, download.songs);
  });

  @override
  Future<Song> song(String id) => _either(
    () => server.song(id),
    () =>
        [for (final download in downloads.all) ...download.songs]
            .firstWhere((song) => song.id == id, orElse: () => throw unreachable),
  );

  @override
  Future<List<Playlist>> playlists() => _either(server.playlists, () {
    return [for (final download in downloads.all) ?download.playlist];
  });

  @override
  Future<(Playlist, List<Song>)> playlist(String id) => _either(() => server.playlist(id), () {
    final download = downloads.ofPlaylist(id) ?? (throw unreachable);
    return (download.playlist!, download.songs);
  });

  @override
  Future<void> createPlaylist(String name, {List<String> songIds = const []}) =>
      _only(() => server.createPlaylist(name, songIds: songIds));

  @override
  Future<void> renamePlaylist(String id, String name) => _only(() => server.renamePlaylist(id, name));

  @override
  Future<void> deletePlaylist(String id) => _only(() => server.deletePlaylist(id));

  @override
  Future<void> addToPlaylist(String id, List<String> songIds) => _only(() => server.addToPlaylist(id, songIds));

  @override
  Future<void> removeFromPlaylist(String id, List<int> indexes) => _only(() => server.removeFromPlaylist(id, indexes));

  @override
  Future<void> moveInPlaylist(String id, {required int from, required int to}) =>
      _only(() => server.moveInPlaylist(id, from: from, to: to));

  @override
  Future<Lyrics?> lyrics(String songId) => _either(() => server.lyrics(songId), () => downloads.lyrics(songId));

  /// From the server alone: what was downloaded doesn't say which are favorites.
  @override
  Future<FavoriteItems> favorites() => _only(server.favorites);

  @override
  Future<void> setFavorite(FavoriteKind kind, String id, {required bool favorite}) =>
      _only(() => server.setFavorite(kind, id, favorite: favorite));

  @override
  Future<SearchResults> search(String query, {int artists = 5, int albums = 10, int songs = 50}) =>
      _either(() => server.search(query, artists: artists, albums: albums, songs: songs), () {
        final words = query.toLowerCase();
        bool matches(String? text) => text != null && text.toLowerCase().contains(words);
        final downloadedSongs = {
          for (final download in downloads.all)
            for (final song in download.songs) song.id: song,
        }.values;
        return (
          artists: [
            for (final artist in _artists())
              if (matches(artist.name)) artist,
          ].take(artists).toList(),
          albums: [
            for (final album in _albums)
              if (matches(album.name) || matches(album.artist)) album,
          ].take(albums).toList(),
          songs: [
            for (final song in downloadedSongs)
              if (matches(song.title) || matches(song.artist) || matches(song.album)) song,
          ].take(songs).toList(),
        );
      });

  @override
  Future<List<Artist>> artists() => _either(server.artists, () => _byName(_artists()));

  /// The artists of the downloaded albums, and of the songs in them and in the downloaded playlists, by their ids, with
  /// how many downloaded albums are theirs.
  List<Artist> _artists() {
    final names = <String, String>{};
    final albums = <String, int>{};

    for (final album in _albums) {
      if (album.artistId case final id?) {
        names[id] ??= album.artist ?? '';
        albums[id] = (albums[id] ?? 0) + 1;
      }
    }

    for (final download in downloads.all) {
      for (final song in download.songs) {
        for (final artist in song.artists) {
          names[artist.id] ??= artist.name;
        }
      }
    }

    return [
      for (final MapEntry(key: id, value: name) in names.entries)
        _withPicture(Artist(id: id, name: name, albumCount: albums[id] ?? 0)),
    ];
  }

  /// [artist] with what the downloads have of them: their picture, and their MusicBrainz id.
  Artist _withPicture(Artist artist) => switch (downloads.artist(artist.id)) {
    final downloaded? => Artist(
      id: artist.id,
      name: downloaded.name,
      albumCount: artist.albumCount,
      coverArt: downloaded.coverArt,
      musicBrainzId: downloaded.musicBrainzId,
    ),
    null => artist,
  };

  static List<Artist> _byName(List<Artist> artists) =>
      artists..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Future<List<Artist>> mostPlayedArtists({int size = 100}) =>
      _either(() => server.mostPlayedArtists(size: size), () => const []);

  @override
  Future<(Artist, List<Album>)> artist(String id) => _either(() => server.artist(id), () {
    final artist = _artists().where((artist) => artist.id == id).firstOrNull ?? (throw unreachable);
    return (
      artist,
      [
        for (final album in _albums)
          if (album.artistId == id) album,
      ],
    );
  });

  @override
  Future<Biography?> biography(String artistId) => _either(() => server.biography(artistId), () => null);

  @override
  Future<List<Artist>> similarArtists(String artistId) =>
      _either(() => server.similarArtists(artistId), () => const []);

  @override
  Future<List<Song>> similarSongs(Song song, {int size = 50}) =>
      _either(() => server.similarSongs(song, size: size), () => const []);

  /// The song's file, where it is downloaded, the server in reach or not: it plays as it is, whatever [maxBitRate].
  @override
  Uri streamUrl(String songId, {int? maxBitRate}) =>
      downloads.songFile(songId)?.uri ?? server.streamUrl(songId, maxBitRate: maxBitRate);

  @override
  Uri downloadUrl(String songId, {int? maxBitRate}) => server.downloadUrl(songId, maxBitRate: maxBitRate);

  /// None for a downloaded song, whose file seeks.
  @override
  Future<Uri?> transcodedStreamUrl(String songId, {required int maxBitRate, required Duration from}) async =>
      downloads.songFile(songId) != null
      ? null
      : await server.transcodedStreamUrl(songId, maxBitRate: maxBitRate, from: from);

  /// Out of reach, or failing for the network, the play is kept, to be counted as the server is back.
  @override
  Future<void> scrobble(String songId, {required DateTime time}) async {
    final counted = await _either(() async {
      await server.scrobble(songId, time: time);
      return true;
    }, () => false);

    if (!counted) {
      await pendingPlays?.add(songId, time);
    }
  }

  @override
  Future<void> scrobbleMissed(String songId, {required DateTime time}) => server.scrobbleMissed(songId, time: time);

  /// The cover's file, where it is downloaded, at [Downloads.coverSize] pixels whatever [size]: the image shown takes it
  /// to the size it wants.
  @override
  Uri coverArtUrl(String id, {int size = 300}) => downloads.coverFile(id)?.uri ?? server.coverArtUrl(id, size: size);

  @override
  Future<Uint8List> coverArt(String id, {int size = 300}) async {
    final file = downloads.coverFile(id);
    return file != null ? file.readAsBytes() : _only(() => server.coverArt(id, size: size));
  }

  @override
  Future<void> signOut() => server.signOut();

  @override
  void close() {
    reachability.removeListener(_reachabilityChanged);
    server.close();
  }
}
