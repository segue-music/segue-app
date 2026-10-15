import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import '../server/reachability.dart';
import '../server/server.dart';

final _log = Logger('PendingPlays');

/// A play this device made with the media server out of reach: of the song whose id is [songId], which started at
/// [time].
typedef PendingPlay = ({String songId, DateTime time});

/// The plays this device made with the media server out of reach, kept in [file] until it is back, when they go to it
/// ([send]) in the order they were made, so that its most played count them as if it had been there.
class PendingPlays {
  PendingPlays._(this.file, this._plays);

  /// Those kept in [file], or none, where there is none or it can't be read.
  static Future<PendingPlays> open(File file) async {
    final plays = <PendingPlay>[];

    try {
      if (await file.exists()) {
        for (final play in jsonDecode(await file.readAsString()) as List) {
          final json = play as Map<String, dynamic>;

          plays.add((
            songId: json['songId'] as String,
            time: DateTime.fromMillisecondsSinceEpoch((json['time'] as num).toInt()),
          ));
        }
      }
    } on Object catch (e) {
      _log.warning('pending plays unreadable', e);
    }

    return PendingPlays._(file, plays);
  }

  final File file;
  final List<PendingPlay> _plays;
  bool _sending = false;

  /// The last write of [file] asked for ([_save]), done once it is, also where it failed.
  Future<void> _lastSave = Future.value();

  List<PendingPlay> get plays => List.unmodifiable(_plays);

  /// Keeps a play of the song whose id is [songId], which started at [time].
  Future<void> add(String songId, DateTime time) async {
    _plays.add((songId: songId, time: time));
    await _save();
  }

  /// Gives each play to [count], the first first, dropping it once counted, or once the server refused it (a song
  /// gone from it, say); one that fails for the network, or that the server fails at for now ([ServerError.isTemporary]),
  /// stops them, the rest kept for the next time. What stopped them, where something did; null once they all went, or
  /// while another send has them.
  Future<Object?> send(Future<void> Function(PendingPlay play) count) async {
    if (_sending) {
      return null;
    }

    _sending = true;

    try {
      while (_plays.isNotEmpty) {
        try {
          await count(_plays.first);
        } on Object catch (error) {
          if (isNetworkFailure(error) || (error is ServerError && error.isTemporary)) {
            return error;
          }

          _log.warning('a play not counted', error);
        }

        _plays.removeAt(0);
        await _save();
      }

      return null;
    } finally {
      _sending = false;
    }
  }

  /// Writes them beside [file], and moves them over it, so that it is never half written: after the write before, so
  /// that two never write over each other.
  Future<void> _save() {
    final saved = _lastSave.then((_) => _write());

    _lastSave = saved.catchError((Object _) {});

    return saved;
  }

  Future<void> _write() async {
    final part = File('${file.path}.part');

    await part.writeAsString(
      jsonEncode([
        for (final play in _plays) {'songId': play.songId, 'time': play.time.millisecondsSinceEpoch},
      ]),
      flush: true,
    );
    await part.rename(file.path);
  }
}
