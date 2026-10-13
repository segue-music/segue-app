import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../widgets/mix_button.dart';
import '../widgets/spinner.dart';
import '../widgets/themed_icon.dart';

/// On a phone, the home's top bar, where the app's icon and name would only say again what the bar at the bottom says:
/// a chip that plays the whole library at random ([ShuffleLibraryChip]), and one that opens the user's favorites
/// (songs, albums and artists), one tap away rather than among the playlists. From the screen's edge, the first one
/// lined up with the home's rows.
class HomeChips extends StatelessWidget {
  const HomeChips({required this.onFavorites, super.key});

  final VoidCallback onFavorites;

  /// How wide the chips' fade is, at the right.
  static const _fade = 32.0;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);

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
            const ShuffleLibraryChip(),
            ActionChip(
              avatar: const ThemedIcon(HugeIcons.strokeRoundedFavourite),
              label: Text(strings.favorites),
              onPressed: onFavorites,
              mouseCursor: WidgetStateMouseCursor.clickable,
            ),
          ],
        ),
      ),
    );
  }
}

/// A chip that plays the whole library at random ([LibraryMix]), a spinner in its icon's place while the songs come:
/// in the phone's home's top bar, and in a wide screen's, from any page. With its name, rather than its icon alone,
/// which is also the player's shuffle.
class ShuffleLibraryChip extends StatefulWidget {
  const ShuffleLibraryChip({super.key});

  @override
  State<ShuffleLibraryChip> createState() => _ShuffleLibraryChipState();
}

class _ShuffleLibraryChipState extends State<ShuffleLibraryChip> {
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
  Widget build(BuildContext context) => ActionChip(
    avatar: _shuffling
        ? Spinner(size: 18, strokeWidth: 2, color: Theme.of(context).colorScheme.primary)
        : const ThemedIcon(HugeIcons.strokeRoundedShuffle),
    label: Text(AppLocalizations.of(context).shuffleLibrary),
    onPressed: _shuffle,
    mouseCursor: WidgetStateMouseCursor.clickable,
  );
}
