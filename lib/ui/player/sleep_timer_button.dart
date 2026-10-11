import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../player/sleep_timer.dart';
import '../../services.dart';
import '../widgets/themed_icon.dart';

/// The sleep timer's button ([SleepTimer]): a moon, in the theme's color while the timer is on, with the minutes left on
/// it while it counts down. It opens a sheet of the whiles to pick, the song's end, and, on, turning it off. Nothing
/// where the session has no timer.
class SleepTimerButton extends StatelessWidget {
  const SleepTimerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final timer = ServicesScope.of(context).sleepTimer;

    if (timer == null) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: timer,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final strings = AppLocalizations.of(context);
        final minutes = timer.minutesLeft;

        return IconButton(
          tooltip: _state(strings, timer) ?? strings.sleepTimer,
          icon: Badge(
            isLabelVisible: minutes != null,
            label: Text('$minutes'),
            backgroundColor: colors.primary,
            textColor: colors.onPrimary,
            child: ThemedIcon(HugeIcons.strokeRoundedMoon02, color: timer.on ? colors.primary : null),
          ),
          onPressed: () => _open(context, timer),
        );
      },
    );
  }

  /// When the timer pauses the music; null while it's off.
  static String? _state(AppLocalizations strings, SleepTimer timer) => switch (timer.minutesLeft) {
    final minutes? => strings.sleepTimerPausesIn(minutes),
    null when timer.untilSongEnds => strings.sleepTimerPausesAtSongEnd,
    null => null,
  };

  /// The timer's sheet, over the window, also from the home's page area: its state, and what to set it to, each closing
  /// it.
  void _open(BuildContext context, SleepTimer timer) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    // As tall as its lines, up to the whole screen, where they scroll.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) {
      final strings = AppLocalizations.of(sheet);
      final text = Theme.of(sheet).textTheme;
      final state = _state(strings, timer);

      ListTile option(String name, VoidCallback onTap, {bool picked = false}) => ListTile(
        title: Text(name),
        selected: picked,
        trailing: picked ? const ThemedIcon(HugeIcons.strokeRoundedTick02) : null,
        onTap: () {
          onTap();
          Navigator.of(sheet).pop();
        },
      );

      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.sleepTimer, style: text.titleLarge),
                if (state != null) Text(state, style: text.bodyMedium),
              ],
            ),
          ),
          for (final after in SleepTimer.whiles)
            option(strings.sleepTimerWhile('${after.inMinutes}'), () => timer.start(after)),
          option(strings.sleepTimerSongEnd, timer.startUntilSongEnds, picked: timer.untilSongEnds),
          if (timer.on) option(strings.sleepTimerOff, timer.cancel),
        ],
      );
    },
  );
}
