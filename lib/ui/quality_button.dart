import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../quality_choice.dart';
import 'menu_item_label.dart';
import 'themed_icon.dart';

/// Picks the quality the player streams in, in a menu: the automatic one, which says what it does, the original, or a
/// bitrate the media server transcodes down to. The one picked has a check. In the home's top bar on a wide screen.
class QualityButton extends StatelessWidget {
  const QualityButton(this.choice, {super.key});

  final QualityChoice choice;

  /// The qualities to pick from, each by its name, and the automatic one with what it does. The quality menu's, and on a
  /// phone the home's menu's.
  static List<({StreamQuality quality, String name, String? detail})> options(AppLocalizations strings) => [
    for (final quality in StreamQuality.values)
      (
        quality: quality,
        name: strings.streamQuality(quality.name, quality.maxBitRate ?? 0),
        detail: quality == StreamQuality.automatic
            ? strings.automaticQualityDetail(StreamQuality.automatic.inUse(onMobileData: true).maxBitRate!)
            : null,
      ),
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
        for (final (:quality, :name, :detail) in options(strings))
          PopupMenuItem(
            value: quality,
            child: MenuItemLabel(
              name,
              detail: detail,
              icon: quality == choice.value ? HugeIcons.strokeRoundedTick02 : null,
            ),
          ),
      ],
    );
  }
}
