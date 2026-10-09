import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'l10n/app_localizations.dart';
import 'language_choice.dart';
import 'player/audio_interruptions.dart';
import 'player/media_controls.dart';
import 'quality_choice.dart';
import 'replay_gain_choice.dart';
import 'services.dart';
import 'session.dart';
import 'theme_choice.dart';
import 'ui/failed_song_message.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/shortcuts.dart';
import 'ui/spinner.dart';
import 'ui/theme.dart';
import 'ui/theme_fade.dart';
import 'ui/title_bar.dart';

class SegueApp extends StatefulWidget {
  const SegueApp({
    required this.session,
    this.themeChoice,
    this.languageChoice,
    this.qualityChoice,
    this.replayGainChoice,
    this.mediaControls,
    this.interruptions,
    this.television = false,
    this.packageInfo,
    super.key,
  });

  /// The saved session, if any: then the app opens straight on the library.
  final Session? session;

  /// The theme picked, light or dark; with none, the app follows the system's.
  final ThemeChoice? themeChoice;

  /// The language picked; with none, the app follows the system's.
  final LanguageChoice? languageChoice;

  /// The quality the player streams in; with none, the original, until a pick.
  final QualityChoice? qualityChoice;

  /// How the player levels the songs' loudness; with none, not at all, until a pick.
  final ReplayGainChoice? replayGainChoice;

  /// The system's media controls, where the platform has them.
  final MediaControls? mediaControls;

  /// Calls and the like pausing this device's playback, where the platform has them.
  final AudioInterruptions? interruptions;

  /// Whether it runs on a TV, driven by a remote's D-pad.
  final bool television;

  /// The app's version and build number, which the settings show; none, no line of them.
  final PackageInfo? packageInfo;

  @override
  State<SegueApp> createState() => _SegueAppState();
}

class _SegueAppState extends State<SegueApp> {
  Services? _services;
  bool _starting = false;
  Object? _error;

  /// [SegueApp.themeChoice], or one of its own, which follows the system's until a pick.
  late final _themeChoice = widget.themeChoice ?? ThemeChoice();

  /// [SegueApp.languageChoice], or one of its own, which follows the system's until a pick.
  late final _languageChoice = widget.languageChoice ?? LanguageChoice();

  /// [SegueApp.qualityChoice], or one of its own, the original until a pick.
  late final _qualityChoice = widget.qualityChoice ?? QualityChoice();

  /// [SegueApp.replayGainChoice], or one of its own, off until a pick.
  late final _replayGainChoice = widget.replayGainChoice ?? ReplayGainChoice();

  @override
  void initState() {
    super.initState();
    final session = widget.session;

    if (session != null) {
      _start(session);
    }
  }

  Future<void> _start(Session session) async {
    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      final services = await Services.start(session, quality: _qualityChoice, replayGain: _replayGainChoice);

      if (!mounted) {
        await services.dispose();
        return;
      }

      setState(() => _services = services);
      widget.mediaControls?.attach(services.connect, services.api);
      widget.interruptions?.attach(services.player);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _signOut() async {
    final services = _services;
    setState(() {
      _services = null;
      _error = null;
    });
    widget.mediaControls?.attach(null, null);
    widget.interruptions?.attach(null);
    await services?.api.signOut();
    await services?.dispose();
    await Session.clear();
  }

  @override
  void dispose() {
    if (widget.themeChoice == null) {
      _themeChoice.dispose();
    }

    if (widget.languageChoice == null) {
      _languageChoice.dispose();
    }

    if (widget.qualityChoice == null) {
      _qualityChoice.dispose();
    }

    if (widget.replayGainChoice == null) {
      _replayGainChoice.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Listenable.merge([_themeChoice, _languageChoice]), builder: _app);

  /// The app, in the theme and the language picked.
  Widget _app(BuildContext context, Widget? _) {
    final services = _services;
    final mediaControls = widget.mediaControls;
    return MaterialApp(
      title: 'Segue',
      debugShowCheckedModeBanner: false,
      // The app's words, and Material's own, in the language picked, or the system's.
      locale: _languageChoice.value,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: LanguageChoice.resolve,
      theme: segueTheme(Brightness.light),
      darkTheme: segueTheme(Brightness.dark),
      themeMode: _themeChoice.value,
      // At once, under the app in the old theme fading away (ThemeFade), rather than each color going to the new one's on
      // its own, which would build the app again on every frame.
      themeAnimationDuration: Duration.zero,
      // Above the navigator, so that every page and sheet sees the services and the shortcuts.
      builder: (context, child) {
        final page = DirectionalNavigation(
          enabled: widget.television,
          child: TextFieldArrowShortcuts(
            child: BackShortcut(child: UnfocusShortcut(child: child!)),
          ),
        );

        final app = ThemeFade(
          child: ThemedTitleBar(
            child: services == null
                ? page
                : ServicesScope(
                    services: services,
                    // The media keys, too, where no system media session takes them.
                    child: PlaybackShortcuts(
                      mediaKeys: widget.mediaControls == null,
                      child: FailedSongMessage(child: page),
                    ),
                  ),
          ),
        );
        return mediaControls == null ? app : _MediaControlsStrings(controls: mediaControls, child: app);
      },
      home: services != null
          ? HomePage(
              onSignOut: _signOut,
              themeChoice: _themeChoice,
              languageChoice: _languageChoice,
              qualityChoice: _qualityChoice,
              replayGainChoice: _replayGainChoice,
              packageInfo: widget.packageInfo,
            )
          : _starting
          ? const Scaffold(body: Center(child: Spinner()))
          : _error != null
          ? Builder(
              builder: (context) {
                final strings = AppLocalizations.of(context);
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(strings.couldNotStart('$_error')),
                        TextButton(onPressed: _signOut, child: Text(strings.signOut)),
                      ],
                    ),
                  ),
                );
              },
            )
          : LoginPage(onSignedIn: _start, languageChoice: _languageChoice),
    );
  }
}

/// Gives the system's media controls the app's words, in the language it shows, and again as it shows another.
class _MediaControlsStrings extends StatefulWidget {
  const _MediaControlsStrings({required this.controls, required this.child});

  final MediaControls controls;
  final Widget child;

  @override
  State<_MediaControlsStrings> createState() => _MediaControlsStringsState();
}

class _MediaControlsStringsState extends State<_MediaControlsStrings> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.controls.strings = AppLocalizations.of(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
