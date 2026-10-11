import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../connect/connect.dart';
import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../widgets/cover.dart';
import '../widgets/spinner.dart';
import '../widgets/themed_icon.dart';

/// Asks for a playlist's name: a new one's, or, with [name], the new name of the playlist named so. The name typed, with
/// no spaces around it; null where the dialog closed without one.
Future<String?> askPlaylistName(BuildContext context, {String? name}) =>
    showDialog<String>(context: context, builder: (_) => _NameDialog(name));

class _NameDialog extends StatefulWidget {
  const _NameDialog(this.name);

  /// The playlist's name now; null for a new one.
  final String? name;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.name);

  /// The name typed, where there is one and it's new.
  String? get _typed => switch (_name.text.trim()) {
    '' => null,
    final name when name == widget.name => null,
    final name => name,
  };

  void _done() {
    if (_typed case final name?) {
      Navigator.of(context).pop(name);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final renaming = widget.name != null;

    return AlertDialog(
      title: Text(renaming ? strings.renamePlaylist : strings.newPlaylist),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: strings.playlistName),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(strings.cancel)),
        // Pressed as the name changes from nothing to something.
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => TextButton(
            onPressed: _typed == null ? null : _done,
            child: Text(renaming ? strings.rename : strings.createPlaylist),
          ),
        ),
      ],
    );
  }
}

/// Asks before [playlist] is deleted: whether to.
Future<bool> confirmPlaylistDeletion(BuildContext context, Playlist playlist) async {
  final strings = AppLocalizations.of(context);
  final delete = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.deletePlaylistQuestion(playlist.name)),
      content: Text(strings.deletePlaylistDetail),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(strings.cancel)),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(strings.delete)),
      ],
    ),
  );

  return delete ?? false;
}

/// Adds [songs] to a playlist the user picks, of those they can change, or to a new one they name, and says so, or why
/// not.
Future<void> addToPlaylist(BuildContext context, List<Song> songs) async {
  final editor = ServicesScope.of(context).playlistEditor;
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);
  final picked = await showDialog<_Pick>(context: context, builder: (_) => const _PlaylistPicker());

  if (picked == null || !context.mounted) {
    return;
  }

  final ids = [for (final song in songs) song.id];
  final (:playlist) = picked;

  if (playlist == null) {
    final name = await askPlaylistName(context);

    if (name == null) {
      return;
    }

    try {
      await editor.create(name, songIds: ids);
      messenger.showSnackBar(SnackBar(content: Text(strings.addedToPlaylist(songs.length, name))));
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(strings.couldNotCreatePlaylist('$error'))));
    }

    return;
  }

  try {
    await editor.add(playlist.id, ids);
    messenger.showSnackBar(SnackBar(content: Text(strings.addedToPlaylist(songs.length, playlist.name))));
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(strings.couldNotChangePlaylist('$error'))));
  }
}

/// A button of the player that adds the song that plays ([now]) to a playlist, as its menu does elsewhere
/// ([addToPlaylist]). Disabled with nothing playing, and for a song the hub couldn't give in the app's API.
class AddToPlaylistButton extends StatelessWidget {
  const AddToPlaylistButton(this.now, {super.key});

  final NowPlaying? now;

  @override
  Widget build(BuildContext context) {
    final now = this.now;
    final songId = now?.songId;

    return IconButton(
      tooltip: AppLocalizations.of(context).addToPlaylist,
      icon: const ThemedIcon(HugeIcons.strokeRoundedPlayListAdd),
      onPressed: now == null || songId == null
          ? null
          : () => addToPlaylist(context, [
              Song(
                id: songId,
                title: now.title ?? '',
                artist: now.artist,
                album: now.album,
                coverArt: now.coverArt,
                duration: now.duration,
              ),
            ]),
    );
  }
}

/// A playlist picked to add songs to; none, a new one.
typedef _Pick = ({Playlist? playlist});

/// The playlists the user can change, by name, under one that makes a new one: picking one closes it with it.
class _PlaylistPicker extends StatefulWidget {
  const _PlaylistPicker();

  @override
  State<_PlaylistPicker> createState() => _PlaylistPickerState();
}

class _PlaylistPickerState extends State<_PlaylistPicker> {
  Future<List<Playlist>>? _playlists;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playlists ??= ServicesScope.of(context).api.playlists().then(
      (playlists) => [
        for (final playlist in playlists)
          if (playlist.editable) playlist,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);

    return SimpleDialog(
      title: Text(strings.addToPlaylist),
      children: [
        ListTile(
          leading: const _NewPlaylistIcon(),
          title: Text(strings.newPlaylist),
          onTap: () => Navigator.of(context).pop<_Pick>((playlist: null)),
        ),
        FutureBuilder(
          future: _playlists,
          builder: (context, snapshot) => switch (snapshot) {
            AsyncSnapshot(hasError: true, :final error) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(strings.couldNotListPlaylists('$error')),
            ),
            AsyncSnapshot(:final data?) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final playlist in data)
                  ListTile(
                    leading: Thumbnail(playlist.coverArt, icon: HugeIcons.strokeRoundedPlaylist01),
                    title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop<_Pick>((playlist: playlist)),
                  ),
              ],
            ),
            _ => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Spinner()),
            ),
          },
        ),
      ],
    );
  }
}

/// A new playlist's icon, a plus, where a playlist's picture would be.
class _NewPlaylistIcon extends StatelessWidget {
  const _NewPlaylistIcon();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: Thumbnail.size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(child: ThemedIcon(HugeIcons.strokeRoundedPlusSign)),
    ),
  );
}

/// A button that makes a new playlist, named in a dialog: at the top of the list of them.
class NewPlaylistTile extends StatelessWidget {
  const NewPlaylistTile({super.key});

  Future<void> _create(BuildContext context) async {
    final editor = ServicesScope.of(context).playlistEditor;
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppLocalizations.of(context);
    final name = await askPlaylistName(context);

    if (name == null) {
      return;
    }

    try {
      await editor.create(name);
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(strings.couldNotCreatePlaylist('$error'))));
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const _NewPlaylistIcon(),
    title: Text(AppLocalizations.of(context).newPlaylist),
    onTap: () => _create(context),
  );
}
