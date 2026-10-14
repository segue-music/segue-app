import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'mixes.dart';
import 'pictures/fanart_tv.dart';
import 'server/models.dart';
import 'server/reachability.dart';
import 'server/server.dart';

final _log = Logger('HomeCache');

/// What the home showed, kept on the device, for it to show at once as the app opens, while it comes anew from the
/// media server: its rows of albums, as the server last listed them, and its mixes, picked the time before, the next
/// time's picked meanwhile. Only what the server said: out of reach ([Reachability]), what the downloads say stays out.
/// One file for each user on each server, written whole under another name and moved over it, as the downloads' index
/// is.
class HomeCache {
  HomeCache._(this.file, this._reachability, this._albums, this._shownMixes) : _nextMixes = _shownMixes;

  /// The cache kept in [file]; an empty one where there is none, or it can't be read.
  static Future<HomeCache> open(File file, {Reachability? reachability}) async {
    final albums = <AlbumOrder, List<Album>>{};

    List<KeptMix>? mixes;

    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

        for (final MapEntry(:key, :value) in (json['albums'] as Map<String, dynamic>? ?? const {}).entries) {
          if (AlbumOrder.values.asNameMap()[key] case final order?) {
            albums[order] = [for (final album in value as List) Album.fromJson(album as Map<String, dynamic>)];
          }
        }

        mixes = switch (json['mixes']) {
          final List<Object?> list => [for (final mix in list) _keptMix(mix as Map<String, dynamic>)],
          _ => null,
        };
      }
    } on Object catch (e) {
      _log.warning('home cache unreadable', e);
      albums.clear();
      mixes = null;
    }

    return HomeCache._(file, reachability, albums, mixes);
  }

  final File file;
  final Reachability? _reachability;
  final Map<AlbumOrder, List<Album>> _albums;

  /// The mixes kept as the app opened, which the home shows this session; null, none were.
  final List<KeptMix>? _shownMixes;

  /// The mixes the home shows the next session.
  List<KeptMix>? _nextMixes;

  /// Whether those are picked, or being picked.
  bool _picking = false;

  /// Their picking; null, none yet.
  Future<void>? _picked;

  /// The writes, one after another.
  Future<void> _writing = Future.value();

  bool _closed = false;

  /// The albums of [order] the home showed last; null, none kept.
  List<Album>? albums(AlbumOrder order) => _albums[order];

  /// [listed], the albums of [order] as the server lists them now, kept for the next time; or [shown], where they are
  /// the same, so that the row showing those stays as it is (where it was scrolled to, the focus on it). Not kept where
  /// the downloads gave them, the server out of reach.
  Future<List<Album>> keepAlbums(AlbumOrder order, Future<List<Album>> listed, {List<Album>? shown}) async {
    final albums = await listed;

    if (!(_reachability?.value ?? true)) {
      return albums;
    }

    final json = _json(albums);

    if (json != _json(_albums[order])) {
      _albums[order] = albums;
      unawaited(_write());
    }

    return shown != null && _json(shown) == json ? shown : albums;
  }

  /// The mixes the home shows: those kept as the app opened, which come at once, or else new ones. Once a session, with
  /// the server in reach, the next session's are picked meanwhile and kept: others, or the new ones shown.
  SuggestedMixes mixes(MediaServer server, {FanartTv? fanartTv}) {
    final kept = _shownMixes;
    final shown = kept == null
        ? SuggestedMixes(server, fanartTv: fanartTv)
        : SuggestedMixes.kept(server, kept, fanartTv: fanartTv);

    if (!_picking) {
      _picking = true;
      unawaited(_picked = _pickNextMixes(() => kept == null ? shown : SuggestedMixes(server, fanartTv: fanartTv)));
    }

    return shown;
  }

  Future<void> _pickNextMixes(SuggestedMixes Function() pick) async {
    // Out of reach, they would be of the downloads alone: for the home to pick again, as the server is back.
    if (!await (_reachability?.settled ?? Future.value(true))) {
      _picking = false;
      return;
    }

    try {
      final next = await pick().keep();

      if (next.isNotEmpty && (_reachability?.value ?? true)) {
        _nextMixes = next;
        await _write();
        return;
      }
    } on Object catch (e) {
      _log.warning('next mixes not picked', e);
    }

    _picking = false;
  }

  /// Writes no more, as the session ends.
  void close() => _closed = true;

  /// Once what it picks and writes is done.
  @visibleForTesting
  Future<void> get idle async {
    await _picked;
    await _writing;
  }

  Future<void> _write() => _writing = _writing.then((_) => _writeNow());

  Future<void> _writeNow() async {
    if (_closed) {
      return;
    }

    try {
      await file.parent.create(recursive: true);

      final part = File('${file.path}.part');

      await part.writeAsString(
        jsonEncode({
          'albums': {
            for (final MapEntry(key: order, value: albums) in _albums.entries)
              order.name: [for (final album in albums) album.toJson()],
          },
          if (_nextMixes case final mixes?) 'mixes': [for (final mix in mixes) _keptMixJson(mix)],
        }),
        flush: true,
      );
      await part.rename(file.path);
    } on Object catch (e) {
      _log.warning('home not kept', e);
    }
  }

  /// [albums] as JSON, to tell whether two lists say the same.
  static String? _json(List<Album>? albums) =>
      albums == null ? null : jsonEncode([for (final album in albums) album.toJson()]);
}

Map<String, Object?> _keptMixJson(KeptMix kept) => {
  ...switch (kept.mix) {
    LibraryMix() => {'library': true},
    GenreMix(:final genre) => {'genre': genre.toJson()},
    DecadeMix(:final decade) => {'decade': decade},
  },
  'firstSongs': [for (final song in kept.firstSongs) song.toJson()],
  if (kept.picture case (:final artist, :final picture))
    'picture': {'artist': artist.toJson(), 'url': picture?.toString()},
};

KeptMix _keptMix(Map<String, dynamic> json) => (
  mix: switch (json) {
    {'library': true} => const LibraryMix(),
    {'genre': final Map<String, dynamic> genre} => GenreMix(Genre.fromJson(genre)),
    {'decade': final num decade} => DecadeMix(decade.toInt()),
    _ => throw const FormatException('neither the library, a genre nor a decade'),
  },
  firstSongs: [for (final song in json['firstSongs'] as List) Song.fromJson(song as Map<String, dynamic>)],
  picture: switch (json['picture']) {
    final Map<String, dynamic> picture => (
      artist: Artist.fromJson(picture['artist'] as Map<String, dynamic>),
      picture: switch (picture['url']) {
        final String url => Uri.parse(url),
        _ => null,
      },
    ),
    _ => null,
  },
);
