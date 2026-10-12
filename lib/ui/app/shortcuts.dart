import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services.dart';
import '../player/player_controls.dart';
import '../widgets/directional_navigation.dart';
import 'page_area.dart';

/// Keyboard shortcuts for playback, on every page: space plays or pauses what the now-playing bar
/// shows. Not while typing: with a text field focused, the key goes on to it.
class PlaybackShortcuts extends StatelessWidget {
  const PlaybackShortcuts({required this.child, this.mediaKeys = false, super.key});

  final Widget child;

  /// Whether the media keys (play/pause, next, previous: a TV remote's, a keyboard's) are taken here
  /// too. Where a system media session takes them (MPRIS on Linux), they never come as keys; where
  /// there is none (Android, for now), they do.
  final bool mediaKeys;

  @override
  Widget build(BuildContext context) {
    final connect = ServicesScope.of(context).connect;

    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
        if (mediaKeys) ...{
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause): const PlayPauseIntent(whileTyping: true),
          const SingleActivator(LogicalKeyboardKey.mediaTrackNext): const _NextIntent(),
          const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): const _PreviousIntent(),
        },
      },
      child: Actions(
        actions: {
          PlayPauseIntent: _PlayPauseAction(() => runCommand(context, connect.toggle)),
          _NextIntent: CallbackAction<_NextIntent>(onInvoke: (_) => runCommand(context, connect.next)),
          _PreviousIntent: CallbackAction<_PreviousIntent>(onInvoke: (_) => runCommand(context, connect.previous)),
        },
        child: child,
      ),
    );
  }
}

class PlayPauseIntent extends Intent {
  const PlayPauseIntent({this.whileTyping = false});

  /// A media key, which a text field doesn't take, so it works while typing too.
  final bool whileTyping;
}

class _NextIntent extends Intent {
  const _NextIntent();
}

class _PreviousIntent extends Intent {
  const _PreviousIntent();
}

class _PlayPauseAction extends Action<PlayPauseIntent> {
  _PlayPauseAction(this._playPause);

  final VoidCallback _playPause;

  /// Disabled while typing, so that the key isn't taken from the text field.
  @override
  bool isEnabled(PlayPauseIntent intent) {
    if (intent.whileTyping) {
      return true;
    }

    final focused = FocusManager.instance.primaryFocus?.context;

    return focused == null || !_inTextField(focused);
  }

  @override
  Object? invoke(PlayPauseIntent intent) {
    _playPause();

    return null;
  }
}

/// The arrows up and down (a TV remote's D-pad) leave a text field for the one above or below. By
/// default they stay in it, moving the caret, and a remote has no other way out. Left and right
/// still move the caret, but on a TV, where they leave it too: there the keyboard, which takes the
/// D-pad, is open while typing, and with it closed the caret is out of sight.
class TextFieldArrowShortcuts extends StatelessWidget {
  const TextFieldArrowShortcuts({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: {
      const SingleActivator(LogicalKeyboardKey.arrowUp): const DirectionalFocusIntent(
        TraversalDirection.up,
        ignoreTextFields: false,
      ),
      const SingleActivator(LogicalKeyboardKey.arrowDown): const DirectionalFocusIntent(
        TraversalDirection.down,
        ignoreTextFields: false,
      ),
      if (DirectionalNavigation.of(context)) ...const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
          TraversalDirection.left,
          ignoreTextFields: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
          TraversalDirection.right,
          ignoreTextFields: false,
        ),
      },
    },
    child: child,
  );
}

/// Whether [focused], the focused widget's context, is in a text field, which takes the keys typed.
bool _inTextField(BuildContext focused) =>
    focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null;

/// The key '/' goes to the search bar, as on many sites, wherever the focus is in the home: [onSearch]. By the
/// character, which some keyboards type with Shift (Spanish, Shift+7), others on a key of their own or the number pad.
/// Not while typing: with a text field focused, the key goes on to it.
class SearchShortcut extends StatelessWidget {
  const SearchShortcut({required this.onSearch, required this.child, super.key});

  final VoidCallback onSearch;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {CharacterActivator('/'): _SearchIntent()},
    child: Actions(actions: {_SearchIntent: _SearchAction(onSearch)}, child: child),
  );
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _SearchAction extends Action<_SearchIntent> {
  _SearchAction(this._search);

  final VoidCallback _search;

  /// Disabled while typing, so that the key isn't taken from the text field.
  @override
  bool isEnabled(_SearchIntent intent) {
    final focused = FocusManager.instance.primaryFocus?.context;

    return focused == null || !_inTextField(focused);
  }

  @override
  Object? invoke(_SearchIntent intent) {
    _search();

    return null;
  }
}

/// The arrow left and Esc go back from a page with a back arrow (an album's, an artist's, the queue...), as that arrow
/// does, whatever on the page has the focus: on a phone, since a wide screen's home takes them first
/// ([HistoryShortcuts]). Not while typing, where the arrow moves the caret and Esc leaves the text field
/// ([UnfocusShortcut]), nor, the arrow, on a TV, where the D-pad's left moves the focus and the remote has a back button
/// of its own.
class BackShortcut extends StatelessWidget {
  const BackShortcut({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.arrowLeft): _BackIntent(),
      SingleActivator(LogicalKeyboardKey.escape): _BackIntent(onTelevision: true),
    },
    child: Actions(actions: {_BackIntent: _BackAction()}, child: child),
  );
}

class _BackIntent extends Intent {
  const _BackIntent({this.onTelevision = false});

  /// Whether it goes back on a TV too: from a key the D-pad doesn't move the focus with.
  final bool onTelevision;
}

class _BackAction extends Action<_BackIntent> {
  /// The page the focus is on, when [intent] goes back from it: one pushed as a [MaterialPageRoute], whose app bar has a
  /// back arrow. The full-screen player and the cover, pushed otherwise, close with a button of their own (and Esc)
  /// instead, and a sheet, a menu or a dialog has none: Esc goes on to close them, as ever.
  ModalRoute<Object?>? _page(_BackIntent intent) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null || _inTextField(focused) || (!intent.onTelevision && DirectionalNavigation.of(focused))) {
      return null;
    }

    final route = ModalRoute.of(focused);

    // As the app bar decides on its back arrow.
    return route is MaterialPageRoute && route.isCurrent && route.impliesAppBarDismissal ? route : null;
  }

  /// Disabled elsewhere, so that the key goes on: to the text field, to move the focus, or to take it off.
  @override
  bool isEnabled(_BackIntent intent) => _page(intent) != null;

  @override
  Object? invoke(_BackIntent intent) {
    _page(intent)?.navigator?.maybePop();

    return null;
  }
}

/// On a wide screen, the arrows left and right go back and forward through the pages of the home's page area, as its
/// top bar's arrows do, wherever the focus is in the home, and Esc goes back as the arrow left does. Not while typing,
/// where the arrows move the caret and Esc leaves the text field ([UnfocusShortcut]), nor, the arrows, on a TV, where
/// they move the focus and the remote has a back button of its own.
class HistoryShortcuts extends StatelessWidget {
  const HistoryShortcuts({required this.history, required this.child, super.key});

  final PageHistory history;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.arrowLeft): _HistoryIntent(forward: false),
      SingleActivator(LogicalKeyboardKey.arrowRight): _HistoryIntent(forward: true),
      SingleActivator(LogicalKeyboardKey.escape): _HistoryIntent(forward: false, onTelevision: true),
    },
    child: Actions(actions: {_HistoryIntent: _HistoryAction(history)}, child: child),
  );
}

class _HistoryIntent extends Intent {
  const _HistoryIntent({required this.forward, this.onTelevision = false});

  final bool forward;

  /// Whether it goes on a TV too: from a key the D-pad doesn't move the focus with.
  final bool onTelevision;
}

class _HistoryAction extends Action<_HistoryIntent> {
  _HistoryAction(this._history);

  final PageHistory _history;

  /// Disabled with nowhere to go, so that the key goes on: to the text field, or to move the focus.
  @override
  bool isEnabled(_HistoryIntent intent) {
    final focused = FocusManager.instance.primaryFocus?.context;

    if (focused == null || _inTextField(focused) || (!intent.onTelevision && DirectionalNavigation.of(focused))) {
      return false;
    }

    return intent.forward ? _history.canGoForward : _history.canGoBack;
  }

  @override
  Object? invoke(_HistoryIntent intent) {
    if (intent.forward) {
      _history.forward();
    } else {
      _history.back();
    }

    return null;
  }
}

/// Esc takes the focus off what has it: the tint or the ring the theme gives it goes, and a text field
/// lets go of the keys, space among them. With nothing focused, Esc goes on, closing a sheet as ever;
/// the pages that Esc closes, and those it goes back from ([BackShortcut], [HistoryShortcuts]), take it first.
class UnfocusShortcut extends StatelessWidget {
  const UnfocusShortcut({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): _UnfocusIntent()},
    child: Actions(actions: {_UnfocusIntent: _UnfocusAction()}, child: child),
  );
}

class _UnfocusIntent extends Intent {
  const _UnfocusIntent();
}

class _UnfocusAction extends Action<_UnfocusIntent> {
  /// Disabled when only a page or a sheet has the focus, nothing on it.
  @override
  bool isEnabled(_UnfocusIntent intent) {
    final focused = FocusManager.instance.primaryFocus;

    return focused != null && focused is! FocusScopeNode;
  }

  @override
  Object? invoke(_UnfocusIntent intent) {
    FocusManager.instance.primaryFocus?.unfocus();

    return null;
  }
}
