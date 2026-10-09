import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../equalizer_choice.dart';
import '../l10n/app_localizations.dart';
import '../language_choice.dart';
import '../quality_choice.dart';
import '../replay_gain_choice.dart';
import '../services.dart';
import '../theme_choice.dart';
import 'equalizer_page.dart';
import 'language_button.dart';
import 'licenses_page.dart';
import 'page_area.dart';
import 'theme_fade.dart';
import 'themed_icon.dart';

/// What the user picks for the app, and signing out: the theme (the system's again too), the language, the quality, the
/// volume's normalization, the equalizer's page, the app's version, the licenses' page and, last, signing out, under the
/// account it signs out of. Each kind of choice a group of its own, under its name, the one picked with a check, as the
/// devices' sheet has the one the app controls; a line between the groups, and between the last and signing out. In the
/// page area, from the top bar's button; a choice missing (none given), its group too, and the version with none.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.onSignOut,
    this.themeChoice,
    this.languageChoice,
    this.qualityChoice,
    this.replayGainChoice,
    this.equalizerChoice,
    this.packageInfo,
    super.key,
  });

  final VoidCallback onSignOut;
  final ThemeChoice? themeChoice;
  final LanguageChoice? languageChoice;
  final QualityChoice? qualityChoice;
  final ReplayGainChoice? replayGainChoice;
  final EqualizerChoice? equalizerChoice;

  /// The app's version and build number, as the build stamped them.
  final PackageInfo? packageInfo;

  /// The qualities to pick from, each by its name, and the automatic one with what it does.
  static List<({StreamQuality quality, String name, String? detail})> _qualities(AppLocalizations strings) => [
    for (final quality in StreamQuality.values)
      (
        quality: quality,
        name: strings.streamQuality(quality.name, quality.maxBitRate ?? 0),
        detail: quality == StreamQuality.automatic
            ? strings.automaticQualityDetail(StreamQuality.automatic.inUse(onMobileData: true).maxBitRate!)
            : null,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = ServicesScope.of(context).session;
    final (themeChoice, languageChoice, qualityChoice, replayGainChoice, equalizerChoice) = (
      this.themeChoice,
      this.languageChoice,
      this.qualityChoice,
      this.replayGainChoice,
      this.equalizerChoice,
    );
    final packageInfo = this.packageInfo;
    return Scaffold(
      appBar: AppBar(
        // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
        automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
        centerTitle: true,
        title: Text(strings.settings),
      ),
      // In the page area, which has no player bar of its own: the home's bars stay under the page, the list ending clear
      // of them, by the room MediaQuery says they take.
      body: ListenableBuilder(
        // The check moves to the one picked.
        listenable: Listenable.merge([themeChoice, languageChoice, qualityChoice, replayGainChoice, equalizerChoice]),
        builder: (context, _) {
          final groups = [
            if (themeChoice != null)
              [
                _Heading(strings.theme),
                for (final (mode, name) in [
                  (ThemeMode.system, strings.systemTheme),
                  (ThemeMode.light, strings.lightTheme),
                  (ThemeMode.dark, strings.darkTheme),
                ])
                  _Option(
                    name,
                    picked: mode == themeChoice.value,
                    // The old theme fades into the new one.
                    onTap: () {
                      ThemeFade.start(context);
                      themeChoice.pick(mode);
                    },
                  ),
              ],
            if (languageChoice != null)
              [
                _Heading(strings.language),
                for (final (language, name) in LanguageButton.options(strings))
                  _Option(
                    name,
                    picked: language?.languageCode == languageChoice.value?.languageCode,
                    onTap: () => languageChoice.pick(language),
                  ),
              ],
            if (qualityChoice != null)
              [
                _Heading(strings.audioQuality),
                for (final (:quality, :name, :detail) in _qualities(strings))
                  _Option(
                    name,
                    detail: detail,
                    picked: quality == qualityChoice.value,
                    onTap: () => qualityChoice.pick(quality),
                  ),
              ],
            // Each way with what it does, under it.
            if (replayGainChoice != null)
              [
                _Heading(strings.volumeNormalization),
                for (final mode in ReplayGainMode.values)
                  _Option(
                    strings.replayGainMode(mode.name),
                    detail: strings.replayGainModeDetail(mode.name),
                    picked: mode == replayGainChoice.value,
                    onTap: () => replayGainChoice.pick(mode),
                  ),
              ],
            // The equalizer, a page of its own in the page area, with the curve it plays with under its name.
            if (equalizerChoice != null)
              [
                ListTile(
                  leading: const ThemedIcon(HugeIcons.strokeRoundedSlidersVertical),
                  title: Text(strings.equalizer),
                  subtitle: Text(
                    equalizerChoice.value.on
                        ? strings.equalizerPreset(equalizerChoice.value.preset.name)
                        : strings.equalizerOff,
                  ),
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => EqualizerPage(choice: equalizerChoice))),
                ),
              ],
            // The app's version, and its licenses and those of what it is made with, a page of their own in the page area.
            [
              if (packageInfo != null)
                ListTile(
                  leading: const ThemedIcon(HugeIcons.strokeRoundedInformationCircle),
                  title: Text(strings.appVersion),
                  subtitle: Text(strings.appVersionNumber(packageInfo.version, packageInfo.buildNumber)),
                ),
              ListTile(
                leading: const ThemedIcon(HugeIcons.strokeRoundedLicense),
                title: Text(strings.openSourceLicenses),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LicensesPage())),
              ),
            ],
          ];
          return ListView(
            children: [
              for (final group in groups) ...[...group, const Divider(height: 33)],
              ListTile(
                leading: const ThemedIcon(HugeIcons.strokeRoundedLogout01),
                title: Text(strings.signOut),
                subtitle: Text(strings.signedInAs(session.credentials.username, session.server.host)),
                onTap: onSignOut,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The name over a group of choices.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
      ),
    );
  }
}

/// One of a group's choices, the one [picked] with a check and in the theme's color; [detail] under it, what it does.
class _Option extends StatelessWidget {
  const _Option(this.name, {required this.picked, required this.onTap, this.detail});

  final String name;
  final String? detail;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return ListTile(
      title: Text(name),
      subtitle: detail == null ? null : Text(detail),
      selected: picked,
      trailing: picked ? const ThemedIcon(HugeIcons.strokeRoundedTick02) : null,
      onTap: onTap,
    );
  }
}
