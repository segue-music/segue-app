import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../quality_choice.dart';
import 'menu_item_label.dart';
import 'themed_icon.dart';

/// Picks the quality the player streams in, in a menu: the original, or a bitrate the media server transcodes down to.
/// The one picked has a check. In the home's top bar on a wide screen.
class QualityButton extends StatelessWidget {
  const QualityButton(this.choice, {super.key});

  final QualityChoice choice;

  /// The qualities to pick from, each by its name. The quality menu's, and on a phone the home's menu's.
  static List<(StreamQuality, String)> options(AppLocalizations strings) => [
    for (final quality in StreamQuality.values) (quality, strings.streamQuality(quality.name, quality.maxBitRate ?? 0)),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return PopupMenuButton<StreamQuality>(
      tooltip: strings.audioQuality,
      icon: const ThemedIcon(HugeIcons.strokeRoundedAudioWave01),
      // The one picked highlighted, level with the button.
      initialValue: choice.value,
      onSelected: choice.pick,
      itemBuilder: (context) => [
        for (final (quality, name) in options(strings))
          PopupMenuItem(
            value: quality,
            child: MenuItemLabel(name, icon: quality == choice.value ? HugeIcons.strokeRoundedTick02 : null),
          ),
      ],
    );
  }
}
