import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import 'menu_item_label.dart';
import 'playlist_dialogs.dart';
import 'themed_icon.dart';

/// What a song's menu does.
enum _SongAction { addToPlaylist, removeFromPlaylist }

/// A song's menu, at the end of its line in a list: what can be done with it besides playing it, adding it to a playlist,
/// and, in a playlist that the user can change ([onRemove]), taking it out. Its button takes no focus: for the keyboard
/// and the remote the song stays one stop, where the menu key, or Shift+F10, opens the menu. [builder] makes the song's
/// line, with the button ([SongMenu.width] wide) where it goes.
class SongMenu extends StatefulWidget {
  const SongMenu(this.song, {required this.builder, this.onRemove, super.key});

  final Song song;

  /// Takes the song out of the playlist listing it; null, no such item.
  final VoidCallback? onRemove;

  final Widget Function(BuildContext context, Widget button) builder;

  /// How wide the button is: as a list's header leaves room for it.
  static const width = 40.0;

  @override
  State<SongMenu> createState() => _SongMenuState();
}

class _SongMenuState extends State<SongMenu> {
  final _button = GlobalKey<PopupMenuButtonState<_SongAction>>();

  void _open() => _button.currentState?.showButtonMenu();

  void _do(_SongAction action) {
    switch (action) {
      case _SongAction.addToPlaylist:
        addToPlaylist(context, [widget.song]);
      case _SongAction.removeFromPlaylist:
        widget.onRemove?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final onRemove = widget.onRemove;
    final button = ExcludeFocus(
      child: SizedBox.square(
        dimension: SongMenu.width,
        child: PopupMenuButton<_SongAction>(
          key: _button,
          tooltip: strings.moreOptions,
          icon: const ThemedIcon(HugeIcons.strokeRoundedMoreVertical),
          // As big as the room it has, without Material's padding for a touch screen around it.
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onSelected: _do,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _SongAction.addToPlaylist,
              child: MenuItemLabel(strings.addToPlaylist, icon: HugeIcons.strokeRoundedPlaylist01),
            ),
            if (onRemove != null)
              PopupMenuItem(
                value: _SongAction.removeFromPlaylist,
                child: MenuItemLabel(strings.removeFromPlaylist, icon: HugeIcons.strokeRoundedRemoveCircle),
              ),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): _open,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): _open,
      },
      child: widget.builder(context, button),
    );
  }
}

/// The end of a song's line in a list: its duration ([duration]), under the header's clock, and its menu's [button].
class SongTrailing extends StatelessWidget {
  const SongTrailing(this.duration, this.button, {super.key});

  final Widget duration;
  final Widget button;

  /// The room between them.
  static const gap = 4.0;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      duration,
      const SizedBox(width: gap),
      button,
    ],
  );
}
