import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';
import 'arrow_scroll.dart';
import 'cover.dart';
import 'themed_icon.dart';

/// An artist's biography, on black as a cover full screen is ([CoverPage]): their picture at the top, square, as wide
/// as the screen but no taller than most of it, and their name and the biography under it, a column of reading width
/// on a wide screen. Esc or its close button closes it.
class BiographyPage extends StatefulWidget {
  const BiographyPage(this.biography, {required this.name, this.picture, super.key});

  final Biography biography;

  /// The artist's.
  final String name;

  /// The artist's picture, by its id on the server; none: a placeholder.
  final String? picture;

  /// Fades it in over the current page: over the whole window, also from a page of the home's page area.
  static Future<void> open(BuildContext context, Biography biography, {required String name, String? picture}) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => BiographyPage(biography, name: name, picture: picture),
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
          body: SafeArea(
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: SizedBox.square(
                                dimension: side,
                                // Asked of the server at that size.
                                child: LargeCover(
                                  widget.picture,
                                  size: (side * MediaQuery.devicePixelRatioOf(context)).ceil(),
                                  icon: HugeIcons.strokeRoundedUser,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                              child: Text(widget.name, style: text.headlineSmall?.copyWith(color: Colors.white)),
                            ),
                            for (final paragraph in widget.biography.paragraphs)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: Text(
                                  paragraph,
                                  style: text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.87)),
                                ),
                              ),
                            if (source != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                                child: Text(
                                  strings.biographyProvidedBy(source),
                                  style: text.bodyMedium?.copyWith(color: Colors.white54),
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
    );
  }
}
