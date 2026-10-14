import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../crossfade_choice.dart';
import '../../download_choice.dart';
import '../../l10n/app_localizations.dart';
import '../../log_file.dart';
import '../../quality_choice.dart';
import '../../replay_gain_choice.dart';
import '../../services.dart';
import '../../settings.dart';
import '../../theme_choice.dart';
import '../player/autoplay_switch.dart';
import 'downloads_page.dart';
import 'equalizer_page.dart';
import 'language_button.dart';
import 'licenses_page.dart';
import 'log_tile.dart';
import '../app/page_area.dart';
import '../app/theme.dart';
import '../app/theme_fade.dart';
import '../widgets/themed_icon.dart';
import 'sign_in_tv_page.dart';

/// What the user picks for the app, and signing out, in groups under their names: the appearance (the theme, its colors
/// and its contrast, the language), the playback (the quality, the volume's normalization, the equalizer's page, the
/// crossfade, autoplay) and the app itself (its version, its log, the licenses' page); a line between the groups, and
/// after the last, signing out, under the account it signs out of. Each choice is a line that says the option picked,
/// which opens a sheet of them all ([_Choice]), or, on or off, a switch. In the page area, from the top bar's button;
/// with no settings (SettingsScope), no choice's line, nor a group left with none, and with no version or no log, no
/// line of it.
class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.onSignOut, this.packageInfo, this.log, super.key});

  final VoidCallback onSignOut;

  /// The app's version and build number, as the build stamped them.
  final PackageInfo? packageInfo;

  /// The app's log, which a line shares or opens the folder of ([LogTile]).
  final LogFile? log;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = ServicesScope.of(context).session;
    final downloads = ServicesScope.of(context).downloads;
    final settings = SettingsScope.maybeOf(context);
    final packageInfo = this.packageInfo;
    final log = this.log;

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
        // A line says the option picked last.
        listenable: Listenable.merge([
          settings?.theme,
          settings?.language,
          settings?.quality,
          settings?.replayGain,
          settings?.equalizer,
          settings?.crossfade,
          settings?.download,
        ]),
        builder: (context, _) {
          final groups = [
            (
              strings.appearance,
              [
                if (settings != null) ...[
                  // The old theme fades into the new one, whatever changes it.
                  _Choice(
                    icon: HugeIcons.strokeRoundedContrast,
                    title: strings.theme,
                    options: [
                      for (final (mode, name) in [
                        (ThemeMode.system, strings.systemTheme),
                        (ThemeMode.light, strings.lightTheme),
                        (ThemeMode.dark, strings.darkTheme),
                      ])
                        (
                          name: name,
                          detail: null,
                          leading: null,
                          picked: mode == settings.theme.value.mode,
                          onPicked: () {
                            ThemeFade.start(context);
                            settings.theme.pickMode(mode);
                          },
                        ),
                    ],
                  ),
                  // Each palette with what it is under it, and its colors beside it, in the theme shown, light or dark.
                  _Choice(
                    icon: HugeIcons.strokeRoundedPaintBoard,
                    title: strings.themeColors,
                    options: [
                      for (final palette in Palette.values)
                        (
                          name: strings.palette(palette.name),
                          detail: strings.paletteDetail(palette.name),
                          leading: _PaletteSwatch(
                            segueColors(
                              Theme.of(context).brightness,
                              palette: palette,
                              highContrast: settings.theme.value.highContrast,
                            ),
                          ),
                          picked: palette == settings.theme.value.palette,
                          onPicked: () {
                            ThemeFade.start(context);
                            settings.theme.pickPalette(palette);
                          },
                        ),
                    ],
                  ),
                  SwitchListTile(
                    secondary: const ThemedIcon(HugeIcons.strokeRoundedView),
                    title: Text(strings.highContrast),
                    subtitle: Text(strings.highContrastDetail),
                    value: settings.theme.value.highContrast,
                    onChanged: (on) {
                      ThemeFade.start(context);
                      settings.theme.turnHighContrast(on);
                    },
                  ),
                  _Choice(
                    icon: HugeIcons.strokeRoundedTranslate,
                    title: strings.language,
                    options: [
                      for (final (language, name) in LanguageButton.options(strings))
                        (
                          name: name,
                          detail: null,
                          leading: null,
                          picked: language?.languageCode == settings.language.value?.languageCode,
                          onPicked: () => settings.language.pick(language),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            (
              strings.playback,
              [
                if (settings != null) ...[
                  // The automatic quality with what it does, under it.
                  _Choice(
                    icon: HugeIcons.strokeRoundedAudioWave01,
                    title: strings.audioQuality,
                    options: [
                      for (final quality in settings.quality.options)
                        (
                          name: strings.streamQuality(quality.name, quality.maxBitRate ?? 0),
                          detail: quality == StreamQuality.automatic
                              ? strings.automaticQualityDetail(
                                  StreamQuality.automatic.inUse(onMobileData: true).maxBitRate!,
                                )
                              : null,
                          leading: null,
                          picked: quality == settings.quality.value,
                          onPicked: () => settings.quality.pick(quality),
                        ),
                    ],
                  ),
                  // Each way with what it does, under it.
                  _Choice(
                    icon: HugeIcons.strokeRoundedVolumeHigh,
                    title: strings.volumeNormalization,
                    options: [
                      for (final mode in ReplayGainMode.values)
                        (
                          name: strings.replayGainMode(mode.name),
                          detail: strings.replayGainModeDetail(mode.name),
                          leading: null,
                          picked: mode == settings.replayGain.value,
                          onPicked: () => settings.replayGain.pick(mode),
                        ),
                    ],
                  ),
                  // The equalizer, a page of its own in the page area, with the curve it plays with under its name.
                  ListTile(
                    leading: const ThemedIcon(HugeIcons.strokeRoundedSlidersVertical),
                    title: Text(strings.equalizer),
                    subtitle: Text(
                      settings.equalizer.value.on
                          ? strings.equalizerPreset(settings.equalizer.value.preset.name)
                          : strings.equalizerOff,
                    ),
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => EqualizerPage(choice: settings.equalizer))),
                  ),
                  // None with what it does, under it.
                  _Choice(
                    icon: HugeIcons.strokeRoundedBlend,
                    title: strings.crossfade,
                    options: [
                      for (final length in CrossfadeChoice.lengths)
                        (
                          name: strings.crossfadeLength(length.inSeconds),
                          detail: length == Duration.zero ? strings.crossfadeOffDetail : null,
                          leading: null,
                          picked: length == settings.crossfade.value,
                          onPicked: () => settings.crossfade.pick(length),
                        ),
                    ],
                  ),
                  AutoplaySwitch(settings.autoplay),
                ],
              ],
            ),
            // How the app downloads, and what it has downloaded, where it downloads.
            (
              strings.downloads,
              [
                if (downloads != null && settings != null) ...[
                  _Choice(
                    icon: HugeIcons.strokeRoundedAudioWave01,
                    title: strings.downloadQuality,
                    options: [
                      for (final quality in DownloadChoice.qualities)
                        (
                          name: strings.streamQuality(quality.name, quality.maxBitRate ?? 0),
                          detail: null,
                          leading: null,
                          picked: quality == settings.download.value.quality,
                          onPicked: () => settings.download.pickQuality(quality),
                        ),
                    ],
                  ),
                  // Only where the device has mobile data, which it waits off until it is turned on.
                  if (settings.download.mobileData)
                    SwitchListTile(
                      secondary: const ThemedIcon(HugeIcons.strokeRoundedWifiDisconnected02),
                      title: Text(strings.downloadOnMobileData),
                      subtitle: Text(strings.downloadOnMobileDataDetail),
                      value: settings.download.value.onMobileData,
                      onChanged: settings.download.pickOnMobileData,
                    ),
                ],
                // The albums and playlists downloaded, a page of their own in the page area, with the room they take under
                // its name.
                if (downloads != null)
                  ListTile(
                    leading: const ThemedIcon(HugeIcons.strokeRoundedDownload04),
                    title: Text(strings.downloadedAlbums),
                    subtitle: DownloadsSize(downloads),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsPage())),
                  ),
              ],
            ),
            // The app's version, its log, and its licenses and those of what it is made with, a page of their own in the page
            // area.
            (
              strings.about,
              [
                if (packageInfo != null)
                  ListTile(
                    leading: const ThemedIcon(HugeIcons.strokeRoundedInformationCircle),
                    title: Text(strings.appVersion),
                    subtitle: Text(strings.appVersionNumber(packageInfo.version, packageInfo.buildNumber)),
                  ),
                if (log != null && LogTile.available(context)) LogTile(log, deviceName: session.deviceName),
                ListTile(
                  leading: const ThemedIcon(HugeIcons.strokeRoundedLicense),
                  title: Text(strings.openSourceLicenses),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LicensesPage())),
                ),
              ],
            ),
          ];

          return ListView(
            children: [
              for (final (name, lines) in groups)
                if (lines.isNotEmpty) ...[_Heading(name), ...lines, const Divider(height: 33)],
              // With the sign-in, as signing out is: on a phone, signing a TV in with it, by the code the TV shows.
              if (SignInTvPage.available(context))
                ListTile(
                  leading: const ThemedIcon(HugeIcons.strokeRoundedQrCode),
                  title: Text(strings.signInTv),
                  subtitle: Text(strings.signInTvDetail),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignInTvPage())),
                ),
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

/// An option of a [_Choice]: its name, what it does where it says, what shows before it where something does, whether
/// it is the one picked, and what picks it.
typedef _ChoiceOption = ({String name, String? detail, Widget? leading, bool picked, VoidCallback onPicked});

/// A choice: a line with its [icon] and [title], which says the option picked, under it. A tap opens a sheet of its
/// [options] over the window, under its title, each with what it does under it where it says, the one picked with a
/// check, as the devices' sheet has the one the app controls. A pick closes it.
class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.options});

  final HugeIconData icon;
  final String title;
  final List<_ChoiceOption> options;

  @override
  Widget build(BuildContext context) {
    final picked = options.where((option) => option.picked).firstOrNull;

    return ListTile(
      leading: ThemedIcon(icon),
      title: Text(title),
      subtitle: picked == null ? null : Text(picked.name),
      onTap: () => _open(context),
    );
  }

  /// The sheet, over the window, also from the home's page area.
  void _open(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    // As tall as its options, up to the whole screen, where they scroll.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title, style: Theme.of(sheet).textTheme.titleLarge),
        ),
        for (final (:name, :detail, :leading, :picked, :onPicked) in options)
          _Option(
            name,
            detail: detail,
            leading: leading,
            picked: picked,
            onTap: () {
              onPicked();
              Navigator.of(sheet).pop();
            },
          ),
      ],
    ),
  );
}

/// The name over a group of lines.
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

/// One of a choice's options, in its sheet, the one [picked] with a check and in the theme's color; [detail] under it,
/// what it does, and [leading] before it.
class _Option extends StatelessWidget {
  const _Option(this.name, {required this.picked, required this.onTap, this.detail, this.leading});

  final String name;
  final String? detail;
  final Widget? leading;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;

    return ListTile(
      leading: leading,
      title: Text(name),
      subtitle: detail == null ? null : Text(detail),
      selected: picked,
      trailing: picked ? const ThemedIcon(HugeIcons.strokeRoundedTick02) : null,
      onTap: onTap,
    );
  }
}

/// A palette's [colors] in small, before its name: a circle of its background and its bars, half and half, with a dot of
/// its pink in the middle, and around it a line in the colors shown, so that it stands out of the sheet whatever its
/// own.
class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch(this.colors);

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.surface, colors.surface, colors.surfaceContainerHighest, colors.surfaceContainerHighest],
        stops: const [0, 0.5, 0.5, 1],
      ),
    ),
    child: Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.primary),
    ),
  );
}
