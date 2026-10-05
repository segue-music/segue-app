import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';

import 'cover.dart';
import 'focus_ring.dart';

/// A cover full screen, on black: as big as the screen's shorter side, and asked of the server at
/// that size. A tap anywhere, Esc or "Fechar" closes it.
class CoverPage extends StatelessWidget {
  const CoverPage(this.id, {super.key});

  final String id;

  /// Fades it in over the current page, the cover growing out of its [CoverButton].
  static Future<void> open(BuildContext context, String id) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => CoverPage(id),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide;
    final pixels = (side * MediaQuery.devicePixelRatioOf(context)).ceil();

    void close() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: Stack(
              children: [
                Center(
                  child: SizedBox.square(
                    dimension: side,
                    child: Hero(
                      tag: _heroTag(id),
                      // The smaller cover, which the page that opened this one has already loaded,
                      // shows until the big one arrives.
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Cover(id),
                          Cover(id, size: pixels),
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(
                      tooltip: 'Fechar',
                      icon: const Icon(HugeIcons.strokeRoundedCancel01),
                      color: Colors.white,
                      onPressed: close,
                    ),
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

/// A cover that opens full screen ([CoverPage]) when tapped, or pressed from the keyboard or the
/// remote. Without a cover it is only the placeholder, and opens nothing.
class CoverButton extends StatelessWidget {
  const CoverButton(this.id, {super.key});

  final String? id;

  static const _borderRadius = BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    final id = this.id;
    final cover = ClipRRect(borderRadius: _borderRadius, child: Cover(id));

    if (id == null) {
      return cover;
    }

    return Tooltip(
      message: 'Ver a capa',
      child: FocusRing(
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: _borderRadius,
          onTap: () => CoverPage.open(context, id),
          child: Hero(tag: _heroTag(id), child: cover),
        ),
      ),
    );
  }
}

/// What ties a [CoverButton] to the [CoverPage] it opens, for the cover to fly between them.
Object _heroTag(String id) => ('cover', id);
