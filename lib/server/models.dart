import 'dart:math';

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
    this.genres = const [],
    this.discTitles = const {},
  });

  /// An album as [toJson] gave it.
  factory Album.fromJson(Map<String, dynamic> json) => Album(
    id: json['id'] as String,
    name: json['name'] as String,
    artist: json['artist'] as String?,
    coverArt: json['coverArt'] as String?,
    year: (json['year'] as num?)?.toInt(),
    songCount: (json['songCount'] as num?)?.toInt(),
    artistId: json['artistId'] as String?,
    releaseDate: switch (json['releaseDate']) {
      [final num year, final num? month, final num? day] => ReleaseDate(
        year.toInt(),
        month: month?.toInt(),
        day: day?.toInt(),
      ),
      _ => null,
    },
    recordLabels: [for (final label in json['recordLabels'] as List? ?? const []) label as String],
    musicBrainzId: json['musicBrainzId'] as String?,
    releaseType: ReleaseType.values.asNameMap()[json['releaseType']],
    genres: [for (final genre in json['genres'] as List? ?? const []) Genre.fromJson(genre as Map<String, dynamic>)],
    discTitles: {
      for (final MapEntry(:key, :value) in (json['discTitles'] as Map<String, dynamic>? ?? const {}).entries)
        int.parse(key): value as String,
    },
  );

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

  /// Its genres; none when the server doesn't say, as Jellyfin doesn't unless asked.
  final List<Genre> genres;

  /// The titles of its discs that have one ("Live at Budokan"), by their numbers, from 1; none where the server doesn't
  /// say (OpenSubsonic's discTitles), as Jellyfin never does.
  final Map<int, String> discTitles;

  /// It as JSON, as the app keeps it on the device (the downloads' index, the home's cache): what it needs to show it.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'artist': artist,
    'coverArt': coverArt,
    'year': year,
    'songCount': songCount,
    'artistId': artistId,
    if (releaseDate case final date?) 'releaseDate': [date.year, date.month, date.day],
    'recordLabels': recordLabels,
    'musicBrainzId': musicBrainzId,
    'releaseType': releaseType?.name,
    'genres': [for (final genre in genres) genre.toJson()],
    'discTitles': {for (final MapEntry(:key, :value) in discTitles.entries) '$key': value},
  };
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
    this.musicBrainzId,
    this.credits = const [],
    this.replayGain,
    this.track,
    this.disc,
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

  /// A song as [toJson] gave it.
  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String?,
    album: json['album'] as String?,
    coverArt: json['coverArt'] as String?,
    duration: switch (json['durationMs']) {
      final num ms => Duration(milliseconds: ms.toInt()),
      _ => null,
    },
    albumId: json['albumId'] as String?,
    artists: [
      for (final artist in json['artists'] as List? ?? const []) Artist.fromJson(artist as Map<String, dynamic>),
    ],
    musicBrainzId: json['musicBrainzId'] as String?,
    replayGain: switch (json['replayGain']) {
      final Map<String, dynamic> gain => ReplayGain(
        trackGain: (gain['trackGain'] as num?)?.toDouble(),
        albumGain: (gain['albumGain'] as num?)?.toDouble(),
        trackPeak: (gain['trackPeak'] as num?)?.toDouble(),
        albumPeak: (gain['albumPeak'] as num?)?.toDouble(),
      ),
      _ => null,
    },
    track: (json['track'] as num?)?.toInt(),
    disc: (json['disc'] as num?)?.toInt(),
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

  /// The id in MusicBrainz of its recording, or of its track on its release (as Jellyfin may have it); null when the
  /// server doesn't know it.
  final String? musicBrainzId;

  /// Who is credited on it, where the server says (OpenSubsonic's contributors, from the file's tags; Jellyfin's
  /// people, where asked for them): who wrote it, played in it, produced it. None where it says nothing, and for a
  /// song another device sent, as for [albumId].
  final List<Credit> credits;

  /// How much louder or quieter it plays, so that the songs play about as loud as one another; null where the server
  /// gives no gain for it, and for a song another device sent, as for [albumId].
  final ReplayGain? replayGain;

  /// Its number on its disc of its album, as its file's tags have it; null where the server doesn't say, and for a song
  /// another device sent, as for [albumId].
  final int? track;

  /// Which disc of its album it is on, from 1; null where the server doesn't say, as for [track].
  final int? disc;

  QueueItem toQueueItem() =>
      QueueItem(id: id, title: title, artist: artist, album: album, durationMs: duration?.inMilliseconds);

  /// It as JSON, as the app keeps it on the device: what it needs to show and play it, its credits left out.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'coverArt': coverArt,
    'durationMs': duration?.inMilliseconds,
    'albumId': albumId,
    'artists': [for (final artist in artists) artist.toJson()],
    'musicBrainzId': musicBrainzId,
    if (replayGain case final gain?)
      'replayGain': {
        'trackGain': gain.trackGain,
        'albumGain': gain.albumGain,
        'trackPeak': gain.trackPeak,
        'albumPeak': gain.albumPeak,
      },
    'track': ?track,
    'disc': ?disc,
  };
}

/// A song's ReplayGain, as the media server gives it: OpenSubsonic's, which Navidrome reads from the file's tags, or
/// Jellyfin's normalization gain, which it measures itself (to -18 LUFS) where the file has no tags. In dB, its own
/// gain, against every song, and its album's, which keeps the album's songs as loud as they are against one another;
/// each with its peak, where the server says it: its loudest sample, 1 being the loudest a file holds.
class ReplayGain {
  const ReplayGain({this.trackGain, this.albumGain, this.trackPeak, this.albumPeak});

  final double? trackGain;
  final double? albumGain;
  final double? trackPeak;
  final double? albumPeak;

  /// The gain to play the song with, in dB: its album's ([album]) or its own, the other where the server gives only
  /// that one, [preamp] dB louder. No more than takes its peak to the loudest a file holds, or, where the server doesn't
  /// say the peak, no more than 0 dB, as mpv does with a file's tags: a gain never makes it clip.
  double decibels({required bool album, double preamp = 0}) {
    final (gain, peak) = (album && albumGain != null) || trackGain == null
        ? (albumGain, albumPeak)
        : (trackGain, trackPeak);
    final headroom = peak != null && peak > 0 ? -20 * log(peak) / ln10 : 0.0;

    return min((gain ?? 0) + preamp, headroom);
  }
}

/// Someone credited on a song, by name, and what they did in it ([role]); a musician with what they played or sang
/// ([part]: "guitar", "background vocals"), as the server or MusicBrainz names it, in English mostly.
class Credit {
  const Credit(this.name, this.role, {this.part, this.artistId, this.musicBrainzId});

  final String name;
  final CreditRole role;

  /// The instrument a [CreditRole.performer] played, or the voice they sang in; null where it isn't said.
  final String? part;

  /// Their id as an artist on the media server; null where they aren't one, or the server doesn't say.
  final String? artistId;

  /// Their id in MusicBrainz; null where it isn't known.
  final String? musicBrainzId;
}

/// What someone credited on a song did in it, each in the section of an album's credits it shows under: performing
/// it, writing it, producing it or making its cover and booklet.
enum CreditRole {
  /// Played or sang in it: what, in [Credit.part].
  performer(CreditSection.performance),
  conductor(CreditSection.performance),
  orchestra(CreditSection.performance),

  /// Wrote its music.
  composer(CreditSection.writing),

  /// Wrote its words.
  lyricist(CreditSection.writing),

  /// Wrote it, its music and words, or either, where it isn't said which.
  writer(CreditSection.writing),
  arranger(CreditSection.writing),
  orchestrator(CreditSection.writing),
  librettist(CreditSection.writing),
  producer(CreditSection.production),
  executiveProducer(CreditSection.production),
  engineer(CreditSection.production),
  assistantEngineer(CreditSection.production),
  recordingEngineer(CreditSection.production),
  mixer(CreditSection.production),
  masteringEngineer(CreditSection.production),
  editor(CreditSection.production),
  programmer(CreditSection.production),
  remixer(CreditSection.production),
  djMixer(CreditSection.production),
  artDirector(CreditSection.artwork),
  designer(CreditSection.artwork),
  illustrator(CreditSection.artwork),

  /// Made its artwork, of whatever kind.
  visualArtist(CreditSection.artwork),
  photographer(CreditSection.artwork),

  /// Wrote the notes in its booklet.
  linerNotesWriter(CreditSection.artwork);

  const CreditRole(this.section);

  final CreditSection section;

  /// The role a media server names [name], in any case: OpenSubsonic's contributors' ("composer", "performer",
  /// "djmixer"), Jellyfin's people's types ("Composer", "Conductor"); null for one the credits don't show (an artist,
  /// a director).
  static CreditRole? named(String name) => switch (name.toLowerCase()) {
    'performer' => performer,
    'conductor' => conductor,
    'composer' => composer,
    'lyricist' => lyricist,
    'writer' => writer,
    'arranger' => arranger,
    'producer' => producer,
    'engineer' => engineer,
    'mixer' => mixer,
    'remixer' => remixer,
    'djmixer' => djMixer,
    _ => null,
  };
}

/// The sections of an album's credits, in the order they show, where it was recorded coming before its artwork.
enum CreditSection { performance, writing, production, artwork }

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
  const Artist({required this.id, required this.name, this.coverArt, this.albumCount, this.musicBrainzId});

  /// An artist as [toJson] gave them.
  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    id: json['id'] as String,
    name: json['name'] as String,
    coverArt: json['coverArt'] as String?,
    musicBrainzId: json['musicBrainzId'] as String?,
    albumCount: (json['albumCount'] as num?)?.toInt(),
  );

  final String id;
  final String name;
  final String? coverArt;
  final int? albumCount;

  /// Their id in MusicBrainz; null when the server doesn't know it, or doesn't say it where it is asked for them with
  /// others.
  final String? musicBrainzId;

  /// Them as JSON, as the app keeps them on the device.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'coverArt': coverArt,
    'musicBrainzId': musicBrainzId,
    'albumCount': albumCount,
  };
}

/// What the media server says of an artist's life and work, a paragraph at a time.
class Biography {
  const Biography(this.paragraphs, {this.source});

  final List<String> paragraphs;

  /// Who tells it, by name (Last.fm); null when the server doesn't say.
  final String? source;

  /// The biography [html] tells, as text: the servers give it as HTML, Navidrome Last.fm's summary of it, which ends
  /// with a link to the rest ("Read more on Last.fm") that says where it comes from, its [source]. Null for none, or
  /// one with no words.
  static Biography? fromHtml(String? html) {
    if (html == null) {
      return null;
    }

    final lastFm = RegExp(r'''<a\b[^>]*href=["'][^"']*last\.fm[^>]*>.*?</a>''', caseSensitive: false, dotAll: true);
    final text = html
        .replaceAll(lastFm, '')
        .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp('<[^>]*>'), '');
    final paragraphs = [
      for (final line in _withoutEntities(text).split('\n'))
        if (line.replaceAll(RegExp(r'\s+'), ' ').trim() case final paragraph when paragraph.isNotEmpty) paragraph,
    ];

    return paragraphs.isEmpty ? null : Biography(paragraphs, source: lastFm.hasMatch(html) ? 'Last.fm' : null);
  }

  /// [text] with HTML's entities ("&amp;", "&#39;") as the characters they stand for.
  static String _withoutEntities(String text) =>
      text.replaceAllMapped(RegExp('&(#[0-9]+|#x[0-9a-f]+|[a-z]+);', caseSensitive: false), (match) {
        final name = match[1]!.toLowerCase();
        final code = name.startsWith('#x')
            ? int.tryParse(name.substring(2), radix: 16)
            : name.startsWith('#')
            ? int.tryParse(name.substring(1))
            : null;

        if (code != null) {
          return code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : match[0]!;
        }

        return switch (name) {
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'apos' => "'",
          'nbsp' => ' ',
          _ => match[0]!,
        };
      });
}

/// A genre of the library's albums.
class Genre {
  const Genre({required this.id, required this.name, this.albumCount});

  /// A genre as [toJson] gave it.
  factory Genre.fromJson(Map<String, dynamic> json) =>
      Genre(id: json['id'] as String, name: json['name'] as String, albumCount: (json['albumCount'] as num?)?.toInt());

  /// Its id in Jellyfin's API; in Subsonic's, which has no ids for genres, its name.
  final String id;
  final String name;

  /// How many albums it has; null when the server doesn't say.
  final int? albumCount;

  /// It as JSON, as the app keeps it on the device.
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'albumCount': ?albumCount};
}

/// A playlist: songs in the order someone put them in, the user or another who shares it with them.
class Playlist {
  const Playlist({required this.id, required this.name, this.coverArt, this.songCount, this.editable = true});

  /// A playlist as [toJson] gave it.
  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    coverArt: json['coverArt'] as String?,
    songCount: (json['songCount'] as num?)?.toInt(),
    editable: json['editable'] as bool? ?? false,
  );

  final String id;
  final String name;

  /// The server's picture for it (Navidrome's and Jellyfin's, a collage of its albums' covers); null when it has none.
  final String? coverArt;

  /// How many songs it has; null when the server doesn't say.
  final int? songCount;

  /// Whether the user can change it: rename it, delete it, add songs to it, remove and move them. Not another user's,
  /// nor one the server makes itself from rules (Navidrome's smart playlists).
  final bool editable;

  /// It as JSON, as the app keeps it on the device.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'coverArt': coverArt,
    'songCount': songCount,
    'editable': editable,
  };
}

/// What a search found.
typedef SearchResults = ({List<Artist> artists, List<Album> albums, List<Song> songs});

/// What the user can keep among their favorites: a song, an album, an artist.
enum FavoriteKind { song, album, artist }

/// The user's favorites, of each kind.
typedef FavoriteItems = ({List<Artist> artists, List<Album> albums, List<Song> songs});
