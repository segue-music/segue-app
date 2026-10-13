import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../../segue/protocol.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../playlist/playlist_dialogs.dart';
import '../widgets/errors.dart';
import '../widgets/menu_shortcuts.dart';
import '../widgets/menu_item_label.dart';
import '../widgets/mix_button.dart';
import '../widgets/themed_icon.dart';
import 'favorite_button.dart';

/// What a menu of songs does: a song's, or an album's with all of its songs.
enum SongAction { playNext, addToQueue, addToPlaylist, favorite, unfavorite, radio, move, remove }

/// The list a song's menu takes it out of ([SongAction.remove]).
enum SongList { playlist, queue }

/// The items of a menu of songs: playing them next and adding them to the queue, where the device the app controls
/// takes it, and adding them to a playlist; a song's, with whether it is one of the user's favorites ([favorite]),
/// making it one or no longer one, and, unless not [radio] (an album's songs, whose menu has the album's), playing its
/// radio; where it is [movable], moving it in its list by the remote's arrows; with [removableFrom], taking the song out
/// of that list.
List<PopupMenuEntry<SongAction>> songMenuItems(
  BuildContext context, {
  bool? favorite,
  bool radio = true,
  bool movable = false,
  SongList? removableFrom,
}) {
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
    if (favorite != null)
      favorite
          ? PopupMenuItem(
              value: SongAction.unfavorite,
              child: MenuItemLabel(strings.removeFromFavorites, icon: filledHeart),
            )
          : PopupMenuItem(
              value: SongAction.favorite,
              child: MenuItemLabel(strings.addToFavorites, icon: HugeIcons.strokeRoundedFavourite),
            ),
    if (radio)
      PopupMenuItem(
        value: SongAction.radio,
        child: MenuItemLabel(strings.songRadio, icon: HugeIcons.strokeRoundedRadio),
      ),
    if (movable)
      PopupMenuItem(
        value: SongAction.move,
        child: MenuItemLabel(strings.move, icon: HugeIcons.strokeRoundedArrowUpDown),
      ),
    if (removableFrom != null)
      PopupMenuItem(
        value: SongAction.remove,
        child: MenuItemLabel(switch (removableFrom) {
          SongList.playlist => strings.removeFromPlaylist,
          SongList.queue => strings.removeFromQueue,
        }, icon: HugeIcons.strokeRoundedRemoveCircle),
      ),
  ];
}

/// Does [action] with [songs]; [onMove] starts moving the song in the list it is in, and [onRemove] takes it out.
void runSongAction(
  BuildContext context,
  SongAction action,
  List<Song> songs, {
  VoidCallback? onMove,
  VoidCallback? onRemove,
}) {
  switch (action) {
    case SongAction.playNext:
      addToQueue(context, songs, next: true);
    case SongAction.addToQueue:
      addToQueue(context, songs, next: false);
    case SongAction.addToPlaylist:
      addToPlaylist(context, songs);
    case SongAction.favorite || SongAction.unfavorite:
      for (final song in songs) {
        setFavorite(context, FavoriteKind.song, song.id, favorite: action == SongAction.favorite);
      }
    case SongAction.radio:
      playMix(context, SongRadio(songs.single));
    case SongAction.move:
      onMove?.call();
    case SongAction.remove:
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
/// playing it next, adding it to the queue or to a playlist, making it one of the user's favorites or no longer one,
/// playing its radio, and, in a list that the user can change ([onRemove]), a playlist or the queue ([list]), taking it out, and on a TV
/// moving it there ([onMove]). Its button takes no focus: for the keyboard and the remote the song stays one stop,
/// where the menu key, Shift+F10, or OK held opens the menu ([MenuShortcuts]). [builder] makes the song's line, with
/// the button ([SongMenu.width] wide) where it goes.
class SongMenu extends StatefulWidget {
  const SongMenu(
    this.song, {
    required this.builder,
    this.onMove,
    this.onRemove,
    this.list = SongList.playlist,
    super.key,
  });

  final Song song;

  /// Starts moving the song in the list it is in, by the remote's arrows ([MovableSong]); null, no such item.
  final VoidCallback? onMove;

  /// Takes the song out of the list it is in; null, no such item.
  final VoidCallback? onRemove;

  /// The list [onRemove] takes it out of, which its item names.
  final SongList list;

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
          onSelected: (action) =>
              runSongAction(context, action, [widget.song], onMove: widget.onMove, onRemove: widget.onRemove),
          itemBuilder: (context) => songMenuItems(
            context,
            favorite: ServicesScope.of(context).favorites.contains(FavoriteKind.song, widget.song.id),
            movable: widget.onMove != null,
            removableFrom: widget.onRemove == null ? null : widget.list,
          ),
        ),
      ),
    );

    return MenuShortcuts(onOpen: _open, child: widget.builder(context, button));
  }
}
