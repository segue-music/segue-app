import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../connect/connect.dart';
import '../server/models.dart';
import '../services.dart';
import 'player_controls.dart';
import 'spinner.dart';

/// The lyrics of what plays, wherever it plays. Synced ones mark the line that plays and keep it in view,
/// and a line tapped goes there; others show as they are.
class LyricsView extends StatefulWidget {
  const LyricsView(this.now, {super.key});

  final NowPlaying now;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  /// The song whose lyrics [_lyrics] brings.
  String? _songId;
  Future<Lyrics?>? _lyrics;

  final _scroll = ScrollController();
  List<GlobalKey> _keys = const [];

  /// The line last brought into view.
  int? _shown;

  /// The lyrics scroll by themselves, to the line that plays: the scrollbar shows only when the user
  /// scrolls them.
  bool _following = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetch();
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fetch();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Asks for the lyrics of the song that plays, when it is another. A song the hub couldn't give in
  /// this device's API has none to ask for.
  void _fetch() {
    final songId = widget.now.songId;

    if (_lyrics != null && songId == _songId) {
      return;
    }

    _songId = songId;
    _shown = null;
    _lyrics = songId == null ? Future.value() : ServicesScope.of(context).api.lyrics(songId);
  }

  /// The line that plays at [position]: the last to have started; none before the first.
  static int? _playing(Lyrics lyrics, Duration position) {
    int? playing;

    for (final (i, line) in lyrics.lines.indexed) {
      if (line.start! > position) {
        break;
      }

      playing = i;
    }

    return playing;
  }

  /// Scrolls the lyrics, and only them, to have line [i] a third of the way down.
  Future<void> _reveal(int i, {required bool animate}) async {
    final line = _keys[i].currentContext?.findRenderObject();

    if (line == null || !_scroll.hasClients) {
      return;
    }

    final position = _scroll.position;
    final offset = RenderAbstractViewport.of(line)
        .getOffsetToReveal(line, 0.35)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    _following = true;

    if (animate) {
      // Until it ends, or the user takes over.
      await _scroll.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(offset);
    }

    _following = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return FutureBuilder(
      future: _lyrics,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message('Não consegui buscar a letra: ${snapshot.error}', style: style);
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: Spinner());
        }

        final lyrics = snapshot.data;
        return lyrics == null ? _Message('Esta música não tem letra.', style: style) : _lines(lyrics);
      },
    );
  }

  Widget _lines(Lyrics lyrics) {
    final text = Theme.of(context).textTheme;
    final synced = lyrics.synced;
    final playing = synced ? _playing(lyrics, widget.now.position) : null;

    if (_keys.length != lyrics.lines.length) {
      _keys = [for (final _ in lyrics.lines) GlobalKey()];
    }

    if (playing != null && playing != _shown) {
      // At once the first time, as the lyrics open on a song already playing.
      final animate = _shown != null;
      _shown = playing;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_reveal(playing, animate: animate)));
    }

    // Big, and a bit smaller in a phone's width, where they would break into too many lines.
    return LayoutBuilder(
      builder: (context, box) =>
          _lineList(lyrics, playing, style: box.maxWidth >= _bigFrom ? text.headlineMedium : text.headlineSmall),
    );
  }

  /// From how wide the lyrics take their biggest size.
  static const _bigFrom = 480.0;

  Widget _lineList(Lyrics lyrics, int? playing, {required TextStyle? style}) {
    final ink = Theme.of(context).colorScheme.onSurface;
    // Faded, but for the line that plays; whole when none does, as in lyrics that aren't synced.
    final faded = lyrics.synced ? ink.withValues(alpha: 0.4) : ink;
    // Out of the focus's way: for the remote, the player's controls are what matters.
    return ExcludeFocus(
      child: Scrollbar(
        controller: _scroll,
        notificationPredicate: (notification) => !_following && defaultScrollNotificationPredicate(notification),
        child: ScrollConfiguration(
          // The scrollbar above in place of the one the platform adds, which shows for any scroll.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in lyrics.lines.indexed)
                  InkWell(
                    key: _keys[i],
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    borderRadius: BorderRadius.circular(8),
                    onTap: switch (line.start) {
                      final start? => () => runCommand(context, () => ServicesScope.of(context).connect.seek(start)),
                      null => null,
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text(
                        line.text,
                        textAlign: TextAlign.center,
                        style: i == playing
                            ? style?.copyWith(fontWeight: FontWeight.bold, color: ink)
                            : style?.copyWith(color: faded),
                      ),
                    ),
                  ),
                if (lyrics.provider case final provider?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                    child: Text(
                      'Letras providas por $provider',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: faded),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Why there are no lyrics to show.
class _Message extends StatelessWidget {
  const _Message(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: style),
    ),
  );
}
