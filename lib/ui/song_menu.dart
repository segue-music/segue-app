import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../segue/protocol.dart';
import '../server/models.dart';
import '../services.dart';
import 'errors.dart';
import 'menu_item_label.dart';
import 'playlist_dialogs.dart';
import 'themed_icon.dart';

/// What a menu of songs does: a song's, or an album's with all of its songs.
enum SongAction { playNext, addToQueue, addToPlaylist, removeFromPlaylist }

/// The items of a menu of songs: playing them next and adding them to the queue, where the device the app controls
/// takes it, and adding them to a playlist; with [removable], taking the song out of the playlist listing it.
List<PopupMenuEntry<SongAction>> songMenuItems(BuildContext context, {bool removable = false}) {
  final strings = AppLocalizations.of(context);
  return [
    if (ServicesScope.of(context).connect.canAddToQueue) ...[
      PopupMenuItem(
        value: SongAction.playNext,
        child: MenuItemLabel(strings.playNext, icon: HugeIcons.strokeRoundedNext),
      ),
      PopupMenuItem(
        value: SongAction.addToQueue,
        child: MenuItemLabel(strings.addToQueue, icon: HugeIcons.strokeRoundedAddToList),
      ),
    ],
    PopupMenuItem(
      value: SongAction.addToPlaylist,
      child: MenuItemLabel(strings.addToPlaylist, icon: HugeIcons.strokeRoundedPlaylist01),
    ),
    if (removable)
      PopupMenuItem(
        value: SongAction.removeFromPlaylist,
        child: MenuItemLabel(strings.removeFromPlaylist, icon: HugeIcons.strokeRoundedRemoveCircle),
      ),
  ];
}

/// Does [action] with [songs]; [onRemove] takes the song out of the playlist listing it.
void runSongAction(BuildContext context, SongAction action, List<Song> songs, {VoidCallback? onRemove}) {
  switch (action) {
    case SongAction.playNext:
      addToQueue(context, songs, next: true);
    case SongAction.addToQueue:
      addToQueue(context, songs, next: false);
    case SongAction.addToPlaylist:
      addToPlaylist(context, songs);
    case SongAction.removeFromPlaylist:
      onRemove?.call();
  }
}

/// Adds [songs] to the queue of the device the app controls, the current track playing on: right after it if [next],
/// otherwise at its end; and says so, or why not. Whether they went.
Future<bool> addToQueue(BuildContext context, List<Song> songs, {required bool next}) async {
  final connect = ServicesScope.of(context).connect;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final strings = AppLocalizations.of(context);
  final result = await connect.addToQueue(songs, next: next);
  final said = switch (result) {
    Result(ok: false, :final error) => describeError(strings, error),
    _ when next => strings.playingNext(songs.length),
    _ => strings.addedToQueue(songs.length),
  };
  messenger?.showSnackBar(SnackBar(content: Text(said)));
  return result.ok;
}

/// A song's menu, at the end of its line in a list, after its duration: what can be done with it besides playing it,
/// playing it next, adding it to the queue or to a playlist, and, in a playlist that the user can change ([onRemove]),
/// taking it out. Its button takes no focus: for the keyboard and the remote the song stays one stop, where the menu
/// key, or Shift+F10, opens the menu. [builder] makes the song's line, with the button ([SongMenu.width] wide) where it
/// goes.
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
  final _button = GlobalKey<PopupMenuButtonState<SongAction>>();

  void _open() => _button.currentState?.showButtonMenu();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final button = ExcludeFocus(
      child: SizedBox.square(
        dimension: SongMenu.width,
        child: PopupMenuButton<SongAction>(
          key: _button,
          tooltip: strings.moreOptions,
          icon: const ThemedIcon(HugeIcons.strokeRoundedMoreVertical),
          // As big as the room it has, without Material's padding for a touch screen around it.
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onSelected: (action) => runSongAction(context, action, [widget.song], onRemove: widget.onRemove),
          itemBuilder: (context) => songMenuItems(context, removable: widget.onRemove != null),
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
