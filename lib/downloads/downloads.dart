import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../server/models.dart';
import '../server/reachability.dart';
import '../server/server.dart';

/// An album or a playlist downloaded, or downloading, to play without the media server: as the server gave it, with its
/// songs, when it was asked for.
@immutable
class Download {
  const Download.album(Album this.album, this.songs, {required this.added}) : playlist = null;

  const Download.playlist(Playlist this.playlist, this.songs, {required this.added}) : album = null;

  /// The album it is, or null for a playlist.
  final Album? album;

  /// The playlist it is, or null for an album.
  final Playlist? playlist;

  final List<Song> songs;

  /// When it was asked for.
  final DateTime added;

  String get id => album != null ? album!.id : playlist!.id;
  String get name => album != null ? album!.name : playlist!.name;

  /// Its cover; null where the server has none for it.
  String? get coverArt => album != null ? album!.coverArt : playlist!.coverArt;

  /// The covers it shows: its own and its songs'.
  Set<String> get covers => {?coverArt, for (final song in songs) ?song.coverArt};

  String get _key => album != null ? 'album:$id' : 'playlist:$id';
}

/// How far a download has got: of its songs, how many are on the device, and how many failed to come this time.
typedef DownloadProgress = ({int done, int failed, int total});

/// The albums and playlists the user downloaded, in [directory]: the songs as their files are (what the media server
/// streams without transcoding), their covers, and what they are (an index), so that they play, and show, without the
/// server. Each song is there once, however many downloads have it.
///
/// What a download lacks comes from the server one file at a time, songs first, while it is in reach ([reachability]):
/// a file that fails waits for the next time it is, or for the app to open again.
class Downloads extends ChangeNotifier {
  Downloads._(this.directory, this._server, this._http, this._reachability, this._downloads, this._files);

  /// The downloads kept in [directory], whose missing songs and covers come from [server] (its files as they are, its
  /// covers at [coverSize] pixels) through [client].
  static Future<Downloads> open(
    Directory directory,
    MediaServer server, {
    http.Client? client,
    Reachability? reachability,
  }) async {
    await Directory('${directory.path}/$_songsFolder').create(recursive: true);
    await Directory('${directory.path}/$_coversFolder').create(recursive: true);
    final index = File('${directory.path}/$_indexFile');
    final downloads = <String, Download>{};
    var readable = true;

    if (await index.exists()) {
      try {
        final json = jsonDecode(await index.readAsString()) as Map<String, dynamic>;

        for (final item in json['downloads'] as List) {
          final download = _download(item as Map<String, dynamic>);
          downloads[download._key] = download;
        }
      } on Object catch (e) {
        // Its files stay, rather than go as no download's.
        debugPrint('downloads index unreadable: $e');
        readable = false;
      }
    }

    final files = <String>{};

    for (final folder in [_songsFolder, _coversFolder]) {
      await for (final entity in Directory('${directory.path}/$folder').list()) {
        // One left halfway by a download cut short.
        if (entity.path.endsWith('.part')) {
          await entity.delete();
        } else {
          files.add('$folder/${entity.uri.pathSegments.last}');
        }
      }
    }

    final opened = Downloads._(directory, server, client ?? http.Client(), reachability, downloads, files);
    reachability?.addListener(opened._reachabilityChanged);

    if (readable) {
      await opened._forget();
    }

    unawaited(opened._fetch());
    return opened;
  }

  /// Where they are kept.
  final Directory directory;

  final MediaServer _server;
  final http.Client _http;
  final Reachability? _reachability;

  /// By [Download._key], in the order they were asked for.
  final Map<String, Download> _downloads;

  /// The files there, by their path under [directory] (`songs/<key>`, `covers/<key>`).
  final Set<String> _files;

  /// The songs and covers, by their files, that failed to come since the server was last out of reach.
  final _failed = <String>{};

  bool _fetching = false;
  bool _disposed = false;

  /// The covers' size, in pixels: as the largest the app asks the server for, a phone's player and an album's page.
  static const coverSize = 800;

  static const _songsFolder = 'songs';
  static const _coversFolder = 'covers';
  static const _indexFile = 'index.json';

  /// Every download, the latest asked for first.
  List<Download> get all => _downloads.values.toList().reversed.toList();

  /// The download of the album whose id is [id]; null where there is none.
  Download? ofAlbum(String id) => _downloads['album:$id'];

  /// The download of the playlist whose id is [id]; null where there is none.
  Download? ofPlaylist(String id) => _downloads['playlist:$id'];

  DownloadProgress progressOf(Download download) {
    var (done, failed) = (0, 0);

    for (final song in download.songs) {
      final file = _songFile(song.id);

      if (_files.contains(file)) {
        done++;
      } else if (_failed.contains(file)) {
        failed++;
      }
    }

    return (done: done, failed: failed, total: download.songs.length);
  }

  /// The file of the song whose id is [songId], where it is on the device.
  File? songFile(String songId) => _existing(_songFile(songId));

  /// The file of the cover whose id is [coverId], where it is on the device, at [coverSize] pixels.
  File? coverFile(String coverId) => _existing(_coverFile(coverId));

  File? _existing(String file) => _files.contains(file) ? File('${directory.path}/$file') : null;

  /// Downloads [album], with [songs], its songs; again, for one already there, with the songs it has now.
  Future<void> addAlbum(Album album, List<Song> songs) =>
      _add(Download.album(album, List.unmodifiable(songs), added: clock.now()));

  /// Downloads [playlist], with [songs], its songs, in its order; again, for one already there, with the songs it has
  /// now.
  Future<void> addPlaylist(Playlist playlist, List<Song> songs) =>
      _add(Download.playlist(playlist, List.unmodifiable(songs), added: clock.now()));

  Future<void> _add(Download download) async {
    _downloads
      ..remove(download._key)
      ..[download._key] = download;
    notifyListeners();
    await _save();
    await _forget();
    unawaited(_fetch());
  }

  /// Takes [download] off the device: the songs and covers no other download has.
  Future<void> remove(Download download) async {
    if (_downloads.remove(download._key) == null) {
      return;
    }

    notifyListeners();
    await _save();
    await _forget();
  }

  /// How much room the downloads take, in bytes.
  Future<int> size() async {
    var bytes = 0;

    for (final file in _files.toList()) {
      try {
        bytes += await File('${directory.path}/$file').length();
      } on FileSystemException {
        continue; // gone meanwhile
      }
    }

    return bytes;
  }

  /// Fetches what the downloads lack, a file at a time, songs first, until none is left, the server is out of reach or
  /// the downloads close. A file that fails is skipped until the server is back in reach.
  Future<void> _fetch() async {
    if (_fetching) {
      return;
    }

    _fetching = true;

    try {
      while (!_disposed && (_reachability?.value ?? true)) {
        final song = _missingSong();
        final cover = song == null ? _missingCover() : null;

        if (song == null && cover == null) {
          break;
        }

        final file = song != null ? _songFile(song.id) : _coverFile(cover!);

        try {
          if (song != null) {
            await _fetchSong(song, file);
          } else {
            await _fetchCover(cover!, file);
          }

          _files.add(file);
        } on Object catch (error) {
          debugPrint('download of $file: $error');
          _failed.add(file);

          if (isNetworkFailure(error)) {
            _reachability?.lost();
          }
        }

        // Taken off meanwhile.
        if (!_wanted().contains(file)) {
          await _delete(file);
        }

        if (!_disposed) {
          notifyListeners();
        }
      }
    } finally {
      _fetching = false;
    }
  }

  Song? _missingSong() {
    for (final download in _downloads.values) {
      for (final song in download.songs) {
        final file = _songFile(song.id);

        if (!_files.contains(file) && !_failed.contains(file)) {
          return song;
        }
      }
    }

    return null;
  }

  String? _missingCover() {
    for (final download in _downloads.values) {
      for (final cover in download.covers) {
        final file = _coverFile(cover);

        if (!_files.contains(file) && !_failed.contains(file)) {
          return cover;
        }
      }
    }

    return null;
  }

  /// The song's file as it is, as the server streams it untranscoded, written beside where it goes and moved there
  /// once whole.
  Future<void> _fetchSong(Song song, String file) async {
    final response = await _http.send(http.Request('GET', _server.streamUrl(song.id))).timeout(_wait);

    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw ServerError('HTTP ${response.statusCode}');
    }

    final part = File('${directory.path}/$file.part');

    try {
      // A stream that stops coming fails, rather than leaving the downloads waiting on it.
      await response.stream.timeout(_wait).pipe(part.openWrite());
      await part.rename('${directory.path}/$file');
    } on Object {
      if (await part.exists()) {
        await part.delete();
      }

      rethrow;
    }
  }

  Future<void> _fetchCover(String cover, String file) async {
    final bytes = await _server.coverArt(cover, size: coverSize).timeout(_wait);
    final part = File('${directory.path}/$file.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename('${directory.path}/$file');
  }

  /// How long the downloads wait for the server, for an answer or for more of a file.
  static const _wait = Duration(seconds: 30);

  /// Every file the downloads want.
  Set<String> _wanted() => {
    for (final download in _downloads.values) ...[
      for (final song in download.songs) _songFile(song.id),
      for (final cover in download.covers) _coverFile(cover),
    ],
  };

  /// Deletes the files no download wants.
  Future<void> _forget() async {
    final wanted = _wanted();

    for (final file in _files.difference(wanted).toList()) {
      await _delete(file);
    }

    _failed.removeWhere((file) => !wanted.contains(file));
  }

  Future<void> _delete(String file) async {
    _files.remove(file);

    try {
      await File('${directory.path}/$file').delete();
    } on FileSystemException {
      // already gone
    }
  }

  /// Writes the index beside where it goes, and moves it there, so that one cut short never leaves half an index.
  Future<void> _save() async {
    final part = File('${directory.path}/$_indexFile.part');
    await part.writeAsString(
      jsonEncode({
        'downloads': [for (final download in _downloads.values) _downloadJson(download)],
      }),
      flush: true,
    );
    await part.rename('${directory.path}/$_indexFile');
  }

  /// The server is in reach again: the files that failed are tried again.
  void _reachabilityChanged() {
    if (_reachability?.value ?? false) {
      _failed.clear();
      notifyListeners();
      unawaited(_fetch());
    }
  }

  /// Tries again the files that failed to come.
  void retry() {
    _failed.clear();
    notifyListeners();
    unawaited(_fetch());
  }

  static String _songFile(String id) => '$_songsFolder/${_name(id)}';
  static String _coverFile(String id) => '$_coversFolder/${_name(id)}';

  /// A file's name for an id, which may hold any character: base 64, as URLs have it, without its padding.
  static String _name(String id) => base64Url.encode(utf8.encode(id)).replaceAll('=', '');

  @override
  void dispose() {
    _disposed = true;
    _reachability?.removeListener(_reachabilityChanged);
    _http.close();
    super.dispose();
  }
}

// The index, as JSON: what the app needs of each album, playlist and song to show and play them.

Map<String, Object?> _downloadJson(Download download) => {
  if (download.album case final album?) 'album': _albumJson(album),
  if (download.playlist case final playlist?) 'playlist': _playlistJson(playlist),
  'songs': [for (final song in download.songs) _songJson(song)],
  'added': download.added.millisecondsSinceEpoch,
};

Download _download(Map<String, dynamic> json) {
  final songs = [for (final song in json['songs'] as List) _song(song as Map<String, dynamic>)];
  final added = DateTime.fromMillisecondsSinceEpoch((json['added'] as num).toInt());
  return switch ((json['album'], json['playlist'])) {
    (final Map<String, dynamic> album, _) => Download.album(_album(album), songs, added: added),
    (_, final Map<String, dynamic> playlist) => Download.playlist(_playlist(playlist), songs, added: added),
    _ => throw const FormatException('neither an album nor a playlist'),
  };
}

Map<String, Object?> _albumJson(Album album) => {
  'id': album.id,
  'name': album.name,
  'artist': album.artist,
  'coverArt': album.coverArt,
  'year': album.year,
  'songCount': album.songCount,
  'artistId': album.artistId,
  if (album.releaseDate case final date?) 'releaseDate': [date.year, date.month, date.day],
  'recordLabels': album.recordLabels,
  'musicBrainzId': album.musicBrainzId,
  'releaseType': album.releaseType?.name,
  'genres': [
    for (final genre in album.genres) {'id': genre.id, 'name': genre.name},
  ],
};

Album _album(Map<String, dynamic> json) => Album(
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
  genres: [
    for (final genre in json['genres'] as List? ?? const [])
      Genre(id: (genre as Map<String, dynamic>)['id'] as String, name: genre['name'] as String),
  ],
);

Map<String, Object?> _playlistJson(Playlist playlist) => {
  'id': playlist.id,
  'name': playlist.name,
  'coverArt': playlist.coverArt,
  'songCount': playlist.songCount,
  'editable': playlist.editable,
};

Playlist _playlist(Map<String, dynamic> json) => Playlist(
  id: json['id'] as String,
  name: json['name'] as String,
  coverArt: json['coverArt'] as String?,
  songCount: (json['songCount'] as num?)?.toInt(),
  editable: json['editable'] as bool? ?? false,
);

Map<String, Object?> _songJson(Song song) => {
  'id': song.id,
  'title': song.title,
  'artist': song.artist,
  'album': song.album,
  'coverArt': song.coverArt,
  'durationMs': song.duration?.inMilliseconds,
  'albumId': song.albumId,
  'artists': [
    for (final artist in song.artists) {'id': artist.id, 'name': artist.name},
  ],
  'musicBrainzId': song.musicBrainzId,
  if (song.replayGain case final gain?)
    'replayGain': {
      'trackGain': gain.trackGain,
      'albumGain': gain.albumGain,
      'trackPeak': gain.trackPeak,
      'albumPeak': gain.albumPeak,
    },
};

Song _song(Map<String, dynamic> json) => Song(
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
    for (final artist in json['artists'] as List? ?? const [])
      Artist(id: (artist as Map<String, dynamic>)['id'] as String, name: artist['name'] as String),
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
);
