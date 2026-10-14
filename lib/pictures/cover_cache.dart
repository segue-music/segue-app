import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../server/server.dart';

final _log = Logger('CoverCache');

/// The covers the app shows, and the pictures from elsewhere (an artist's from fanart.tv), kept on the device as they
/// come, so that they show at once the next time, the media server out of reach too: in a folder of the app's cache for
/// each user on each server, from which the oldest go past [maxBytes]. One older than [refreshAfter] shows, and comes
/// again meanwhile, for the next time: a server may change a cover and keep its id (Jellyfin's).
class CoverCache {
  CoverCache(
    this.directory, {
    http.Client? client,
    this.maxBytes = 100 * 1024 * 1024,
    this.refreshAfter = const Duration(days: 30),
  }) : _http = client ?? http.Client();

  final Directory directory;
  final http.Client _http;

  /// How much the files may take, all together, after [trim].
  final int maxBytes;

  /// How old a file is when it comes again.
  final Duration refreshAfter;

  /// How many files have been written, which tells their parts apart, as two of the same picture may be.
  int _written = 0;

  /// The cover [id], [size] pixels across, as [server] gives it ([MediaServer.coverArt]).
  ImageProvider cover(MediaServer server, String id, {required int size}) =>
      _KeptImage(this, _file('cover $id $size'), () => server.coverArt(id, size: size));

  /// The picture at [url].
  ImageProvider picture(Uri url) => _KeptImage(this, _file('picture $url'), () => _download(url));

  /// A file's name for [key], which may hold any character, and be long (a URL): its SHA-256, in hex.
  File _file(String key) => File('${directory.path}/${sha256.convert(utf8.encode(key))}');

  Future<Uint8List> _download(Uri url) async {
    final response = await _http.get(url);

    if (response.statusCode != 200 || !(response.headers['content-type'] ?? '').startsWith('image/')) {
      throw HttpException('no picture (HTTP ${response.statusCode})', uri: url);
    }

    return response.bodyBytes;
  }

  /// The image kept in [file], or else from [fetch], kept in it as it comes.
  Future<ui.Codec> _load(File file, Future<Uint8List> Function() fetch, ImageDecoderCallback decode) async {
    try {
      final stat = await file.stat();

      if (stat.type == FileSystemEntityType.file) {
        final codec = await decode(await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()));

        if (clock.now().difference(stat.modified) > refreshAfter) {
          unawaited(fetch().then((bytes) => _keep(file, bytes), onError: (Object _) {}));
        }

        return codec;
      }
    } on Object catch (e) {
      // One that can't be read, or isn't an image: from where it comes, again.
      _log.warning('kept picture unreadable', e);
    }

    final bytes = await fetch();

    unawaited(_keep(file, bytes));

    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  /// Keeps [bytes] in [file]: whole under another name, then under its own, so that none is ever read half written.
  Future<void> _keep(File file, Uint8List bytes) async {
    try {
      await directory.create(recursive: true);

      final part = File('${file.path}.${_written++}.part');

      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
    } on Object catch (e) {
      _log.warning('picture not kept', e);
    }
  }

  /// Deletes the oldest files past [maxBytes], and the parts left by an app that ended as it wrote them.
  Future<void> trim() async {
    try {
      if (!await directory.exists()) {
        return;
      }

      final files = <(File, FileStat)>[];

      await for (final entity in directory.list()) {
        if (entity is! File) {
          continue;
        }

        if (entity.path.endsWith('.part')) {
          await entity.delete();
        } else {
          files.add((entity, await entity.stat()));
        }
      }

      var size = files.fold(0, (size, file) => size + file.$2.size);
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));

      for (final (file, stat) in files) {
        if (size <= maxBytes) {
          break;
        }

        await file.delete();
        size -= stat.size;
      }
    } on Object catch (e) {
      _log.warning('pictures not trimmed', e);
    }
  }

  void close() => _http.close();
}

/// An image kept in a file of a [CoverCache], or else from where it comes; the same as another kept in the same file.
@immutable
class _KeptImage extends ImageProvider<_KeptImage> {
  const _KeptImage(this._cache, this.file, this._fetch);

  final CoverCache _cache;
  final File file;
  final Future<Uint8List> Function() _fetch;

  @override
  Future<_KeptImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_KeptImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _cache._load(file, _fetch, decode), scale: 1, debugLabel: file.path);

  @override
  bool operator ==(Object other) => other is _KeptImage && other.file.path == file.path;

  @override
  int get hashCode => file.path.hashCode;
}
