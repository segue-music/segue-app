import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../player/player.dart';
import '../../services.dart';

/// Tells, in a snack bar, of each song this device's player stopped on because it couldn't load it
/// (the media server couldn't give it, say). Play tries it again.
class FailedSongMessage extends StatefulWidget {
  const FailedSongMessage({required this.child, super.key});

  final Widget child;

  @override
  State<FailedSongMessage> createState() => _FailedSongMessageState();
}

class _FailedSongMessageState extends State<FailedSongMessage> {
  PlayerController? _player;

  /// Whether the player had stopped on a failed song at its last change: each failure is told once.
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = ServicesScope.of(context).player;

    if (player != _player) {
      _player?.removeListener(_changed);
      _player = player..addListener(_changed);
      _failed = player.failed;
    }
  }

  @override
  void dispose() {
    _player?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final player = _player!;
    final song = player.current;

    if (player.failed && !_failed && song != null) {
      final message = AppLocalizations.of(context).couldNotPlaySong(song.title);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }

    _failed = player.failed;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
