import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The keys that open the menu of an item of a list (a song, a playlist), which is one stop for the keyboard and the
/// remote, its menu's button, where it has one, taking no focus: the menu key, Shift+F10, and the D-pad's center held,
/// as Android TV's apps have it, since a TV's remote seldom has a menu key. Let go before then, the center does what it
/// always did (plays the song, opens the playlist), only as it is let go rather than as it is pressed.
class MenuShortcuts extends StatefulWidget {
  const MenuShortcuts({required this.onOpen, required this.child, super.key});

  /// Opens the item's menu.
  final VoidCallback onOpen;

  /// The item, which has the focus: its keys come up through this.
  final Widget child;

  @override
  State<MenuShortcuts> createState() => _MenuShortcutsState();
}

class _MenuShortcutsState extends State<MenuShortcuts> {
  /// Until the center, pressed, has been held long enough to open the menu.
  Timer? _hold;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.select) {
      return KeyEventResult.ignored;
    }

    final pressed = _hold != null;
    _hold?.cancel();
    _hold = null;

    if (event is KeyDownEvent) {
      _hold = Timer(kLongPressTimeout, () {
        _hold = null;
        widget.onOpen();
      });
    } else if (pressed && event is KeyRepeatEvent) {
      // Android repeats a key from when it takes it as held (its long press timeout, which the user may change), which
      // can be before Flutter's.
      widget.onOpen();
    } else if (pressed && event is KeyUpEvent) {
      final focused = FocusManager.instance.primaryFocus?.context;

      if (focused != null) {
        Actions.maybeInvoke(focused, const ActivateIntent());
      }
    }

    // Its repeats too, which, held, would otherwise play the song again and again.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.contextMenu): widget.onOpen,
      const SingleActivator(LogicalKeyboardKey.f10, shift: true): widget.onOpen,
    },
    child: Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: widget.child),
  );
}

/// Where the menu of the item [context] builds opens ([showMenu]): at [at], in the window, where a pointer pressed the
/// item, or else over it.
RelativeRect menuPosition(BuildContext context, {Offset? at}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final item = context.findRenderObject()! as RenderBox;
  final area = switch (at) {
    final point? => Rect.fromPoints(overlay.globalToLocal(point), overlay.globalToLocal(point)),
    null => Rect.fromPoints(
      item.localToGlobal(Offset.zero, ancestor: overlay),
      item.localToGlobal(item.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
  };

  return RelativeRect.fromRect(area, Offset.zero & overlay.size);
}
