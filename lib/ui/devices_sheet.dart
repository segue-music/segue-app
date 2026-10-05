import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../segue/protocol.dart';
import '../services.dart';

import 'errors.dart';

/// The device picker: pick where the music plays.
Future<void> showDevicesSheet(BuildContext context) =>
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const _DevicesSheet());

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
            leading: const Icon(HugeIcons.strokeRoundedComputer),
            title: Text('Este aparelho (${services.session.deviceName})'),
            selected: connect.activeId == null,
            trailing: _marks(playing: connect.player.playing, active: connect.activeId == null),
            onTap: () => act(() => connect.switchTo(null)),
          ),
          if (client == null)
            ListTile(
              leading: const Icon(HugeIcons.strokeRoundedInformationCircle),
              title: const Text('Nenhum hub encontrado'),
              subtitle: Text('Sem o hub em ${services.session.server.host}, só dá para tocar aqui.'),
            ),
          for (final device in connect.devices)
            ListTile(
              leading: const Icon(HugeIcons.strokeRoundedSpeaker),
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

  /// Which device plays (equalizer) and which one the app controls (check).
  static Widget? _marks({required bool playing, required bool active}) {
    if (!playing && !active) {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (playing) const Icon(HugeIcons.strokeRoundedAudioWave01),
        if (active) const Icon(HugeIcons.strokeRoundedTick02),
      ],
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
