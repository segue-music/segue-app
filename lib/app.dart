import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'l10n/app_localizations.dart';
import 'language_choice.dart';
import 'player/audio_interruptions.dart';
import 'player/media_controls.dart';
import 'services.dart';
import 'session.dart';
import 'settings.dart';
import 'theme_choice.dart';
import 'ui/app/home_page.dart';
import 'ui/app/login_page.dart';
import 'ui/app/shortcuts.dart';
import 'ui/app/television_screen.dart';
import 'ui/app/theme.dart';
import 'ui/app/theme_fade.dart';
import 'ui/app/title_bar.dart';
import 'ui/player/failed_song_message.dart';
import 'ui/widgets/spinner.dart';

class SegueApp extends StatefulWidget {
  const SegueApp({
    required this.session,
    this.settings,
    this.mediaControls,
    this.interruptions,
    this.television = false,
    this.packageInfo,
    super.key,
  });

  /// The saved session, if any: then the app opens straight on the library.
  final Session? session;

  /// What the user picked for the app, as the last launch left it; with none, each choice's default until a pick.
  final Settings? settings;

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

  /// The session of the app closed by [_close], which starts again as its screen shows again; null, it isn't closed.
  Session? _closed;
  late final AppLifecycleListener _lifecycle;

  /// [SegueApp.settings], or the app's own, each choice its default until a pick.
  late final _settings = widget.settings ?? Settings();

  @override
  void initState() {
    super.initState();
    widget.mediaControls
      ?..close = _close
      ..open = _reopen;
    _lifecycle = AppLifecycleListener(onResume: _reopen, onExitRequested: _exit);
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
      final services = await Services.start(session, settings: _settings);

      if (!mounted) {
        await services.dispose();
        return;
      }

      setState(() => _services = services);
      widget.mediaControls?.attach(
        services.connect,
        services.api,
        favorites: services.favorites,
        reachability: services.reachability,
      );
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

  /// Closes the app, swiped out of Android's recent apps ([MediaControls.close]) or its window closed on a computer
  /// ([_exit]): the music this device plays stops, paused where it was, which the hub keeps as the last playback, so
  /// that the app opens on it again; another device's plays on. The system's media controls let go of it, and the hub
  /// hears it leave. On Android the process stays, with nothing running, until Android ends it or the app opens again in
  /// it ([_reopen]): ended at once, it would come back without a screen, as the system's media controls look for music
  /// to resume in it, and with it the app, signed in to the hub and showing its music there.
  Future<void> _close() async {
    final services = _services;

    if (services == null) {
      return;
    }

    await services.player.pause();
    widget.mediaControls?.attach(null, null);
    widget.interruptions?.attach(null);

    if (mounted) {
      setState(() {
        _services = null;
        _closed = services.session;
      });
    }

    await services.dispose();
  }

  /// The window closed on a computer: the app closes ([_close]) before Flutter ends it. Ended with mpv still playing,
  /// it aborted, often: mpv went on calling the Dart that had ended (media_kit's wakeup callback), which disposing its
  /// players stops. A close that takes too long, the hub not answering, doesn't keep the window open.
  Future<AppExitResponse> _exit() async {
    await _close().timeout(const Duration(seconds: 3), onTimeout: () {});

    return AppExitResponse.exit;
  }

  /// The app closed by [_close] opens again, its screen showing or for a play from the system's media controls: it starts
  /// as it does in a process of its own.
  void _reopen() {
    final session = _closed;

    if (session != null) {
      _closed = null;
      unawaited(_start(session));
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
    if (widget.settings == null) {
      _settings.dispose();
    }

    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Listenable.merge([_settings.theme, _settings.language]), builder: _app);

  /// The app, in the theme and the language picked.
  Widget _app(BuildContext context, Widget? _) {
    final services = _services;
    final ThemeSettings(:mode, :palette, :highContrast) = _settings.theme.value;
    final mediaControls = widget.mediaControls;

    return MaterialApp(
      title: 'Segue',
      debugShowCheckedModeBanner: false,
      // The app's words, and Material's own, in the language picked, or the system's.
      locale: _settings.language.value,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: LanguageChoice.resolve,
      theme: segueTheme(Brightness.light, palette: palette, highContrast: highContrast),
      darkTheme: segueTheme(Brightness.dark, palette: palette, highContrast: highContrast),
      themeMode: mode,
      // At once, under the app in the old theme fading away (ThemeFade), rather than each color going to the new one's on
      // its own, which would build the app again on every frame.
      themeAnimationDuration: Duration.zero,
      // Above the navigator, so that every page and sheet sees the settings, the services and the shortcuts.
      builder: (context, child) {
        final page = TelevisionScreen(
          enabled: widget.television,
          child: TextFieldArrowShortcuts(
            // Esc goes back from a page before it takes the focus off what has it there.
            child: UnfocusShortcut(child: BackShortcut(child: child!)),
          ),
        );

        final app = SettingsScope(
          settings: _settings,
          child: ThemeFade(
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
          ),
        );

        return mediaControls == null ? app : _MediaControlsStrings(controls: mediaControls, child: app);
      },
      home: services != null
          ? HomePage(onSignOut: _signOut, packageInfo: widget.packageInfo)
          : _starting || _closed != null
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
          : LoginPage(onSignedIn: _start),
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
