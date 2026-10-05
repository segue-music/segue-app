import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../server/models.dart';
import '../services.dart';
import 'errors.dart';
import 'spinner.dart';

/// A button that plays an album from its first song without opening it, to go over its cover. On a
/// computer it shows while the pointer is over the album ([hovered]); on a phone or a tablet, with
/// nothing to hover with, always. On a TV it doesn't: the remote goes from album to album, and would
/// have to stop at each one's button too. There an album plays from its page.
class AlbumPlayButton extends StatefulWidget {
  const AlbumPlayButton(this.album, {required this.hovered, this.small = false, super.key});

  final Album album;

  /// The pointer is over the album.
  final bool hovered;

  /// Over a thumbnail, as in search results, rather than a cover.
  final bool small;

  @override
  State<AlbumPlayButton> createState() => _AlbumPlayButtonState();
}

class _AlbumPlayButtonState extends State<AlbumPlayButton> {
  /// The album's songs are on their way.
  bool _loading = false;

  Future<void> _play() async {
    if (_loading) {
      return;
    }

    final services = ServicesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);

    try {
      final (_, songs) = await services.api.album(widget.album.id);
      final result = await services.connect.playSongs(songs, 0);

      if (!result.ok) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(result.error))));
      }
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Não consegui tocar o álbum: $error')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.navigationModeOf(context) == NavigationMode.directional) {
      return const SizedBox.shrink();
    }

    // By the platform, not by whether a mouse is connected: on a computer the system says the mouse is
    // gone whenever the pointer leaves the window.
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: touch || widget.hovered || _loading ? _button(context) : const SizedBox.shrink(),
    );
  }

  Widget _button(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconSize = widget.small ? 18.0 : 28.0;
    // Out of the focus's way, as the album's artist is: for the keyboard the album stays one stop.
    return ExcludeFocus(
      child: IconButton.filled(
        tooltip: 'Tocar o álbum',
        iconSize: iconSize,
        // The filled button's colors, said again: in a list tile's leading, the tile's icon button theme
        // would give the icon the tile's icons' color.
        style: IconButton.styleFrom(
          foregroundColor: colors.onPrimary,
          backgroundColor: colors.primary,
          minimumSize: widget.small ? const Size.square(32) : null,
          padding: widget.small ? EdgeInsets.zero : null,
        ),
        onPressed: _play,
        icon: _loading
            ? Spinner(size: iconSize, strokeWidth: 2.5, color: colors.onPrimary)
            : const Icon(HugeIcons.strokeRoundedPlay),
      ),
    );
  }
}
