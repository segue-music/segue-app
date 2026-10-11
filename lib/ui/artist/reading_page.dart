import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../widgets/arrow_scroll.dart';
import '../widgets/cover.dart';
import '../widgets/text_link.dart';
import '../widgets/themed_icon.dart';
import 'picture_gallery.dart';

/// A page to read about an artist or an album, on black as a cover full screen is ([CoverPage]): a picture at the top,
/// square, as wide as the screen but no taller than most of it, or a gallery of pictures ([ReadingPage.gallery]), and
/// [children] under it, a column of reading width on a wide screen. Esc, its close button or a tap beside the picture
/// and the text closes it.
class ReadingPage extends StatefulWidget {
  const ReadingPage({required this.picture, required this.icon, required this.children, super.key})
    : morePictures = null,
      _hasGallery = false;

  /// A page whose pictures are a gallery ([PictureGallery]): [picture], then [morePictures], as they come, which the
  /// arrows left and right go through too, while it shows.
  const ReadingPage.gallery({
    required this.picture,
    required this.icon,
    required this.children,
    this.morePictures,
    super.key,
  }) : _hasGallery = true;

  /// The picture, by its cover id on the server; none: a placeholder.
  final String? picture;

  /// What the placeholder shows.
  final HugeIconData icon;

  /// The gallery's pictures after [picture], by their URLs, as they come; none: [picture] alone.
  final Future<List<Uri>>? morePictures;

  final bool _hasGallery;

  final List<Widget> children;

  /// Fades [page] in over the current page: over the whole window, also from a page of the home's page area.
  static Future<void> open(BuildContext context, Widget page) => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> {
  final _scroll = ScrollController();
  final _gallery = GlobalKey<PictureGalleryState>();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The arrows left and right go from one of the gallery's pictures to the next, while some of it shows (at the top of
  /// the page); otherwise, and at its ends, they go on, to move the focus.
  KeyEventResult _turnByArrow(FocusNode _, KeyEvent event) {
    final by = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    final gallery = _gallery.currentState;

    if (by == 0 || event is KeyUpEvent || gallery == null || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }

    final shows = _scroll.offset < (_gallery.currentContext?.size?.height ?? 0);

    return shows && gallery.turn(by) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final strings = AppLocalizations.of(context);
    // Most of the screen's height at most, so that the text starts above its bottom.
    final side = min(screen.width, screen.height * 0.6);
    final picture = widget._hasGallery
        ? PictureGallery(widget.picture, icon: widget.icon, more: widget.morePictures, key: _gallery)
        : SizedBox.square(
            dimension: side,
            // Asked of the server at that size.
            child: LargeCover(
              widget.picture,
              size: (side * MediaQuery.devicePixelRatioOf(context)).ceil(),
              icon: widget.icon,
            ),
          );

    void close() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      // Wherever the focus is in the page, which it never takes itself.
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: widget._hasGallery ? _turnByArrow : null,
        // The system's icons light, over the black above the picture.
        child: AnnotatedRegion(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: Colors.black,
            // A tap beside the picture and the text closes it (on a wide screen, the black on either side), as a tap
            // anywhere closes a cover's.
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    // Up and down scroll it, also while a link has the focus (from Tab: the arrows only scroll).
                    ArrowScroll(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(child: _keepingTaps(picture)),
                                _keepingTaps(
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: widget.children,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // On a dark round, to stand out from the picture, and from the text going up under it.
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton(
                        tooltip: strings.close,
                        icon: const ThemedIcon(HugeIcons.strokeRoundedCancel01),
                        color: Colors.white,
                        style: IconButton.styleFrom(backgroundColor: Colors.black54),
                        onPressed: close,
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

  /// [child], whose taps stay in it: only those beside it close the page.
  static Widget _keepingTaps(Widget child) =>
      GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: child);
}

/// One of a [NameTable]'s lines: a name, a link to the page of [artist] where it's one of the library's artists, and
/// what is said of them ([detail]).
typedef NameLine = ({String name, Artist? artist, String detail});

/// Names, one a line, under titles, each with what is said of them beside it, lighter, on a [ReadingPage]'s black.
/// What is said lines up after the longest name, or [nameWidth] of the column (a fraction of it), where a longer one
/// wraps. The names of the library's artists are links to their pages ([onOpenArtist]), which close the page.
class NameTable extends StatelessWidget {
  const NameTable(this.groups, {this.nameWidth = 0.6, this.onOpenArtist, super.key});

  /// Each title, with the lines under it; a title without lines doesn't show.
  final List<(String, List<NameLine>)> groups;

  final double nameWidth;

  /// Opens an artist's page, from the link of their name, as the page closes.
  final void Function(Artist artist)? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final name = text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.87));
    final detail = text.bodyLarge?.copyWith(color: Colors.white54);

    return Table(
      columnWidths: {0: MinColumnWidth(const IntrinsicColumnWidth(), FractionColumnWidth(nameWidth))},
      defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (final (title, lines) in groups)
          if (lines.isNotEmpty) ...[
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 4),
                  child: Text(title, style: text.titleMedium?.copyWith(color: Colors.white)),
                ),
                const SizedBox.shrink(),
              ],
            ),
            for (final line in lines)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 4, end: 16),
                    child: switch (line.artist) {
                      final artist? => TextLink(
                        line.name,
                        tooltip: strings.openArtist,
                        onTap: () {
                          Navigator.of(context).pop();
                          onOpenArtist?.call(artist);
                        },
                        style: name,
                        maxLines: 2,
                      ),
                      null => Text(line.name, style: name),
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(line.detail, style: detail),
                  ),
                ],
              ),
          ],
      ],
    );
  }
}
