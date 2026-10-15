import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../server/models.dart';
import '../server/reachability.dart';
import '../server/server.dart';

final _log = Logger('Downloads');

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

/// Something a download lacks, and how it comes: by the key it fails under ([Downloads._failed]), a file's path.
typedef _Missing = ({String key, Future<void> Function() fetch});

/// The albums and playlists the user downloaded, in [directory]: the songs as their files are, or transcoded down to a
/// bitrate, their covers, their lyrics, their artists with their pictures, and what they all are (an index), so that
/// they play, and show, without the media server. Each song is there once, however many downloads have it.
///
/// What a download lacks comes from the server one thing at a time, its songs, then their covers, lyrics and artists,
/// while it is in reach ([Reachability]) and the downloads aren't held (on mobile data, where the user keeps them off
/// it): what fails waits for the next time the server is in reach, or for the app to open again.
class Downloads extends ChangeNotifier {
  Downloads._(
    this.directory,
    this._server,
    this._http,
    this._reachability,
    this._downloads,
    this._artists,
    this._files,
    this._renames,
    this._kept,
    this._maxBitRate,
    this._hold,
    this._lyricsOf,
    this._artistPicture,
  );

  /// The downloads kept in [directory], whose missing songs, covers and artists come from [server] through [client]:
  /// the songs in the bitrate [maxBitRate] gives as each comes (null, the files as they are), the covers and artists'
  /// pictures at [coverSize] pixels, and, where the server has none, the artist's picture that [artistPicture] finds
  /// (fanart.tv's). Their lyrics are the ones [lyricsOf] finds. Nothing comes while [hold] is true.
  static Future<Downloads> open(
    Directory directory,
    MediaServer server, {
    http.Client? client,
    Reachability? reachability,
    int? Function()? maxBitRate,
    ValueListenable<bool>? hold,
    Future<Lyrics?> Function(Song song)? lyricsOf,
    Future<Uri?> Function(Artist artist)? artistPicture,
  }) async {
    for (final folder in _folders) {
      await Directory('${directory.path}/$folder').create(recursive: true);
    }

    final index = File('${directory.path}/$_indexFile');
    final downloads = <String, Download>{};
    final artists = <String, Artist>{};
    final renames = <String, String>{};
    final kept = <String>{};
    var readable = true;

    if (await index.exists()) {
      try {
        final json = jsonDecode(await index.readAsString()) as Map<String, dynamic>;

        for (final item in json['downloads'] as List) {
          final download = _download(item as Map<String, dynamic>);
          downloads[download._key] = download;
        }

        for (final item in json['artists'] as List? ?? const []) {
          final artist = Artist.fromJson(item as Map<String, dynamic>);
          artists[artist.id] = artist;
        }

        for (final MapEntry(key: from, value: to) in (json['renames'] as Map<String, dynamic>? ?? const {}).entries) {
          renames[from] = to as String;
        }

        kept.addAll([for (final file in json['kept'] as List? ?? const []) file as String]);
      } on FileSystemException {
        // The disk, not what the index says: it may read the next time, and stays as it is, the downloads failing.
        rethrow;
      } on Object catch (e) {
        _log.warning('downloads index unreadable', e);
        readable = false;
      }
    }

    final files = <String>{};

    for (final folder in _folders) {
      await for (final entity in Directory('${directory.path}/$folder').list()) {
        // One left halfway by a download cut short.
        if (entity.path.endsWith('.part')) {
          await entity.delete();
        } else {
          files.add('$folder/${entity.uri.pathSegments.last}');
        }
      }
    }

    if (!readable) {
      kept.addAll(files);
    }

    final opened = Downloads._(
      directory,
      server,
      client ?? http.Client(),
      reachability,
      downloads,
      artists,
      files,
      renames,
      kept,
      maxBitRate,
      hold,
      lyricsOf,
      artistPicture,
    );

    reachability?.addListener(opened._resume);
    hold?.addListener(opened._resume);

    if (readable) {
      await opened._finishRenames();
      await opened._forget();
    } else {
      // It goes aside, rather than under the next index, and its files are kept in that one.
      await index.rename('${directory.path}/$_unreadableIndexFile');
      await opened._save();
    }

    unawaited(opened._fetch());

    return opened;
  }

  /// Where they are kept.
  final Directory directory;

  final MediaServer _server;
  final http.Client _http;
  final Reachability? _reachability;
  final int? Function()? _maxBitRate;
  final ValueListenable<bool>? _hold;
  final Future<Lyrics?> Function(Song song)? _lyricsOf;
  final Future<Uri?> Function(Artist artist)? _artistPicture;

  /// By [Download._key], in the order they were asked for.
  final Map<String, Download> _downloads;

  /// The artists of the downloads, by their ids, as the server gave them, with the id of their picture on the device
  /// ([Artist.coverArt]): the server's, or, for fanart.tv's, `fanart:` and their MusicBrainz id.
  final Map<String, Artist> _artists;

  /// The files there, by their path under [directory] (`songs/<key>`, `covers/<key>`, `lyrics/<key>`).
  final Set<String> _files;

  /// The files that take new names, as the ids they are named by changed ([_renameIds]), from the one they have to
  /// the one they take, until they have: in the index too, for the downloads to go on with them as they open again.
  final Map<String, String> _renames;

  /// The files the downloads keep though none wants them: those of an index that couldn't be read (a newer app's,
  /// say), rather than delete what it had, until a download wants one, which then goes with it. In the index too, for
  /// the next time they open.
  final Set<String> _kept;

  /// What failed to come since the server was last out of reach, by its key: a file's path, or an artist's
  /// (`artists/<key>`).
  final _failed = <String>{};

  /// The fetching under way ([_fetch]); null while there is none.
  Future<void>? _fetching;

  /// The last write of the index asked for ([_save]), done once it is, also where it failed.
  Future<void> _lastSave = Future.value();

  bool _disposed = false;

  /// The covers' size, in pixels: as the largest the app asks the server for, a phone's player and an album's page.
  static const coverSize = 800;

  static const _songsFolder = 'songs';
  static const _coversFolder = 'covers';
  static const _lyricsFolder = 'lyrics';
  static const _folders = [_songsFolder, _coversFolder, _lyricsFolder];
  static const _indexFile = 'index.json';
  static const _unreadableIndexFile = 'index.unreadable.json';

  /// Every download, the latest asked for first.
  List<Download> get all => _downloads.values.toList().reversed.toList();

  /// The download of the album whose id is [id]; null where there is none.
  Download? ofAlbum(String id) => _downloads['album:$id'];

  /// The download of the playlist whose id is [id]; null where there is none.
  Download? ofPlaylist(String id) => _downloads['playlist:$id'];

  /// Whether the downloads wait, held where the user keeps them off mobile data.
  bool get held => _hold?.value ?? false;

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

  /// The file of the cover whose id is [coverId], where it is on the device, at [coverSize] pixels: an album's, a song's,
  /// a playlist's or an artist's picture ([artist]).
  File? coverFile(String coverId) => _existing(_coverFile(coverId));

  File? _existing(String file) => _files.contains(file) ? File('${directory.path}/$file') : null;

  /// The artist whose id is [id], of a download, as the server gave them, with their picture's id ([Artist.coverArt])
  /// where it is on the device; null where the downloads haven't got them.
  Artist? artist(String id) => _artists[id];

  /// The lyrics of the song whose id is [songId], downloaded with it; null where it has none, or they haven't come.
  Future<Lyrics?> lyrics(String songId) async {
    final file = _existing(_lyricsFile(songId));

    if (file == null) {
      return null;
    }

    try {
      return _lyrics(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } on Object catch (e) {
      _log.warning('lyrics unreadable', e);
      return null;
    }
  }

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

  /// Takes [download] off the device: the songs, covers, lyrics and artists no other download has.
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

  /// Fetches what the downloads lack, one thing at a time, until nothing is left, the server is out of reach, the
  /// downloads are held or they close. What fails is skipped until the server is back in reach.
  Future<void> _fetch() => _fetching ??= _fetchMissing().whenComplete(() => _fetching = null);

  Future<void> _fetchMissing() async {
    // As the app opens, once the server is known to be in reach: it has then answered, saying which ids it gives.
    if (await (_reachability?.settled ?? Future.value(true)) && !_disposed) {
      await _renameIds();
    }

    while (await (_reachability?.settled ?? Future.value(true)) && !_disposed && !held) {
      final missing = _missingSong() ?? _missingCover() ?? _missingLyrics() ?? _missingArtist();

      if (missing == null) {
        break;
      }

      try {
        await missing.fetch();
      } on Object catch (error) {
        // Closed meanwhile, its requests cut short ([close]).
        if (_disposed) {
          return;
        }

        _log.warning('download of ${missing.key}', error);
        _failed.add(missing.key);

        if (isNetworkFailure(error)) {
          _reachability?.lost(error);
        }
      }

      // Taken off meanwhile.
      await _forget();

      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// Whether [key] is neither there nor failed.
  bool _lacks(String key) => !_files.contains(key) && !_failed.contains(key);

  _Missing? _missingSong() {
    for (final download in _downloads.values) {
      for (final song in download.songs) {
        final file = _songFile(song.id);

        if (_lacks(file)) {
          return (key: file, fetch: () => _fetchSong(song, file));
        }
      }
    }

    return null;
  }

  _Missing? _missingCover() {
    for (final download in _downloads.values) {
      for (final cover in download.covers) {
        final file = _coverFile(cover);

        if (_lacks(file)) {
          return (key: file, fetch: () => _write(file, () => _server.coverArt(cover, size: coverSize)));
        }
      }
    }

    return null;
  }

  _Missing? _missingLyrics() {
    final lyricsOf = _lyricsOf;

    if (lyricsOf == null) {
      return null;
    }

    for (final download in _downloads.values) {
      for (final song in download.songs) {
        final file = _lyricsFile(song.id);

        if (_lacks(file)) {
          // A song with none has a file all the same, which says so, to be asked once.
          return (
            key: file,
            fetch: () => _write(file, () async => utf8.encode(jsonEncode(_lyricsJson(await lyricsOf(song))))),
          );
        }
      }
    }

    return null;
  }

  _Missing? _missingArtist() {
    for (final id in _wantedArtists()) {
      final key = _artistKey(id);

      if (!_artists.containsKey(id) && !_failed.contains(key)) {
        return (key: key, fetch: () => _fetchArtist(id));
      }
    }

    return null;
  }

  /// The song's file, as the server streams it in the quality picked for downloads, written beside where it goes and
  /// moved there once whole.
  Future<void> _fetchSong(Song song, String file) async {
    final url = _server.downloadUrl(song.id, maxBitRate: _maxBitRate?.call());
    final response = await _http.send(http.Request('GET', url)).timeout(_wait);

    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw ServerError('HTTP ${response.statusCode}');
    }

    final type = response.headers['content-type'] ?? '';

    // A Subsonic server refuses with a 200 all the same, its error in place of the song (as JSON, which the app asks
    // for), and a proxy may answer with a page of its own: neither is a song to keep.
    if (type.contains('json') || type.contains('xml') || type.startsWith('text/')) {
      final answer = utf8.decode(await http.ByteStream(response.stream.timeout(_wait)).toBytes(), allowMalformed: true);

      throw ServerError('no song for ${song.id}: ${answer.length > 200 ? answer.substring(0, 200) : answer}');
    }

    final part = File('${directory.path}/$file.part');

    try {
      // A stream that stops coming fails, rather than leaving the downloads waiting on it.
      await response.stream.timeout(_wait).pipe(part.openWrite());
      await part.rename('${directory.path}/$file');
      _files.add(file);
    } on Object {
      if (await part.exists()) {
        await part.delete();
      }

      rethrow;
    }
  }

  /// The artist whose id is [id], as the server gives them, with their picture: the server's, or else, where it has
  /// none, the one [_artistPicture] finds. Without one, where neither has one, or it can't be had.
  Future<void> _fetchArtist(String id) async {
    final (artist, _) = await _server.artist(id).timeout(_wait);

    String? picture;

    try {
      if (artist.coverArt case final cover?) {
        await _write(_coverFile(cover), () => _server.coverArt(cover, size: coverSize));
        picture = cover;
      } else if ((artist.musicBrainzId, _artistPicture) case (final musicBrainzId?, final artistPicture?)) {
        picture = await _fetchFoundPicture(artist, musicBrainzId, artistPicture);
      }
    } on ServerError catch (e) {
      _log.warning('no picture of ${artist.name}', e);
      picture = null;
    }

    _artists[id] = Artist(
      id: id,
      name: artist.name,
      coverArt: picture,
      musicBrainzId: artist.musicBrainzId,
      albumCount: artist.albumCount,
    );
    await _save();
  }

  /// The picture of [artist] that [artistPicture] finds (fanart.tv's), as the cover `fanart:` and their MusicBrainz id
  /// ([musicBrainzId]); none where it finds none. Failing for the network, it fails as anything else would, to be asked
  /// again, rather than as the media server out of reach: the picture comes from elsewhere.
  Future<String?> _fetchFoundPicture(
    Artist artist,
    String musicBrainzId,
    Future<Uri?> Function(Artist artist) artistPicture,
  ) async {
    try {
      final url = await artistPicture(artist).timeout(_wait);

      if (url == null) {
        return null;
      }

      final picture = 'fanart:$musicBrainzId';

      await _write(_coverFile(picture), () async {
        final response = await _http.get(url).timeout(_wait);

        if (response.statusCode != 200) {
          throw ServerError('HTTP ${response.statusCode}');
        }

        return response.bodyBytes;
      });

      return picture;
    } on Object catch (e) {
      if (!isNetworkFailure(e)) {
        rethrow;
      }

      throw Exception('picture of ${artist.name}: $e');
    }
  }

  /// Gives what the downloads keep the ids the server has for it now ([MediaServer.currentId]), where it has given its
  /// items new ones since they came, as Navidrome 0.64 did: the index's, so that they match the server's again, and the
  /// files' names. The index goes first, with the files to rename in it ([_renames]), then the files: closed meanwhile,
  /// the downloads go on with them as they open again, rather than take them for files no download wants.
  Future<void> _renameIds() async {
    var changed = false;

    String current(String id, {bool cover = false}) {
      final current = _server.currentId(id, cover: cover);
      changed |= current != id;

      return current;
    }

    final downloads = [for (final download in _downloads.values) _renamed(download, current)];
    final artists = [for (final artist in _artists.values) _renamedArtist(artist, current)];

    if (!changed) {
      return;
    }

    void rename(String from, String to) {
      if (from != to && _files.contains(from)) {
        _renames[from] = to;
      }
    }

    for (final download in _downloads.values) {
      for (final song in download.songs) {
        rename(_songFile(song.id), _songFile(current(song.id)));
        rename(_lyricsFile(song.id), _lyricsFile(current(song.id)));
      }

      for (final cover in download.covers) {
        rename(_coverFile(cover), _coverFile(current(cover, cover: true)));
      }
    }

    for (final artist in _artists.values) {
      if (artist.coverArt case final picture?) {
        rename(_coverFile(picture), _coverFile(current(picture, cover: true)));
      }
    }

    _downloads.clear();

    // Two that are now one (downloaded again meanwhile, by its new id) are the one asked for later.
    for (final download in downloads) {
      _downloads
        ..remove(download._key)
        ..[download._key] = download;
    }

    _artists
      ..clear()
      ..addEntries([for (final artist in artists) MapEntry(artist.id, artist)]);
    await _save();
    await _finishRenames();

    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Gives the files [_renames] holds their new names, and forgets them once they have them. One downloaded again
  /// meanwhile, under its new name, stays rather than the one from before.
  Future<void> _finishRenames() async {
    if (_renames.isEmpty) {
      return;
    }

    for (final MapEntry(key: from, value: to) in _renames.entries.toList()) {
      _renames.remove(from);

      if (!_files.remove(from)) {
        continue; // renamed before the downloads closed
      }

      try {
        final file = File('${directory.path}/$from');

        if (_files.contains(to)) {
          await file.delete();
        } else {
          await file.rename('${directory.path}/$to');
          _files.add(to);
        }
      } on FileSystemException catch (e) {
        // To come again, if it is gone.
        _log.warning('download not renamed', e);
      }
    }

    await _save();
  }

  /// Writes what [bytes] gives as [file], beside where it goes, and moves it there.
  Future<void> _write(String file, Future<List<int>> Function() bytes) async {
    final content = await bytes().timeout(_wait);
    final part = File('${directory.path}/$file.part');

    await part.writeAsBytes(content, flush: true);
    await part.rename('${directory.path}/$file');
    _files.add(file);
  }

  /// How long the downloads wait for the server, for an answer or for more of a file.
  static const _wait = Duration(seconds: 30);

  /// The ids of the downloads' artists: the albums', and each song's first.
  Set<String> _wantedArtists() => {
    for (final download in _downloads.values) ...[
      ?download.album?.artistId,
      for (final song in download.songs) ?song.artistId,
    ],
  };

  /// Every file the downloads want, those still to take their new names and those kept too.
  Set<String> _wanted() => {..._renames.keys, ..._kept, ..._wantedByDownloads()};

  /// The files of the downloads and of their artists.
  Set<String> _wantedByDownloads() => {
    for (final download in _downloads.values) ...[
      for (final song in download.songs) ...[_songFile(song.id), _lyricsFile(song.id)],
      for (final cover in download.covers) _coverFile(cover),
    ],
    for (final artist in _artists.values)
      if (artist.coverArt case final picture?) _coverFile(picture),
  };

  /// Forgets the artists no download has, and deletes the files none wants.
  Future<void> _forget() async {
    final artists = _wantedArtists();
    final before = (_artists.length, _kept.length);

    _artists.removeWhere((id, _) => !artists.contains(id));
    // A kept file a download wants is its own from now.
    _kept.removeAll(_wantedByDownloads());

    if ((_artists.length, _kept.length) != before) {
      await _save();
    }

    final wanted = _wanted();

    for (final file in _files.difference(wanted).toList()) {
      await _delete(file);
    }

    _failed.removeWhere((key) => !wanted.contains(key) && !artists.map(_artistKey).contains(key));
  }

  Future<void> _delete(String file) async {
    _files.remove(file);

    try {
      await File('${directory.path}/$file').delete();
    } on FileSystemException {
      // already gone
    }
  }

  /// Writes the index beside where it goes, and moves it there, so that one cut short never leaves half an index: after
  /// the write before, so that two never write over each other.
  Future<void> _save() {
    final saved = _lastSave.then((_) => _writeIndex());

    _lastSave = saved.catchError((Object _) {});

    return saved;
  }

  Future<void> _writeIndex() async {
    final part = File('${directory.path}/$_indexFile.part');

    await part.writeAsString(
      jsonEncode({
        'downloads': [for (final download in _downloads.values) _downloadJson(download)],
        'artists': [for (final artist in _artists.values) artist.toJson()],
        if (_renames.isNotEmpty) 'renames': _renames,
        if (_kept.isNotEmpty) 'kept': _kept.toList(),
      }),
      flush: true,
    );
    await part.rename('${directory.path}/$_indexFile');
  }

  /// The server in reach again, or the downloads no longer held: what failed is tried again, and what is missing
  /// comes.
  void _resume() {
    if ((_reachability?.value ?? true) && !held) {
      _failed.clear();
      unawaited(_fetch());
    }

    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Tries again what failed to come.
  void retry() {
    _failed.clear();
    notifyListeners();
    unawaited(_fetch());
  }

  static String _songFile(String id) => '$_songsFolder/${_name(id)}';
  static String _coverFile(String id) => '$_coversFolder/${_name(id)}';
  static String _lyricsFile(String id) => '$_lyricsFolder/${_name(id)}';
  static String _artistKey(String id) => 'artists/${_name(id)}';

  /// A file's name for an id, which may hold any character: base 64, as URLs have it, without its padding.
  static String _name(String id) => base64Url.encode(utf8.encode(id)).replaceAll('=', '');

  /// Disposes of them ([dispose]), and completes once what was under way has stopped: the thing coming, which fails as
  /// its requests are cut short (its client closed, and the media server's), and the index being written. Opened again
  /// before, on the same folder, they would write over each other.
  Future<void> close() async {
    dispose();
    // What failed there has said so already.
    await _fetching?.catchError((Object _) {});
    await _lastSave;
  }

  @override
  void dispose() {
    _disposed = true;
    _reachability?.removeListener(_resume);
    _hold?.removeListener(_resume);
    _http.close();
    super.dispose();
  }
}

// The index, as JSON: what the app needs of each album, playlist and song to show and play them.

Map<String, Object?> _downloadJson(Download download) => {
  if (download.album case final album?) 'album': album.toJson(),
  if (download.playlist case final playlist?) 'playlist': playlist.toJson(),
  'songs': [for (final song in download.songs) song.toJson()],
  'added': download.added.millisecondsSinceEpoch,
};

Download _download(Map<String, dynamic> json) {
  final songs = [for (final song in json['songs'] as List) Song.fromJson(song as Map<String, dynamic>)];
  final added = DateTime.fromMillisecondsSinceEpoch((json['added'] as num).toInt());

  return switch ((json['album'], json['playlist'])) {
    (final Map<String, dynamic> album, _) => Download.album(Album.fromJson(album), songs, added: added),
    (_, final Map<String, dynamic> playlist) => Download.playlist(Playlist.fromJson(playlist), songs, added: added),
    _ => throw const FormatException('neither an album nor a playlist'),
  };
}

/// The id the server has now for one it gave, as [MediaServer.currentId] says.
typedef _CurrentId = String Function(String id, {bool cover});

// What a download keeps, with the ids [_CurrentId] gives for the ones it holds: anything else as the index keeps it.
// A genre's id is its name, on Subsonic, and stays.

Download _renamed(Download download, _CurrentId current) {
  final songs = List<Song>.unmodifiable([for (final song in download.songs) _renamedSong(song, current)]);

  return switch ((download.album, download.playlist)) {
    (final album?, _) => Download.album(
      Album.fromJson({
        ...album.toJson(),
        'id': current(album.id),
        'artistId': _currentOrNull(album.artistId, current),
        'coverArt': _currentOrNull(album.coverArt, current, cover: true),
      }),
      songs,
      added: download.added,
    ),
    (_, final playlist?) => Download.playlist(
      Playlist.fromJson({
        ...playlist.toJson(),
        'id': current(playlist.id),
        'coverArt': _currentOrNull(playlist.coverArt, current, cover: true),
      }),
      songs,
      added: download.added,
    ),
    _ => download,
  };
}

Song _renamedSong(Song song, _CurrentId current) => Song.fromJson({
  ...song.toJson(),
  'id': current(song.id),
  'albumId': _currentOrNull(song.albumId, current),
  'coverArt': _currentOrNull(song.coverArt, current, cover: true),
  'artists': [for (final artist in song.artists) _renamedArtist(artist, current).toJson()],
});

/// Its picture's id too, the server's cover, which a picture from elsewhere (`fanart:`) isn't.
Artist _renamedArtist(Artist artist, _CurrentId current) => Artist.fromJson({
  ...artist.toJson(),
  'id': current(artist.id),
  'coverArt': _currentOrNull(artist.coverArt, current, cover: true),
});

String? _currentOrNull(String? id, _CurrentId current, {bool cover = false}) =>
    id == null ? null : current(id, cover: cover);

/// Lyrics as JSON, each line with when it starts, where they're synced; none, as no lines.
Map<String, Object?> _lyricsJson(Lyrics? lyrics) => {
  'provider': lyrics?.provider,
  'lines': [
    for (final line in lyrics?.lines ?? const <LyricLine>[]) {'text': line.text, 'startMs': line.start?.inMilliseconds},
  ],
};

/// The lyrics [json] holds; null for none.
Lyrics? _lyrics(Map<String, dynamic> json) {
  final lines = [
    for (final line in json['lines'] as List)
      LyricLine(
        (line as Map<String, dynamic>)['text'] as String,
        start: switch (line['startMs']) {
          final num ms => Duration(milliseconds: ms.toInt()),
          _ => null,
        },
      ),
  ];

  return lines.isEmpty ? null : Lyrics(lines, provider: json['provider'] as String?);
}
