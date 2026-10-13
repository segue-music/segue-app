import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../segue/protocol.dart';
import '../../services.dart';

import '../widgets/directional_navigation.dart';
import '../widgets/equalizer.dart';
import '../widgets/errors.dart';
import '../widgets/themed_icon.dart';

/// The device picker: pick where the music plays.
Future<void> showDevicesSheet(BuildContext context) =>
    // Over the whole window, also from a page of the home's page area.
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => const _DevicesSheet(),
    );

class _DevicesSheet extends StatelessWidget {
  const _DevicesSheet();

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final connect = services.connect;
    final strings = AppLocalizations.of(context);

    Future<void> act(Future<Result> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final result = await action();

      if (result.ok) {
        navigator.pop();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(describeError(strings, result.error))));
      }
    }

    return ListenableBuilder(
      listenable: connect,
      builder: (context, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(strings.connectToDevice, style: Theme.of(context).textTheme.titleLarge),
          ),
          ListTile(
            leading: ThemedIcon(_thisDeviceIcon(context)),
            title: Text(strings.thisDevice(services.session.deviceName)),
            selected: connect.activeId == null,
            trailing: _marks(playing: connect.player.playing, active: connect.activeId == null),
            onTap: () => act(() => connect.switchTo(null)),
          ),
          if (connect.client == null)
            ListTile(
              leading: const ThemedIcon(HugeIcons.strokeRoundedInformationCircle),
              title: Text(strings.noHubFound),
              subtitle: Text(strings.noHubAt(services.session.server.host)),
            ),
          for (final device in connect.devices)
            ListTile(
              leading: const ThemedIcon(HugeIcons.strokeRoundedSpeaker),
              title: Text(device.info.name),
              subtitle: Text(_describe(device)),
              selected: connect.activeId == device.id,
              trailing: _marks(
                playing: device.state?.status == PlaybackStatus.playing,
                active: connect.activeId == device.id,
              ),
              onTap: () => act(() => connect.switchTo(device.id)),
            ),
        ],
      ),
    );
  }

  /// What this device is: a TV, which the remote drives; a phone or a tablet, by its touch screen and how wide it
  /// is (600 across or more, as Material counts, a tablet); or else a computer. Of the other devices the protocol
  /// says nothing of the kind, so they are all speakers.
  static HugeIconData _thisDeviceIcon(BuildContext context) {
    if (DirectionalNavigation.of(context)) {
      return HugeIcons.strokeRoundedTv01;
    }

    return switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia =>
        MediaQuery.sizeOf(context).shortestSide >= 600
            ? HugeIcons.strokeRoundedTablet01
            : HugeIcons.strokeRoundedSmartphone,
      TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => HugeIcons.strokeRoundedComputer,
    };
  }

  /// Whether a device plays (equalizer) and whether the app controls it (check).
  static Widget? _marks({required bool playing, required bool active}) {
    if (!playing && !active) {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [if (playing) const Equalizer(), if (active) const ThemedIcon(HugeIcons.strokeRoundedTick02)],
    );
  }

  /// What [device] plays, or has paused, without saying which: the equalizer says it plays. Otherwise its app.
  static String _describe(Device device) {
    final state = device.state;
    final item = state?.current;

    if (item == null || state!.status == PlaybackStatus.stopped) {
      return device.info.client;
    }

    return [item.title, item.artist].nonNulls.join(' · ');
  }
}
