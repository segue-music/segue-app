import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import '../services.dart';
import 'menu_item_label.dart';
import 'playlist_dialogs.dart';
import 'song_menu.dart';

/// What a playlist's menu does.
enum PlaylistAction { playNext, addToQueue, rename, delete }

/// The items of [playlist]'s menu, on its page and in the list of them: playing its songs next and adding them to the
/// queue, where it has some ([hasSongs]) and the device the app controls takes it; renaming it and deleting it, where
/// the user can change it. None, where none of these.
List<PopupMenuEntry<PlaylistAction>> playlistMenuItems(
  BuildContext context,
  Playlist playlist, {
  required bool hasSongs,
}) {
  final strings = AppLocalizations.of(context);
  return [
    if (hasSongs && ServicesScope.of(context).connect.canAddToQueue) ...[
      PopupMenuItem(
        value: PlaylistAction.playNext,
        child: MenuItemLabel(strings.playNext, icon: HugeIcons.strokeRoundedNext),
      ),
      PopupMenuItem(
        value: PlaylistAction.addToQueue,
        child: MenuItemLabel(strings.addToQueue, icon: HugeIcons.strokeRoundedAddToList),
      ),
    ],
    if (playlist.editable) ...[
      PopupMenuItem(
        value: PlaylistAction.rename,
        child: MenuItemLabel(strings.renamePlaylist, icon: HugeIcons.strokeRoundedEdit02),
      ),
      PopupMenuItem(
        value: PlaylistAction.delete,
        child: MenuItemLabel(strings.deletePlaylist, icon: HugeIcons.strokeRoundedDelete02),
      ),
    ],
  ];
}

/// Does [action] to [playlist]: plays its songs next, or adds them to the queue, those of its page ([songs]), or else
/// as the server has them; or asks for its new name, or whether to delete it, then has the server do it. Says why not
/// where it isn't done. Whether it was done.
Future<bool> runPlaylistAction(
  BuildContext context,
  Playlist playlist,
  PlaylistAction action, {
  List<Song>? songs,
}) async {
  final services = ServicesScope.of(context);
  final editor = services.playlistEditor;
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);

  Future<void> Function()? change;

  switch (action) {
    case PlaylistAction.playNext || PlaylistAction.addToQueue:
      var queued = songs;

      if (queued == null) {
        try {
          (_, queued) = await services.api.playlist(playlist.id);
        } on Object catch (error) {
          messenger.showSnackBar(SnackBar(content: Text(strings.couldNotOpenPlaylist('$error'))));
          return false;
        }
      }

      if (queued.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(strings.playlistEmpty)));
        return false;
      }

      if (!context.mounted) {
        return false;
      }

      return addToQueue(context, queued, next: action == PlaylistAction.playNext);

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
