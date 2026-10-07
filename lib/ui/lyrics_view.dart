import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hugeicons/hugeicons.dart';

import '../connect/connect.dart';
import '../server/models.dart';
import '../services.dart';
import 'player_controls.dart';
import 'spinner.dart';
import 'themed_icon.dart';

/// The lyrics of what plays, wherever it plays. Synced ones mark the line that plays and keep it in view,
/// and a line tapped goes there (unless a tap does something else, [onTap]); others show as they are.
class LyricsView extends StatefulWidget {
  const LyricsView(this.now, {this.onTap, super.key});

  final NowPlaying now;

  /// What a tap anywhere on the lyrics does, in place of a line's going there: under the full-screen player on a
  /// phone, where they are short, opening them full screen.
  final VoidCallback? onTap;

  /// How tall the fades at the lyrics' top and bottom are.
  static const edgeFade = 40.0;

  /// What a part with no singing shows, in synced lyrics: a blank line, or an intro.
  static const instrumentalIcon = HugeIcons.strokeRoundedMusicNote03;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  /// The song whose lyrics [_lyrics] brings: by its id, and by its title, artist and album, as LRCLIB
  /// knows it (also with no id, from a hub that couldn't translate it).
  Object? _song;
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
    final now = widget.now;
    final song = (now.songId, now.title, now.artist, now.album);

    if (_lyrics != null && song == _song) {
      return;
    }

    _song = song;
    _shown = null;
    _lyrics = _find(now).then(_withIntro);
  }

  /// The song's lyrics from the media server; when it has none, or fails, from LRCLIB. The server's
  /// failure shows only if LRCLIB has none either.
  Future<Lyrics?> _find(NowPlaying now) async {
    final services = ServicesScope.of(context);
    final (songId, title, artist) = (now.songId, now.title, now.artist);
    (Object, StackTrace)? failure;
    Lyrics? lyrics;

    try {
      lyrics = songId == null ? null : await services.api.lyrics(songId);
    } on Object catch (error, stack) {
      failure = (error, stack);
    }

    final lrclib = services.lrclib;

    if (lyrics == null && lrclib != null && title != null && artist != null) {
      lyrics = await lrclib.find(title: title, artist: artist, album: now.album, duration: now.duration);
    }

    if ((lyrics, failure) case (null, (final error, final stack)?)) {
      Error.throwWithStackTrace(error, stack);
    }

    return lyrics;
  }

  /// From how late a first line leaves an intro to show, as a part with no singing.
  static const _introFrom = Duration(seconds: 2);

  /// [lyrics], with a blank line for their intro when they are synced and their first line comes late
  /// enough.
  static Lyrics? _withIntro(Lyrics? lyrics) {
    final first = lyrics?.lines.firstOrNull?.start;

    if (lyrics == null || !lyrics.synced || first == null || first < _introFrom) {
      return lyrics;
    }

    return Lyrics([const LyricLine('', start: Duration.zero), ...lyrics.lines], provider: lyrics.provider);
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
    final lyrics = FutureBuilder(
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
    final onTap = widget.onTap;

    if (onTap == null) {
      return lyrics;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: lyrics),
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
        // Fading out at the top and the bottom, rather than cut off there. The scrollbar stays whole.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final edge = bounds.height > 0 ? min(LyricsView.edgeFade / bounds.height, 0.5) : 0.0;
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
              stops: [0, edge, 1 - edge, 1],
            ).createShader(bounds);
          },
          child: ScrollConfiguration(
            // The scrollbar above in place of the one the platform adds, which shows for any scroll.
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _scroll,
              // Room under the fades, for the first and the last lines to show whole.
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: LyricsView.edgeFade),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, line) in lyrics.lines.indexed)
                    InkWell(
                      key: _keys[i],
                      // With a tap of their own, the lyrics' hand, over the lines too.
                      mouseCursor: widget.onTap == null ? WidgetStateMouseCursor.clickable : MouseCursor.defer,
                      borderRadius: BorderRadius.circular(8),
                      onTap: switch (line.start) {
                        final start? when widget.onTap == null => () => runCommand(
                          context,
                          () => ServicesScope.of(context).connect.seek(start),
                        ),
                        _ => null,
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        // A blank line of synced lyrics is a part with no singing; of others, a gap between
                        // verses.
                        child: lyrics.synced && line.text.trim().isEmpty
                            ? ThemedIcon(
                                LyricsView.instrumentalIcon,
                                size: style?.fontSize,
                                color: i == playing ? ink : faded,
                              )
                            : Text(
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
