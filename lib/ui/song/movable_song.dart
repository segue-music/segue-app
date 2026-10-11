import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// [items] with the one at [from] at [to] instead, the others closing up after it and making room for it.
List<T> withMove<T>(List<T> items, {required int from, required int to}) => [...items]
  ..removeAt(from)
  ..insert(to, items[from]);

/// Where the item at [index] goes as the one at [from] moves to [to] ([withMove]).
int indexAfterMove(int index, {required int from, required int to}) => switch (index) {
  _ when index == from => to,
  _ when from < index && index <= to => index - 1,
  _ when to <= index && index < from => index + 1,
  _ => index,
};

/// On a TV, which has no drag, a song of a list (the queue, a playlist) that the remote moves: picked to move from its
/// menu ([moving]), it is lifted over the others, as a song dragged elsewhere is, and the arrows up and down move it a
/// place at a time ([onStep], -1 up, 1 down), the list scrolling to keep it in sight. OK leaves it where it is
/// ([onDrop]), as does the focus going elsewhere, and Back, or Esc, puts it back ([onCancel]). Meanwhile a message at the
/// bottom says so, and the focus stays on it. Every song of such a list has one, moving or not, so that its line keeps
/// its place in the tree, and with it the focus, as it starts or stops moving; the list keeps it by its key as it moves
/// past the others.
class MovableSong extends StatefulWidget {
  const MovableSong({
    required this.moving,
    required this.onStep,
    required this.onDrop,
    required this.onCancel,
    required this.child,
    super.key,
  });

  final bool moving;
  final ValueChanged<int> onStep;
  final VoidCallback onDrop;
  final VoidCallback onCancel;

  /// The song's line.
  final Widget child;

  @override
  State<MovableSong> createState() => _MovableSongState();
}

class _MovableSongState extends State<MovableSong> {
  /// Around the song's line, which has the focus while it moves: the line's keys come up through it.
  final _focus = FocusNode(canRequestFocus: false, skipTraversal: true);

  /// Closes the message at the bottom, while it moves, where it still shows.
  VoidCallback? _closeHint;

  /// The keys that leave it where it is: the D-pad's center, and Enter.
  static final _drop = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  /// The keys that put it back: the remote's back button, and Esc.
  static final _cancel = {LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape};

  /// The keys that open its menu ([SongMenu]), which do nothing while it moves.
  static final _menu = {LogicalKeyboardKey.contextMenu, LogicalKeyboardKey.f10};

  @override
  void initState() {
    super.initState();

    if (widget.moving) {
      _start();
    }
  }

  @override
  void didUpdateWidget(MovableSong oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.moving && !oldWidget.moving) {
      _start();
    } else if (!widget.moving && oldWidget.moving) {
      _endHint();
    }
  }

  @override
  void dispose() {
    _endHint();
    _focus.dispose();
    super.dispose();
  }

  /// Once the list has it moving (not while it's being built), says how it moves, and takes the focus, where it isn't:
  /// picked from its menu, the menu gives it back to the song it opened from, but one opened otherwise may not.
  void _start() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !widget.moving) {
      return;
    }

    // At once, in place of the messages before it, rather than after them: and so the first, which closing it takes.
    final messenger = ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..removeCurrentSnackBar();
    final hint = messenger?.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).moveHint), duration: const Duration(days: 1)),
    );

    if (hint != null) {
      // Gone otherwise (another message in its place), it is no longer to close.
      var shown = true;
      hint.closed.whenComplete(() => shown = false);
      _closeHint = () {
        if (shown && messenger!.mounted) {
          hint.close();
        }
      };
    }

    if (!_focus.hasFocus) {
      _focus.traversalDescendants.firstOrNull?.requestFocus();
    }
  });

  /// Closes the message, after this frame: not while the list is being built.
  void _endHint() {
    final close = _closeHint;
    _closeHint = null;

    if (close != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!widget.moving) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final pressed = event is KeyDownEvent;

    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      if (event is! KeyUpEvent) {
        _step(key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      }
    } else if (_drop.contains(key)) {
      if (pressed) {
        widget.onDrop();
      }
    } else if (_cancel.contains(key)) {
      if (pressed) {
        widget.onCancel();
      }
    } else if (key != LogicalKeyboardKey.arrowLeft && key != LogicalKeyboardKey.arrowRight && !_menu.contains(key)) {
      // Anything else as ever: the media keys, say. Left and right would take the focus away from it.
      return KeyEventResult.ignored;
    }

    // Their repeats and releases too, held: OK would otherwise play the song.
    return KeyEventResult.handled;
  }

  /// Moves it a place up (-1) or down (1), and once the list has it there, scrolls it into sight, as the focus going
  /// there would.
  void _step(int direction) {
    widget.onStep(direction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: direction < 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _onKey,
    onFocusChange: (focused) {
      if (!focused && widget.moving) {
        widget.onDrop();
      }
    },
    // Lifted, on the page's color, as a song dragged is; otherwise as if not there, the line's tint on the page.
    child: Material(
      color: widget.moving ? Theme.of(context).colorScheme.surfaceContainerHigh : Colors.transparent,
      elevation: widget.moving ? 4 : 0,
      borderRadius: BorderRadius.circular(8),
      child: widget.child,
    ),
  );
}
