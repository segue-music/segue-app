import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../segue/protocol.dart';
import '../services.dart';

import 'equalizer.dart';
import 'errors.dart';
import 'themed_icon.dart';

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
    final client = connect.client;

    Future<void> act(Future<Result> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final result = await action();

      if (result.ok) {
        navigator.pop();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(describeError(result.error))));
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
            child: Text('Conectar a um aparelho', style: Theme.of(context).textTheme.titleLarge),
          ),
          ListTile(
            leading: ThemedIcon(_thisDeviceIcon(context)),
            title: Text('Este aparelho (${services.session.deviceName})'),
            selected: connect.activeId == null,
            trailing: _marks(playing: connect.player.playing, active: connect.activeId == null),
            onTap: () => act(() => connect.switchTo(null)),
          ),
          if (client == null)
            ListTile(
              leading: const ThemedIcon(HugeIcons.strokeRoundedInformationCircle),
              title: const Text('Nenhum hub encontrado'),
              subtitle: Text('Sem o hub em ${services.session.server.host}, só dá para tocar aqui.'),
            ),
          for (final device in connect.devices)
            ListTile(
              leading: const ThemedIcon(HugeIcons.strokeRoundedSpeaker),
              title: Text(device.info.name),
              subtitle: Text(_describe(device)),
              selected: connect.activeId == device.id,
              trailing: _marks(playing: connect.playingId == device.id, active: connect.activeId == device.id),
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
    if (MediaQuery.navigationModeOf(context) == NavigationMode.directional) {
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

  /// Which device plays (equalizer) and which one the app controls (check).
  static Widget? _marks({required bool playing, required bool active}) {
    if (!playing && !active) {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [if (playing) const Equalizer(), if (active) const ThemedIcon(HugeIcons.strokeRoundedTick02)],
    );
  }

  static String _describe(Device device) {
    final item = device.state?.current;
    final what = item == null ? null : [item.title, item.artist].nonNulls.join(' · ');
    return switch (device.state?.status) {
      PlaybackStatus.playing => 'Tocando: $what',
      PlaybackStatus.paused => 'Pausado: $what',
      _ => device.info.client,
    };
  }
}
