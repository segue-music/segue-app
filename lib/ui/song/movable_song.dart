import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/directional_navigation.dart';

/// A list's songs that move (the queue's from the one on top, a playlist's), as a sliver: dragged, on a touch screen
/// once held a moment, since a drag scrolls the list, and with a mouse at once; on a TV, which has no drag, by the
/// remote, from their menu ([MovableSong]), the list showing the song where it has gone so far, and once it's left
/// there, [onMove] moving it. While it moves, back (the top bar's arrow, say) puts it back rather than leaving the page.
/// Without [onMove] (a list the user can't change), they stay where they are.
class MovableSongs extends StatefulWidget {
  const MovableSongs({required this.keys, required this.itemBuilder, this.onMove, super.key});

  /// A key for each song, which stays with it as the list comes anew and as it moves past others: the list keeps its
  /// line by it, and with it the focus.
  final List<Key> keys;

  /// Builds the song at [index] in the list as it is, not where it shows as it moves; with how the remote moves it, on
  /// a TV.
  final Widget Function(BuildContext context, int index, RemoteMove? byRemote) itemBuilder;

  /// Moves the song at [from] to [to], the place it then has.
  final void Function(int from, int to)? onMove;

  @override
  State<MovableSongs> createState() => _MovableSongsState();
}

/// How a song of [MovableSongs] moves by the remote, on a TV.
class RemoteMove {
  const RemoteMove({required this.start, required this.movable});

  /// Picks it to move: its menu's item (`SongMenu.onMove`).
  final VoidCallback start;

  /// Its line, as the remote moves it.
  final Widget Function(Widget line) movable;
}

class _MovableSongsState extends State<MovableSongs> {
  /// On a TV, the song the remote moves, by its key, as the list may come anew meanwhile, and how many places it has
  /// gone so far, up (below zero) or down.
  ({Key key, int by})? _moving;

  @override
  Widget build(BuildContext context) {
    final onMove = widget.onMove;

    if (onMove == null) {
      return _keyed(widget.keys, (context, i) => widget.itemBuilder(context, i, null));
    }

    if (DirectionalNavigation.of(context)) {
      return _byRemote(onMove);
    }

    final keys = widget.keys;
    final theme = Theme.of(context);
    final touch = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
    };

    return SliverReorderableList(
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final song = widget.itemBuilder(context, i, null);

        return touch
            ? ReorderableDelayedDragStartListener(key: keys[i], index: i, child: song)
            : ReorderableDragStartListener(key: keys[i], index: i, child: song);
      },
      onReorderItem: onMove,
      // The song moving, lifted over the others, on the page's color: in the overlay, over the page.
      proxyDecorator: (child, _, _) => Material(
        elevation: 4,
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }

  Widget _byRemote(void Function(int from, int to) onMove) {
    final keys = widget.keys;
    final moving = _moving;
    final from = moving == null ? -1 : keys.indexOf(moving.key);
    // Where each song shows: the one moving where it has gone so far.
    var order = [for (var i = 0; i < keys.length; i++) i];
    int? to;

    if (moving != null && from >= 0) {
      to = (from + moving.by).clamp(0, keys.length - 1);
      order = _withMove(order, from: from, to: to);
    } else {
      // Gone from the list meanwhile, as it came anew.
      _moving = null;
    }

    void stop() => setState(() => _moving = null);

    return PopScope(
      canPop: to == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          stop();
        }
      },
      child: _keyed([for (final i in order) keys[i]], (context, shown) {
        final i = order[shown];
        final key = keys[i];

        return widget.itemBuilder(
          context,
          i,
          RemoteMove(
            start: () => setState(() => _moving = (key: key, by: 0)),
            movable: (line) => MovableSong(
              moving: shown == to,
              onStep: (step) =>
                  setState(() => _moving = (key: key, by: (shown + step).clamp(0, keys.length - 1) - from)),
              onDrop: () {
                stop();
                onMove(from, shown);
              },
              onCancel: stop,
              child: line,
            ),
          ),
        );
      }),
    );
  }

  /// The songs in the order of [keys], each line kept by its key: one the remote moves keeps its line, and the focus.
  /// [builder] builds the one at a place in it.
  Widget _keyed(List<Key> keys, IndexedWidgetBuilder builder) => SliverList.builder(
    itemCount: keys.length,
    itemBuilder: (context, i) => KeyedSubtree(key: keys[i], child: builder(context, i)),
    findChildIndexCallback: (key) {
      final i = keys.indexOf(key);

      return i < 0 ? null : i;
    },
  );
}

/// [items] with the one at [from] at [to] instead, the others closing up after it and making room for it.
List<T> _withMove<T>(List<T> items, {required int from, required int to}) => [...items]
  ..removeAt(from)
  ..insert(to, items[from]);

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
