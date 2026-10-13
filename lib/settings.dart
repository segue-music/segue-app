import 'package:flutter/widgets.dart';

import 'autoplay_choice.dart';
import 'crossfade_choice.dart';
import 'download_choice.dart';
import 'equalizer_choice.dart';
import 'language_choice.dart';
import 'quality_choice.dart';
import 'replay_gain_choice.dart';
import 'theme_choice.dart';
import 'volume_choice.dart';

/// What the user picks for the app, each choice kept across launches (and sign-outs): this device's, not the account's,
/// and there before a sign-in, as the theme and the language are. A choice not given is its own default until a pick.
class Settings {
  Settings({
    ThemeChoice? theme,
    LanguageChoice? language,
    QualityChoice? quality,
    DownloadChoice? download,
    ReplayGainChoice? replayGain,
    EqualizerChoice? equalizer,
    AutoplayChoice? autoplay,
    CrossfadeChoice? crossfade,
    VolumeChoice? volume,
  }) : theme = theme ?? ThemeChoice(),
       language = language ?? LanguageChoice(),
       quality = quality ?? QualityChoice(),
       download = download ?? DownloadChoice(),
       replayGain = replayGain ?? ReplayGainChoice(),
       equalizer = equalizer ?? EqualizerChoice(),
       autoplay = autoplay ?? AutoplayChoice(),
       crossfade = crossfade ?? CrossfadeChoice(),
       volume = volume ?? VolumeChoice();

  /// Each choice as picked last, all read at once rather than one after the other, as the app opens.
  static Future<Settings> load() async {
    final (theme, language, quality, download, replayGain, equalizer, autoplay, crossfade, volume) = await (
      ThemeChoice.load(),
      LanguageChoice.load(),
      QualityChoice.load(),
      DownloadChoice.load(),
      ReplayGainChoice.load(),
      EqualizerChoice.load(),
      AutoplayChoice.load(),
      CrossfadeChoice.load(),
      VolumeChoice.load(),
    ).wait;

    return Settings(
      theme: theme,
      language: language,
      quality: quality,
      download: download,
      replayGain: replayGain,
      equalizer: equalizer,
      autoplay: autoplay,
      crossfade: crossfade,
      volume: volume,
    );
  }

  /// The theme the app shows: light, dark or the system's, its colors and its contrast.
  final ThemeChoice theme;

  /// The language the app shows.
  final LanguageChoice language;

  /// The quality the player streams in.
  final QualityChoice quality;

  /// How the app downloads: in which quality, and whether over mobile data too.
  final DownloadChoice download;

  /// How the player levels the songs' loudness.
  final ReplayGainChoice replayGain;

  /// The equalizer the player plays through.
  final EqualizerChoice equalizer;

  /// Whether the player goes on after the queue's last song with songs like it.
  final AutoplayChoice autoplay;

  /// How long the player crossfades the songs for.
  final CrossfadeChoice crossfade;

  /// This device's volume, which the player starts at.
  final VolumeChoice volume;

  void dispose() {
    for (final choice in <ChangeNotifier>[
      theme,
      language,
      quality,
      download,
      replayGain,
      equalizer,
      autoplay,
      crossfade,
      volume,
    ]) {
      choice.dispose();
    }
  }
}

/// Hands the settings down the tree, to the pages that pick them. It sits above the navigator (`app.dart`), as the
/// settings outlive a sign-in: the sign-in's page picks the language too.
class SettingsScope extends InheritedWidget {
  const SettingsScope({required this.settings, required super.child, super.key});

  final Settings settings;

  /// The settings above [context]; null where there are none, and then no way to pick them, as in tests that give none.
  static Settings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.settings;

  @override
  bool updateShouldNotify(SettingsScope oldWidget) => settings != oldWidget.settings;
}
