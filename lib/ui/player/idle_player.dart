import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../connect/connect.dart';
import '../../device.dart';
import '../../services.dart';
import '../widgets/directional_navigation.dart';
import 'player_page.dart';

/// On a TV, while this device plays, the full-screen player comes by itself as the remote is left alone a while
/// ([after]), as a screen saver would: what plays, its cover big on its color and its lyrics, moving slowly about so as
/// not to mark the screen ([TelevisionControls]), rather than the page the music was picked on, which stays under it.
/// Until then the screen stays on, for the player to come before the system's screen saver, which may start sooner.
/// Music on another device leaves the TV as the system has it: kept on, it would show the app for hours to no one, the
/// music playing elsewhere.
class IdlePlayer extends StatefulWidget {
  const IdlePlayer({required this.child, super.key});

  final Widget child;

  /// How long the remote is left alone before the player comes.
  static const after = Duration(minutes: 3);

  @override
  State<IdlePlayer> createState() => _IdlePlayerState();
}

class _IdlePlayerState extends State<IdlePlayer> {
  /// What plays, on a TV; none elsewhere.
  ConnectController? _connect;

  /// Whether this device plays.
  bool _playing = false;

  /// Until the player comes, from the last key; once it has come, none until the next.
  Timer? _idle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final connect = context.television ? ServicesScope.of(context).connect : null;

    if (connect == _connect) {
      return;
    }

    if (_connect == null) {
      HardwareKeyboard.instance.addHandler(_pressed);
      GestureBinding.instance.pointerRouter.addGlobalRoute(_pointed);
    } else {
      _connect!.removeListener(_follow);
    }

    if (connect == null) {
      _stopWatching();
    }

    _connect = connect;
    connect?.addListener(_follow);
    _playing = _playsHere();
    _wait();
  }

  @override
  void dispose() {
    _connect?.removeListener(_follow);

    if (_connect != null) {
      _stopWatching();
    }

    _idle?.cancel();
    super.dispose();
  }

  void _stopWatching() {
    HardwareKeyboard.instance.removeHandler(_pressed);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointed);
  }

  bool _playsHere() => switch (_connect?.nowPlaying) {
    final now? => now.playing && now.device == null,
    null => false,
  };

  /// Starts or stops waiting, as this device starts playing or stops.
  void _follow() {
    final playing = _playsHere();

    if (playing != _playing) {
      setState(() => _playing = playing);
      _wait();
    }
  }

  /// Waits for the remote to be left alone, from now, while this device plays.
  void _wait() {
    _idle?.cancel();
    _idle = _playing ? Timer(IdlePlayer.after, _bringPlayer) : null;
  }

  /// Any key, as any pointer, starts the wait over: the remote's, a keyboard's, the TV's own buttons'.
  bool _pressed(KeyEvent event) {
    _wait();

    return false;
  }

  void _pointed(PointerEvent event) => _wait();

  /// Brings the full-screen player, unless the keyboard is up: someone types on it, with the remote, whose keys go to
  /// the keyboard rather than to the app.
  void _bringPlayer() {
    if (!mounted || !_playing) {
      return;
    }

    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      _wait();
      return;
    }

    PlayerPage.show(context);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      if (_playing) const KeepScreenOn(child: SizedBox.shrink()),
    ],
  );
}
