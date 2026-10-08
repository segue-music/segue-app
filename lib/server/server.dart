import 'dart:typed_data';

import '../segue/protocol.dart';
import 'models.dart';

/// How the app introduces itself, to the media server and to the hub.
const clientName = 'Segue';
const appVersion = '0.1.0';

/// What the app keeps of a sign-in, to talk to the media server again without the password.
abstract interface class Credentials {
  /// The user's name on the media server.
  String get username;
}

/// The media server refused a request, or answered with something the app can't use.
class ServerError implements Exception {
  const ServerError(this.message, {this.isAuth = false});

  final String message;

  /// The server doesn't take the credentials: a wrong user or password, or a sign-in it forgot.
  final bool isAuth;

  @override
  String toString() => message;
}

/// Orders the library's albums come in.
enum AlbumOrder {
  /// The latest added to the library first.
  latest,

  /// By name.
  name,

  /// The latest released first, by release date.
  released,

  /// The ones the user plays most first; none before anything has played.
  mostPlayed,
}

/// The keys of [counts], the highest count first; a tie keeps their order in [counts].
List<K> rankedByCount<K>(Map<K, int> counts) {
  final ranked = [for (final (i, MapEntry(:key, :value)) in counts.entries.indexed) (key: key, count: value, i: i)]
    ..sort((a, b) => a.count != b.count ? b.count.compareTo(a.count) : a.i.compareTo(b.i));
  return [for (final entry in ranked) entry.key];
}

/// The media server, through the API it speaks: `SubsonicApi` or `JellyfinApi`.
abstract interface class MediaServer {
  /// Also the API of the ids the hub gives this device (SPEC.md, section 8).
  Api get api;

  Credentials get credentials;

  /// The same credentials, for the hub's hello (SPEC.md, section 2).
  Auth get auth;

  /// Albums, in [order].
  Future<List<Album>> albums({required AlbumOrder order, int size = 100, int offset = 0});

  /// Every genre, in no particular order.
  Future<List<Genre>> genres();

  /// The albums of the genre whose id is [id], by name.
  Future<List<Album>> genreAlbums(String id, {int size = 100, int offset = 0});

  /// The albums the user plays most, the most played first; none before anything has played. With
  /// [genre], a genre's id, those of that genre.
  Future<List<Album>> mostPlayedAlbums({int size = 20, String? genre});

  /// The genres the user plays most, the most played first; none before anything has played.
  Future<List<Genre>> mostPlayedGenres({int size = 10});

  /// The songs of the artist whose id is [artistId] that the user plays most, the most played first;
  /// none before any of theirs has played.
  Future<List<Song>> mostPlayedSongs(String artistId, {int size = 10});

  /// The songs of [artist] that everyone plays most, the most popular first, of those in the library, as the server
  /// learns them from Last.fm or the like; none where it can't say.
  Future<List<Song>> popularSongs(Artist artist, {int size = 10});

  /// An album and its songs, in order. The album may say more than in a list of albums: its record labels, on a
  /// Jellyfin server.
  Future<(Album, List<Song>)> album(String id);

  /// A song, with its album's and its artist's ids.
  Future<Song> song(String id);

  /// The user's playlists, and those others share with them, in no particular order.
  Future<List<Playlist>> playlists();

  /// A playlist and its songs, in its order.
  Future<(Playlist, List<Song>)> playlist(String id);

  /// Makes a playlist of the user's named [name], with the songs whose ids are [songIds] in it, in that order.
  Future<void> createPlaylist(String name, {List<String> songIds = const []});

  /// Names the playlist whose id is [id] [name].
  Future<void> renamePlaylist(String id, String name);

  /// Deletes the playlist whose id is [id]; its songs stay in the library.
  Future<void> deletePlaylist(String id);

  /// Adds the songs whose ids are [songIds] at the end of the playlist whose id is [id], in that order.
  Future<void> addToPlaylist(String id, List<String> songIds);

  /// Takes out of the playlist whose id is [id] its songs at [indexes], from 0, in its order as [playlist] gives it.
  Future<void> removeFromPlaylist(String id, List<int> indexes);

  /// Moves the song at [from] in the playlist whose id is [id] to [to], the place it then has, the songs between moving
  /// up or down to make room; both from 0, in its order as [playlist] gives it.
  Future<void> moveInPlaylist(String id, {required int from, required int to});

  /// A song's lyrics, the synced ones where the server has both; null when it has none.
  Future<Lyrics?> lyrics(String songId);

  /// Artists, albums and songs whose name, title or artist matches [query].
  Future<SearchResults> search(String query, {int artists = 5, int albums = 10, int songs = 50});

  /// Every artist, by name.
  Future<List<Artist>> artists();

  /// The artists the user plays most, the most played first, as [artists] gives them; none before anything has
  /// played.
  Future<List<Artist>> mostPlayedArtists({int size = 100});

  /// An artist and their albums.
  Future<(Artist, List<Album>)> artist(String id);

  /// The biography of the artist whose id is [artistId], as the server has it (Navidrome from Last.fm, Jellyfin from
  /// its metadata or the user); null when it has none.
  Future<Biography?> biography(String artistId);

  /// The library's artists like the one whose id is [artistId], the most alike first, 20 at most, as the server learns
  /// them (Navidrome from Last.fm, Jellyfin from their metadata); none where it can't say.
  Future<List<Artist>> similarArtists(String artistId);

  /// Where a song's audio is, for the player: the URL carries the credentials. With [maxBitRate], in kbps, the server
  /// transcodes a song whose bitrate is higher, as it goes: on Subsonic a stream that can't seek ([transcodedStreamUrl]
  /// stands in), and on Jellyfin HLS, which can.
  Uri streamUrl(String songId, {int? maxBitRate});

  /// The stream that [streamUrl] gives with [maxBitRate] where the server transcodes the song, from [from] on, in whole
  /// seconds: to seek in a stream that can't, the player starts it there instead. Null where the server can't start
  /// it later: a Subsonic server without OpenSubsonic's transcodeOffset, and Jellyfin, whose HLS needn't.
  Future<Uri?> transcodedStreamUrl(String songId, {required int maxBitRate, required Duration from});

  /// Counts a play of the song whose id is [songId], which started playing at [time], toward the
  /// user's most played.
  Future<void> scrobble(String songId, {required DateTime time});

  Uri coverArtUrl(String id, {int size = 300});

  /// The cover's image bytes.
  Future<Uint8List> coverArt(String id, {int size = 300});

  /// Ends the sign-in on the server, where it keeps one (Jellyfin). Never throws: signing out
  /// offline still signs out.
  Future<void> signOut();

  void close();
}
