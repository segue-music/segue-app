import '../segue/protocol.dart';

/// The library's items, whichever API they came from. Ids and cover ids are the media server's, in
/// its API.
class Album {
  const Album({
    required this.id,
    required this.name,
    this.artist,
    this.coverArt,
    this.year,
    this.songCount,
    this.artistId,
  });

  final String id;
  final String name;
  final String? artist;
  final String? coverArt;
  final int? year;
  final int? songCount;

  /// The id of its artist, the one its [artist] names (the first, when it has several); null when the
  /// server gives none.
  final String? artistId;
}

class Song {
  const Song({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.coverArt,
    this.duration,
    this.albumId,
    this.artistId,
  });

  /// A song another device sent, by its id in this device's API. The cover goes by the song id:
  /// Navidrome takes a raw entity id for getCoverArt (parseArtworkID in core/artwork/artwork.go), and
  /// its Jellyfin API serves a song's album art for it. A Jellyfin server has an image only for songs
  /// whose file has one.
  factory Song.fromQueueItem(QueueItem item) => Song(
    id: item.id!,
    title: item.title ?? '',
    artist: item.artist,
    album: item.album,
    coverArt: item.id,
    duration: item.durationMs == null ? null : Duration(milliseconds: item.durationMs!),
  );

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? coverArt;
  final Duration? duration;

  /// Its album's id; null for a song another device sent, whose queue item doesn't carry it.
  final String? albumId;

  /// The id of its first artist, the one its [artist] starts with; null as [albumId] is.
  final String? artistId;

  QueueItem toQueueItem() =>
      QueueItem(id: id, title: title, artist: artist, album: album, durationMs: duration?.inMilliseconds);
}

/// A song's lyrics, line by line, each with when it starts when they're synced to the song.
class Lyrics {
  const Lyrics(this.lines, {this.provider});

  final List<LyricLine> lines;

  /// Who gives them: the media server, by its name (Navidrome, Jellyfin); null when it doesn't say.
  final String? provider;

  /// Whether each line says when it starts.
  bool get synced => lines.every((line) => line.start != null);
}

class LyricLine {
  const LyricLine(this.text, {this.start});

  final String text;

  /// When it starts in the song; null in lyrics that aren't synced.
  final Duration? start;
}

class Artist {
  const Artist({required this.id, required this.name, this.coverArt, this.albumCount});

  final String id;
  final String name;
  final String? coverArt;
  final int? albumCount;
}

/// A genre of the library's albums.
class Genre {
  const Genre({required this.id, required this.name, this.albumCount});

  /// Its id in Jellyfin's API; in Subsonic's, which has no ids for genres, its name.
  final String id;
  final String name;

  /// How many albums it has; null when the server doesn't say.
  final int? albumCount;
}

/// What a search found.
typedef SearchResults = ({List<Artist> artists, List<Album> albums, List<Song> songs});
