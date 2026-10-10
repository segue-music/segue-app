import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../autoplay_choice.dart';
import '../l10n/app_localizations.dart';
import 'themed_icon.dart';

/// The switch that turns autoplay ([choice]) on and off, with what it does under it: in the settings, and at the end of
/// the queue.
class AutoplaySwitch extends StatelessWidget {
  const AutoplaySwitch(this.choice, {super.key});

  final AutoplayChoice choice;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: choice,
      builder: (context, _) => SwitchListTile(
        secondary: const ThemedIcon(HugeIcons.strokeRoundedInfinity01),
        title: Text(strings.autoplay),
        subtitle: Text(strings.autoplayDetail),
        value: choice.value,
        onChanged: choice.turn,
      ),
    );
  }
}
