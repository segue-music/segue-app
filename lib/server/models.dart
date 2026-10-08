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
    this.releaseDate,
    this.recordLabels = const [],
    this.musicBrainzId,
    this.releaseType,
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

  /// When it came out; null when the server doesn't say.
  final ReleaseDate? releaseDate;

  /// The labels that put it out; none when the server doesn't say.
  final List<String> recordLabels;

  /// The id of its release in MusicBrainz (its edition, with its date and labels); null when the server doesn't know
  /// it.
  final String? musicBrainzId;

  /// What kind of release it is: an album proper, an EP, a single, a compilation; null when the server doesn't say,
  /// as Jellyfin never does.
  final ReleaseType? releaseType;
}

/// What kind of release an album is, as MusicBrainz sorts them: by its primary type (an album, an EP, a single), or
/// its secondary one, a compilation, which is an album too.
enum ReleaseType {
  album,
  ep,
  single,

  /// Songs that came out before, as a best of.
  compilation;

  /// The type of a release whose types, as MusicBrainz names them ("Album", "EP", "Compilation"), in any case, are
  /// [names], which may also hold several apart by commas, semicolons or slashes, as a file's tag does; null when none
  /// is one of these.
  static ReleaseType? named(Iterable<String> names) {
    final types = {
      for (final name in names)
        for (final type in name.split(RegExp('[,;/]'))) type.trim().toLowerCase(),
    };

    if (types.contains('compilation')) {
      return compilation;
    }

    return [album, ep, single].where((type) => types.contains(type.name)).firstOrNull;
  }
}

/// A date as precisely as the server knows it: a day, or only a month, or only a year.
class ReleaseDate {
  const ReleaseDate(this.year, {this.month, this.day});

  final int year;

  /// From 1, January, to 12; null when only the year is known.
  final int? month;

  /// The day of the month; null when only the month or the year is known.
  final int? day;
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
    this.artists = const [],
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

  /// Its artists, with their ids, the ones [artist] names: the main one first, then those with them ("Run-DMC;
  /// Aerosmith", "Santana feat. Rob Thomas"). None for a song another device sent, as for [albumId].
  final List<Artist> artists;

  /// The id of its first artist, the one its [artist] starts with; null as [albumId] is.
  String? get artistId => artists.firstOrNull?.id;

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
