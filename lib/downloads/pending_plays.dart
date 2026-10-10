import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../server/reachability.dart';

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
      debugPrint('pending plays unreadable: $e');
    }

    return PendingPlays._(file, plays);
  }

  final File file;
  final List<PendingPlay> _plays;
  bool _sending = false;

  List<PendingPlay> get plays => List.unmodifiable(_plays);

  /// Keeps a play of the song whose id is [songId], which started at [time].
  Future<void> add(String songId, DateTime time) async {
    _plays.add((songId: songId, time: time));
    await _save();
  }

  /// Gives each play to [count], the first first, dropping it once counted, or once the server refused it (a song
  /// gone from it, say); one that fails for the network stops them, the rest kept for the next time. Whether they all
  /// went.
  Future<bool> send(Future<void> Function(PendingPlay play) count) async {
    if (_sending) {
      return false;
    }

    _sending = true;

    try {
      while (_plays.isNotEmpty) {
        try {
          await count(_plays.first);
        } on Object catch (error) {
          if (isNetworkFailure(error)) {
            return false;
          }

          debugPrint('a play not counted: $error');
        }

        _plays.removeAt(0);
        await _save();
      }

      return true;
    } finally {
      _sending = false;
    }
  }

  /// Writes them beside [file], and moves them over it, so that it is never half written.
  Future<void> _save() async {
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
