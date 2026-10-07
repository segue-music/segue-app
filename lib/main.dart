import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'player/audio_interruptions.dart';
import 'player/media_controls.dart';
import 'session.dart';
import 'device.dart';
import 'language_choice.dart';
import 'theme_choice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final television = await adaptToTelevision();
  final controls = await MediaControls.start();
  final interruptions = await AudioInterruptions.start();
  runApp(
    SegueApp(
      session: await Session.load(),
      themeChoice: await ThemeChoice.load(),
      languageChoice: await LanguageChoice.load(),
      mediaControls: controls,
      interruptions: interruptions,
      television: television,
    ),
  );
}
