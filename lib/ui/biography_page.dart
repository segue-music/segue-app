import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../releases/musicbrainz.dart';
import '../server/models.dart';
import 'arrow_scroll.dart';
import 'cover.dart';
import 'themed_icon.dart';

/// An artist's biography, on black as a cover full screen is ([CoverPage]): their picture at the top, square, as wide
/// as the screen but no taller than most of it, and their name, with a band's years beside it, and the biography under
/// it, a column of reading width on a wide screen. Esc, its close button or a tap beside the picture and the text
/// closes it.
class BiographyPage extends StatefulWidget {
  const BiographyPage(this.biography, {required this.name, this.picture, this.years, super.key});

  final Biography biography;

  /// The artist's.
  final String name;

  /// The artist's picture, by its id on the server; none: a placeholder.
  final String? picture;

  /// The years the artist has been together, where they are a band ([MusicBrainz.bandYears]); none: none shown.
  final Future<BandYears?>? years;

  /// Fades it in over the current page: over the whole window, also from a page of the home's page area.
  static Future<void> open(
    BuildContext context,
    Biography biography, {
    required String name,
    String? picture,
    Future<BandYears?>? years,
  }) => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => BiographyPage(biography, name: name, picture: picture, years: years),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<BiographyPage> createState() => _BiographyPageState();
}

class _BiographyPageState extends State<BiographyPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    // Most of the screen's height at most, so that the name and the biography start above its bottom.
    final side = min(screen.width, screen.height * 0.6);
    final source = widget.biography.source;

    void close() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
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
                  // Nothing in it takes the focus: up and down scroll it.
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
                              Center(
                                child: _keepingTaps(
                                  SizedBox.square(
                                    dimension: side,
                                    // Asked of the server at that size.
                                    child: LargeCover(
                                      widget.picture,
                                      size: (side * MediaQuery.devicePixelRatioOf(context)).ceil(),
                                      icon: HugeIcons.strokeRoundedUser,
                                    ),
                                  ),
                                ),
                              ),
                              _keepingTaps(
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // A band's years after the name, as they come, under it where they don't fit.
                                      FutureBuilder(
                                        future: widget.years,
                                        builder: (context, snapshot) => Text.rich(
                                          TextSpan(
                                            text: widget.name,
                                            children: [
                                              if (snapshot.data case final years?) ...[
                                                const TextSpan(text: ' '),
                                                TextSpan(
                                                  text: _yearsText(strings, years),
                                                  style: text.bodyLarge?.copyWith(color: Colors.white54),
                                                ),
                                              ],
                                            ],
                                          ),
                                          style: text.headlineSmall?.copyWith(color: Colors.white),
                                        ),
                                      ),
                                      for (final paragraph in widget.biography.paragraphs)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Text(
                                            paragraph,
                                            style: text.bodyLarge?.copyWith(
                                              color: Colors.white.withValues(alpha: 0.87),
                                            ),
                                          ),
                                        ),
                                      if (source != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 24),
                                          child: Text(
                                            strings.biographyProvidedBy(source),
                                            style: text.bodyMedium?.copyWith(color: Colors.white54),
                                          ),
                                        ),
                                    ],
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
    );
  }

  /// [years] as they show beside the name, on one line: "(desde 1991)", "(1966 – 1978)", "(até 1978)", "(1966 – ?)".
  static String _yearsText(AppLocalizations strings, BandYears years) => strings
      .bandYears(
        switch (years) {
          (begin: _, end: _, ended: false) => 'since',
          (begin: null, end: _, ended: true) => 'until',
          (begin: _, end: null, ended: true) => 'endUnknown',
          _ => 'other',
        },
        years.begin ?? 0,
        years.end ?? 0,
      )
      .replaceAll(' ', '\u00a0');

  /// [child], whose taps stay in it: only those beside it close the page.
  static Widget _keepingTaps(Widget child) =>
      GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: child);
}
