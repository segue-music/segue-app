import 'package:flutter/material.dart';

import 'player/audio_interruptions.dart';
import 'player/media_controls.dart';
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
    this.mediaControls,
    this.interruptions,
    this.television = false,
    super.key,
  });

  /// The saved session, if any: then the app opens straight on the library.
  final Session? session;

  /// The theme picked, light or dark; with none, the app follows the system's.
  final ThemeChoice? themeChoice;

  /// The system's media controls, where the platform has them.
  final MediaControls? mediaControls;

  /// Calls and the like pausing this device's playback, where the platform has them.
  final AudioInterruptions? interruptions;

  /// Whether it runs on a TV, driven by a remote's D-pad.
  final bool television;

  @override
  State<SegueApp> createState() => _SegueAppState();
}

class _SegueAppState extends State<SegueApp> {
  Services? _services;
  bool _starting = false;
  Object? _error;

  /// [SegueApp.themeChoice], or one of its own, which follows the system's until a pick.
  late final _themeChoice = widget.themeChoice ?? ThemeChoice();

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
      final services = await Services.start(session);

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

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _themeChoice, builder: _app);

  /// The app, in the theme picked.
  Widget _app(BuildContext context, Widget? _) {
    final services = _services;
    return MaterialApp(
      title: 'Segue',
      debugShowCheckedModeBanner: false,
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

        return ThemeFade(
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
      },
      home: services != null
          ? HomePage(onSignOut: _signOut, themeChoice: _themeChoice)
          : _starting
          ? const Scaffold(body: Center(child: Spinner()))
          : _error != null
          ? Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Erro ao abrir: $_error'),
                    TextButton(onPressed: _signOut, child: const Text('Sair')),
                  ],
                ),
              ),
            )
          : LoginPage(onSignedIn: _start),
    );
  }
}
