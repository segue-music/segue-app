import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('segue/window');

/// Gives the window's title bar, the one with the app's name and the close button, the theme's background and
/// text, so that it reads as part of the app and not as a strip of the system's color above it. On Linux, GTK draws
/// it (linux/runner/my_application.cc). Elsewhere there is no such channel, and the system's bar stays as it is.
class ThemedTitleBar extends StatefulWidget {
  const ThemedTitleBar({required this.child, super.key});

  final Widget child;

  @override
  State<ThemedTitleBar> createState() => _ThemedTitleBarState();
}

class _ThemedTitleBarState extends State<ThemedTitleBar> {
  /// The colors the window was last told, so that it is told again only when the theme changes.
  ({Color background, Color foreground})? _told;

  /// Whether the window has no title bar of the app's to paint.
  bool _unsupported = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final colors = Theme.of(context).colorScheme;

    _paint((background: colors.surface, foreground: colors.onSurface));
  }

  Future<void> _paint(({Color background, Color foreground}) colors) async {
    if (_unsupported || colors == _told) {
      return;
    }

    _told = colors;

    try {
      await _channel.invokeMethod<void>('setTitleBarColors', {
        'background': colors.background.toARGB32(),
        'foreground': colors.foreground.toARGB32(),
      });
    } on MissingPluginException {
      _unsupported = true;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
