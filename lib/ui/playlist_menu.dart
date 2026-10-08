import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import '../services.dart';
import 'menu_item_label.dart';
import 'playlist_dialogs.dart';

/// What a playlist's menu does.
enum PlaylistAction { rename, delete }

/// The items of a playlist's menu, which renames it and deletes it: on its page, and in the list of them.
List<PopupMenuEntry<PlaylistAction>> playlistMenuItems(AppLocalizations strings) => [
  PopupMenuItem(
    value: PlaylistAction.rename,
    child: MenuItemLabel(strings.renamePlaylist, icon: HugeIcons.strokeRoundedEdit02),
  ),
  PopupMenuItem(
    value: PlaylistAction.delete,
    child: MenuItemLabel(strings.deletePlaylist, icon: HugeIcons.strokeRoundedDelete02),
  ),
];

/// Does [action] to [playlist]: asks for its new name, or whether to delete it, then has the server do it, saying why
/// not where it doesn't. Whether it was done.
Future<bool> runPlaylistAction(BuildContext context, Playlist playlist, PlaylistAction action) async {
  final editor = ServicesScope.of(context).playlistEditor;
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);

  Future<void> Function()? change;

  switch (action) {
    case PlaylistAction.rename:
      final name = await askPlaylistName(context, name: playlist.name);

      if (name != null) {
        change = () => editor.rename(playlist.id, name);
      }

    case PlaylistAction.delete:
      if (await confirmPlaylistDeletion(context, playlist)) {
        change = () => editor.delete(playlist.id);
      }
  }

  if (change == null) {
    return false;
  }

  try {
    await change();
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(strings.couldNotChangePlaylist('$error'))));
    return false;
  }
}
