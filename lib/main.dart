import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'autoplay_choice.dart';
import 'crossfade_choice.dart';
import 'player/audio_interruptions.dart';
import 'player/libmpv_licenses.dart';
import 'player/media_controls.dart';
import 'session.dart';
import 'device.dart';
import 'equalizer_choice.dart';
import 'language_choice.dart';
import 'download_choice.dart';
import 'quality_choice.dart';
import 'replay_gain_choice.dart';
import 'theme_choice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  addLibmpvLicenses();
  final television = await adaptToTelevision();
  final controls = await MediaControls.start();
  final interruptions = await AudioInterruptions.start();
  runApp(
    SegueApp(
      session: await Session.load(),
      themeChoice: await ThemeChoice.load(),
      languageChoice: await LanguageChoice.load(),
      qualityChoice: await QualityChoice.load(),
      downloadChoice: await DownloadChoice.load(),
      replayGainChoice: await ReplayGainChoice.load(),
      equalizerChoice: await EqualizerChoice.load(),
      autoplayChoice: await AutoplayChoice.load(),
      crossfadeChoice: await CrossfadeChoice.load(),
      mediaControls: controls,
      interruptions: interruptions,
      television: television,
      packageInfo: await PackageInfo.fromPlatform(),
    ),
  );
}
