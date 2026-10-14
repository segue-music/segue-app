import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'player/audio_interruptions.dart';
import 'player/libmpv_licenses.dart';
import 'player/media_controls.dart';
import 'session.dart';
import 'settings.dart';
import 'device.dart';
import 'log_file.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final packageInfo = await PackageInfo.fromPlatform();
  // Before anything else, so that the log has what goes wrong as the app starts.
  final log = await startLogging(packageInfo);

  MediaKit.ensureInitialized();
  addLibmpvLicenses();

  final television = await adaptToTelevision();
  // The system's media service before the session and the settings are read: as the app starts for Android Auto,
  // audio_service drops, unanswered, what the car asks before there is a handler.
  final controls = await MediaControls.start();
  final interruptions = await AudioInterruptions.start();

  if (television) {
    Logger('Segue').info('on a TV');
  }

  runApp(
    SegueApp(
      session: await Session.load(),
      settings: await Settings.load(),
      mediaControls: controls,
      interruptions: interruptions,
      television: television,
      packageInfo: packageInfo,
      log: log,
    ),
  );
}
