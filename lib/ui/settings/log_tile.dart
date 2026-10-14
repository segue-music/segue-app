import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../log_file.dart';
import '../widgets/directional_navigation.dart';
import '../widgets/themed_icon.dart';

final _log = Logger('LogTile');

/// The settings' line of the app's log ([LogFile]; README.md, "Logs"), with what it has and hasn't under it, for
/// whoever sends it. On a phone or a tablet it shares the log through the system's share sheet (an e-mail, a chat, the
/// files), as one file named for the device ([deviceName]) and the time; on a computer it opens the log's folder, the
/// files there to attach. None on a TV ([available]), whose share sheet has nowhere to go: `adb pull` takes it there.
class LogTile extends StatelessWidget {
  const LogTile(this.log, {required this.deviceName, super.key});

  final LogFile log;

  /// This device's name, as the other devices see it.
  final String deviceName;

  /// Whether this device has the line: not a TV.
  static bool available(BuildContext context) => !context.television;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final platform = Theme.of(context).platform;
    final shares = platform == TargetPlatform.android || platform == TargetPlatform.iOS;

    return ListTile(
      leading: ThemedIcon(shares ? HugeIcons.strokeRoundedFileExport : HugeIcons.strokeRoundedFolderOpen),
      title: Text(shares ? strings.shareLog : strings.openLogFolder),
      subtitle: Text(strings.logDetail),
      onTap: () => shares ? _share(context) : _open(context),
    );
  }

  Future<void> _share(BuildContext context) async {
    // Where the sheet comes out of, on an iPad: this line.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppLocalizations.of(context);

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(await log.read(), mimeType: 'text/plain')],
          fileNameOverrides: [logName(deviceName, clock.now())],
          sharePositionOrigin: origin,
        ),
      );
    } on Object catch (e) {
      _log.warning('log not shared', e);
      messenger.showSnackBar(SnackBar(content: Text(strings.logFailed)));
    }
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppLocalizations.of(context);
    var opened = false;

    try {
      opened = await launchUrl(Uri.directory(log.directory.path));
    } on Object catch (e) {
      _log.warning('log folder not opened', e);
    }

    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(strings.logFailed)));
    }
  }
}

/// The name of the log [deviceName] shares at [time], `segue-log-living-room-2026-10-14-1530.txt`: the device's name in
/// its letters and digits alone, lowercase, whatever takes the file.
String logName(String deviceName, DateTime time) {
  String twoDigits(int number) => '$number'.padLeft(2, '0');

  final words = deviceName
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((word) => word.isNotEmpty);
  final date =
      '${time.year}-${twoDigits(time.month)}-${twoDigits(time.day)}-${twoDigits(time.hour)}${twoDigits(time.minute)}';

  return ['segue-log', ...words, '$date.txt'].join('-');
}
