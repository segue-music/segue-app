import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../widgets/spinner.dart';
import '../widgets/themed_icon.dart';
import 'mix_row.dart';

/// On a phone, the home's top bar, where the app's icon and name would only say again what the bar at the bottom says:
/// a chip that plays the whole library at random, and one that opens the user's favorite songs, one tap away rather
/// than among the playlists. From the screen's edge, the first one lined up with the home's rows.
class HomeChips extends StatefulWidget {
  const HomeChips({required this.onFavorites, super.key});

  final VoidCallback onFavorites;

  @override
  State<HomeChips> createState() => _HomeChipsState();
}

class _HomeChipsState extends State<HomeChips> {
  /// How wide the chips' fade is, at the right.
  static const _fade = 32.0;

  /// The library's songs are on their way.
  bool _shuffling = false;

  Future<void> _shuffle() async {
    // Pressed again meanwhile, nothing: the chip stays enabled, so that the focus stays on it.
    if (_shuffling) {
      return;
    }

    setState(() => _shuffling = true);
    await playMix(context, const LibraryMix());

    if (mounted) {
      setState(() => _shuffling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);

    Widget chip(String label, Widget icon, VoidCallback onPressed) => ActionChip(
      avatar: icon,
      label: Text(label),
      onPressed: onPressed,
      mouseCursor: WidgetStateMouseCursor.clickable,
    );

    // Where they don't fit beside the bar's buttons (the system's text made bigger), they scroll sideways, as the
    // library's tabs do, and fade out before the buttons rather than end against them; scrolled to the last, it is clear
    // of the fade.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: const [Colors.black, Colors.transparent],
        stops: [max(0, 1 - _fade / bounds.width), 1],
      ).createShader(bounds),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 16, right: _fade),
        child: Row(
          spacing: 8,
          children: [
            chip(
              strings.shuffleLibrary,
              _shuffling
                  ? Spinner(size: 18, strokeWidth: 2, color: Theme.of(context).colorScheme.primary)
                  : const ThemedIcon(HugeIcons.strokeRoundedShuffle),
              _shuffle,
            ),
            chip(strings.favoriteSongsChip, const ThemedIcon(HugeIcons.strokeRoundedFavourite), widget.onFavorites),
          ],
        ),
      ),
    );
  }
}
