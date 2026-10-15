import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../connect/connect.dart';
import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../widgets/directional_navigation.dart';
import '../widgets/spinner.dart';
import '../widgets/themed_icon.dart';
import 'player_controls.dart';

/// The lyrics of [now]'s song: the media server's, or, where it has none, or fails, LRCLIB's, with a blank line for an
/// intro (a part with no singing). A failure shows only if neither has them: the server's, or else LRCLIB's
/// ([_LrclibFailed]). Asked for once for each of the last few songs, whoever asks (the lyrics, and on a TV the player,
/// to know whether to show them), and again after a failure.
Future<Lyrics?> lyricsOf(BuildContext context, NowPlaying now) {
  final services = ServicesScope.of(context);
  final found = _found[services.api] ??= {};
  final song = lyricsSongOf(now);
  // The latest last, as the oldest go first.
  final known = found.remove(song) ?? _Found(_find(services, now).then(_withIntro));
  found[song] = known;

  if (found.length > _songsRemembered) {
    found.remove(found.keys.first);
  }

  unawaited(
    known.lyrics.then(
      (lyrics) => known.any = lyrics != null,
      onError: (Object _) {
        if (identical(found[song], known)) {
          found.remove(song);
        }
      },
    ),
  );

  return known.lyrics;
}

/// Whether [now]'s song has lyrics, where [lyricsOf] has found out; null where it hasn't yet, or failed.
bool? hasLyrics(BuildContext context, NowPlaying now) => _found[ServicesScope.of(context).api]?[lyricsSongOf(now)]?.any;

/// What [lyricsOf] has found, by song, for each media server: tests' servers each their own.
final _found = Expando<Map<Object, _Found>>();

/// For how many songs [lyricsOf] keeps what it found.
const _songsRemembered = 10;

/// A song as [lyricsOf] knows it, and remembers its lyrics by: by its id, and by its title, artist and album, as LRCLIB
/// knows it (also with no id, from a hub that couldn't translate it).
Object lyricsSongOf(NowPlaying now) => (now.songId, now.title, now.artist, now.album);

/// What [lyricsOf] found for a song, and, once it knows, whether there are any.
class _Found {
  _Found(this.lyrics);

  final Future<Lyrics?> lyrics;
  bool? any;
}

Future<Lyrics?> _find(Services services, NowPlaying now) async {
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
    try {
      lyrics = await lrclib.find(title: title, artist: artist, album: now.album, duration: now.duration);
    } on Object catch (_, stack) {
      failure ??= (const _LrclibFailed(), stack);
    }
  }

  if ((lyrics, failure) case (null, (final error, final stack)?)) {
    Error.throwWithStackTrace(error, stack);
  }

  return lyrics;
}

/// From how late a first line leaves an intro to show, as a part with no singing.
const _introFrom = Duration(seconds: 2);

/// [lyrics], with a blank line for their intro when they are synced and their first line comes late enough.
Lyrics? _withIntro(Lyrics? lyrics) {
  final first = lyrics?.lines.firstOrNull?.start;

  if (lyrics == null || !lyrics.synced || first == null || first < _introFrom) {
    return lyrics;
  }

  return Lyrics([const LyricLine('', start: Duration.zero), ...lyrics.lines], provider: lyrics.provider);
}

/// The lyrics of what plays, wherever it plays. Synced ones mark the line that plays and keep it in view,
/// and a line tapped goes there (unless a tap does something else, [onTap]); others show as they are. On a TV, as
/// karaoke ([karaoke]).
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

  /// Whether they show as karaoke, sung along to from across the room: on a TV. There the line that plays is bigger
  /// than the rest, growing as it comes, and in the middle; the lines to come are fainter, and those gone by fainter
  /// still. The full-screen player opens with them, and gives them more of the screen.
  static bool karaoke(BuildContext context) => context.television;

  /// How long the line that plays, as karaoke, takes to grow, and the one before to shrink.
  static const _grow = Duration(milliseconds: 300);

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  /// The song whose lyrics [_lyrics] brings ([lyricsSongOf]).
  Object? _song;
  Future<Lyrics?>? _lyrics;

  final _scroll = ScrollController();
  List<GlobalKey> _keys = const [];

  /// The line last brought into view.
  int? _shown;

  /// The lyrics scroll by themselves, to the line that plays: the scrollbar shows only when the user
  /// scrolls them.
  bool _following = false;

  /// As karaoke, the style each line goes to, growing or shrinking, as the last build gave it ([_growth]).
  TextStyle? Function(int line)? _endStyleOf;

  /// As karaoke, the lines' texts broken as they break playing ([_brokenAsPlaying]), and the width, the style and the
  /// text's scale they were broken for.
  final _broken = <String, String>{};
  Object? _brokenFor;

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
    final song = lyricsSongOf(now);

    if (_lyrics != null && song == _song) {
      return;
    }

    _song = song;
    _shown = null;
    _lyrics = lyricsOf(context, now);
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

  /// Scrolls the lyrics, and only them, to have line [i] a third of the way down; as karaoke, in the middle.
  Future<void> _reveal(int i, {required bool animate}) async {
    final karaoke = LyricsView.karaoke(context);
    final offset = _offsetToReveal(i, karaoke: karaoke);

    if (offset == null) {
      return;
    }

    _following = true;

    if (animate) {
      // Until it ends, or the user takes over. As karaoke, along with the line's growing.
      await _scroll.animateTo(offset, duration: LyricsView._grow, curve: Curves.easeOut);

      // Should the lines have ended up elsewhere all the same, the rest of the way.
      if (_offsetToReveal(i, karaoke: karaoke) case final settled?
          when karaoke && (settled - _scroll.offset).abs() > 1) {
        await _scroll.animateTo(settled, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    } else {
      _scroll.jumpTo(offset);
    }

    _following = false;
  }

  /// Where the lyrics scroll to for line [i] to be a third of the way down, or as [karaoke], in the middle; null before
  /// they are laid out. As karaoke, where it is once the lines growing and shrinking have ([_growth]): the line that
  /// plays, and the one before. Scrolled to where it was as they started, the lyrics went past it, the line before
  /// shrinking under it, and came back.
  double? _offsetToReveal(int i, {required bool karaoke}) {
    final line = _keys[i].currentContext?.findRenderObject();

    if (line == null || !_scroll.hasClients || !mounted) {
      return null;
    }

    final position = _scroll.position;
    var offset = RenderAbstractViewport.of(line).getOffsetToReveal(line, karaoke ? 0.5 : 0.35).offset;
    var end = position.maxScrollExtent;

    if (karaoke) {
      for (final (j, key) in _keys.indexed) {
        final growth = _growth(key, _endStyleOf?.call(j));
        // Those above it move it as much; its own growing, half as much, from its middle.
        offset += j < i ? growth : (j == i ? growth / 2 : 0);
        end += growth;
      }
    }

    return offset.clamp(position.minScrollExtent, end);
  }

  /// How much taller the line [key] holds gets as its text goes to [style]: its text laid out as the [Text] will lay
  /// it out then. None where its size is there already, or it has no text (a part with no singing, whose icon changes
  /// size at once).
  static double _growth(GlobalKey key, TextStyle? style) {
    final context = key.currentContext;
    final paragraph = _paragraphIn(context?.findRenderObject());

    if (context == null || paragraph == null || style == null) {
      return 0;
    }

    final now = paragraph.text.style;
    final end = DefaultTextStyle.of(context).style.merge(style);

    if (now?.fontSize == end.fontSize && now?.fontWeight == end.fontWeight && now?.height == end.height) {
      return 0;
    }

    final painter = TextPainter(
      text: TextSpan(text: paragraph.text.toPlainText(), style: end),
      textAlign: paragraph.textAlign,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textWidthBasis: paragraph.textWidthBasis,
      textHeightBehavior: paragraph.textHeightBehavior,
    )..layout(minWidth: paragraph.constraints.minWidth, maxWidth: paragraph.constraints.maxWidth);
    final growth = paragraph.constraints.constrainHeight(painter.height) - paragraph.size.height;

    painter.dispose();

    return growth;
  }

  /// The text in [object], the first found.
  static RenderParagraph? _paragraphIn(RenderObject? object) {
    if (object == null || object is RenderParagraph) {
      return object as RenderParagraph?;
    }

    RenderParagraph? found;

    object.visitChildren((child) => found ??= _paragraphIn(child));

    return found;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final strings = AppLocalizations.of(context);
    final lyrics = FutureBuilder(
      future: _lyrics,
      builder: (context, snapshot) {
        // First: while the next song's come, the snapshot keeps the song before's error.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: Spinner());
        }

        if (snapshot.error case final error?) {
          return _Message(
            error is _LrclibFailed ? strings.couldNotFetchLyrics : strings.couldNotFetchLyricsError('$error'),
            style: style,
          );
        }

        final lyrics = snapshot.data;

        return lyrics == null ? _Message(strings.noLyrics, style: style) : _lines(lyrics);
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

    // Big, and a bit smaller in a phone's width, where they would break into too many lines. As karaoke, the line that
    // plays bigger still, and the others a bit smaller, for it to stand out.
    if (LyricsView.karaoke(context)) {
      return _lineList(lyrics, playing, style: text.headlineSmall, playingStyle: text.displaySmall);
    }

    return LayoutBuilder(
      builder: (context, box) =>
          _lineList(lyrics, playing, style: box.maxWidth >= _bigFrom ? text.headlineMedium : text.headlineSmall),
    );
  }

  /// From how wide the lyrics take their biggest size.
  static const _bigFrom = 480.0;

  /// The room at the sides of the lyrics, under the scrollbar, and of each line, within its ink. As karaoke, none: the
  /// remote neither scrolls them nor presses a line, and their sides line up with what is around them (on a TV, the
  /// full-screen player's controls).
  static const _side = 12.0;
  static const _lineSide = 8.0;

  /// As karaoke, [text] broken into the lines it takes as the line that plays, in [style], [width] wide, the way the
  /// [Text] would break it: shown so before it plays too, and as it grows and shrinks, no word goes to another line,
  /// as one would at some size on the way, nor does the line become two. Where it takes one line, as it is.
  String _brokenAsPlaying(String text, TextStyle style, double width) {
    final scale = MediaQuery.textScalerOf(context);

    if ((width, style, scale) != _brokenFor) {
      _broken.clear();
      _brokenFor = (width, style, scale);
    }

    return _broken[text] ??= _breakAsPlaying(text, style, width, scale);
  }

  String _breakAsPlaying(String text, TextStyle style, double width, TextScaler scale) {
    final defaults = DefaultTextStyle.of(context);
    final painter = TextPainter(
      text: TextSpan(text: text, style: defaults.style.merge(style)),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: scale,
      locale: Localizations.maybeLocaleOf(context),
      textWidthBasis: defaults.textWidthBasis,
      textHeightBehavior: defaults.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
    )..layout(maxWidth: width);
    // Each line's part of the text, by a point in its middle.
    final lines = [
      for (final line in painter.computeLineMetrics())
        painter.getLineBoundary(
          painter.getPositionForOffset(Offset(line.left + line.width / 2, line.baseline - line.ascent / 2)),
        ),
    ];

    painter.dispose();

    return lines.length < 2 ? text : [for (final line in lines) line.textInside(text).trim()].join('\n');
  }

  /// The lines in [style], the one that plays ([playing]) bold, in [playingStyle] where it has one of its own.
  Widget _lineList(Lyrics lyrics, int? playing, {required TextStyle? style, TextStyle? playingStyle}) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final karaoke = LyricsView.karaoke(context);
    // Faded, but for the line that plays; whole when none does, as in lyrics that aren't synced. As karaoke, those to
    // come less than those gone by.
    final faded = lyrics.synced ? ink.withValues(alpha: karaoke ? 0.5 : 0.4) : ink;
    final gone = lyrics.synced && karaoke ? ink.withValues(alpha: 0.25) : faded;
    final current = (playingStyle ?? style)?.copyWith(fontWeight: FontWeight.bold, color: ink);

    TextStyle? styleOf(int i) => switch (playing) {
      final playing? when i == playing => current,
      final playing? when i < playing => style?.copyWith(color: gone),
      _ => style?.copyWith(color: faded),
    };

    _endStyleOf = karaoke ? styleOf : null;

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
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                controller: _scroll,
                // Room under the fades, for the first and the last lines to show whole.
                padding: EdgeInsets.symmetric(horizontal: karaoke ? 0 : _side, vertical: LyricsView.edgeFade),
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
                          padding: EdgeInsets.symmetric(horizontal: karaoke ? 0 : _lineSide, vertical: 6),
                          // A blank line of synced lyrics is a part with no singing; of others, a gap between
                          // verses.
                          child: lyrics.synced && line.text.trim().isEmpty
                              ? ThemedIcon(
                                  LyricsView.instrumentalIcon,
                                  size: styleOf(i)?.fontSize,
                                  color: styleOf(i)?.color,
                                )
                              // As karaoke, growing as it comes to play, and shrinking as it goes, broken as it is playing.
                              : karaoke
                              ? TweenAnimationBuilder(
                                  tween: TextStyleTween(end: styleOf(i)),
                                  duration: LyricsView._grow,
                                  curve: Curves.easeOut,
                                  builder: (context, style, _) => Text(
                                    current == null ? line.text : _brokenAsPlaying(line.text, current, box.maxWidth),
                                    textAlign: TextAlign.center,
                                    style: style,
                                  ),
                                )
                              : Text(line.text, textAlign: TextAlign.center, style: styleOf(i)),
                        ),
                      ),
                    if (lyrics.provider case final provider?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                        child: Text(
                          AppLocalizations.of(context).lyricsProvidedBy(provider),
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

/// LRCLIB failed, with the media server having no lyrics either. What it said stays out of the message: an
/// HTTP status (a 503 when it is too busy) or a network error, of no use to the user.
class _LrclibFailed implements Exception {
  const _LrclibFailed();
}
