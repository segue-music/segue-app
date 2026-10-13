import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'player/audio_interruptions.dart';
import 'player/libmpv_licenses.dart';
import 'player/media_controls.dart';
import 'session.dart';
import 'settings.dart';
import 'device.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  addLibmpvLicenses();
  final television = await adaptToTelevision();
  // The system's media service before the session and the settings are read: as the app starts for Android Auto,
  // audio_service drops, unanswered, what the car asks before there is a handler.
  final controls = await MediaControls.start();
  final interruptions = await AudioInterruptions.start();
  runApp(
    SegueApp(
      session: await Session.load(),
      settings: await Settings.load(),
      mediaControls: controls,
      interruptions: interruptions,
      television: television,
      packageInfo: await PackageInfo.fromPlatform(),
    ),
  );
}
