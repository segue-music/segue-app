import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/cover.dart';
import '../widgets/themed_icon.dart';

final _log = Logger('PictureGallery');

/// Pictures side by side, one at a time in the middle, square, as wide as the text under it, with a little of the next
/// showing beside it, and of the one before: the media server's, by its cover id, then more from elsewhere, by their
/// URLs, as they come. A swipe goes from one to the next, as a tap on the one beside does, and with
/// a mouse the arrows that come over them as the pointer is over the gallery; the keyboard's and the remote's arrows,
/// from the page it's on, through [PictureGalleryState.turn].
class PictureGallery extends StatefulWidget {
  const PictureGallery(this.picture, {required this.icon, this.more, super.key});

  /// The media server's picture, by its cover id, the first; none: the first of [more], or a placeholder.
  final String? picture;

  /// What the placeholder shows.
  final HugeIconData icon;

  /// More pictures, after [picture], by their URLs, as they come; none: [picture] alone.
  final Future<List<Uri>>? more;

  @override
  State<PictureGallery> createState() => PictureGalleryState();
}

class PictureGalleryState extends State<PictureGallery> {
  /// On either side of a picture, lined up with the text under it ([ReadingPage]'s), in which the ones beside it show.
  static const _margin = 16.0;

  /// Between two pictures, less than [_margin], for a little of the ones beside the middle one to show.
  static const _gap = 8.0;

  /// How much of the pictures beside the middle one shows at most, where the gallery could be wider: on a wider screen
  /// than a phone's, whose height may keep the picture narrower than the text.
  static const _peek = 44.0;

  /// The pictures after the media server's, once they have come.
  List<Uri> _more = const [];

  /// The one in the middle, from 0.
  int _page = 0;

  /// Its pages, as wide as a picture and a gap in the gallery: made anew where that changes, as the window does.
  PageController? _pages;

  /// Whether a mouse's pointer is over the gallery, which brings the arrows.
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(PictureGallery oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.more != oldWidget.more) {
      _follow();
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  /// Takes the pictures of [PictureGallery.more] as they come, while they are still the gallery's.
  void _follow() {
    final more = widget.more;
    _more = const [];
    more?.then((found) {
      if (mounted && widget.more == more) {
        setState(() => _more = found);
      }
    }, onError: (Object e) => _log.warning('more pictures not had', e));
  }

  /// How many pictures it has.
  int get _count => max(1, (widget.picture == null ? 0 : 1) + _more.length);

  /// Goes [by] pictures on, forward or (negative) back, as far as there are; whether there was one that way.
  bool turn(int by) {
    final pages = _pages;
    final to = (_page + by).clamp(0, _count - 1);

    if (pages == null || !pages.hasClients || to == _page) {
      return false;
    }

    pages.animateToPage(to, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

    return true;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final screen = MediaQuery.sizeOf(context);
      final room = constraints.maxWidth;
      // No taller than most of the screen, so that the text starts above its bottom.
      final side = max(0.0, min(room - 2 * _margin, screen.height * 0.6));
      final width = min(room, side + 2 * (_gap + _peek));
      final fraction = (side + _gap) / width;

      if (_pages?.viewportFraction != fraction) {
        final old = _pages;
        _pages = PageController(viewportFraction: fraction, initialPage: _page);
        WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      }

      final pixels = (side * MediaQuery.devicePixelRatioOf(context)).ceil();

      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          width: width,
          height: side,
          child: Stack(
            children: [
              ScrollConfiguration(
                // Dragged with a mouse too, as a row of albums is.
                behavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false, dragDevices: PointerDeviceKind.values.toSet()),
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _count,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                    child: _picture(i, pixels: pixels),
                  ),
                ),
              ),
              _arrow(back: true),
              _arrow(back: false),
            ],
          ),
        ),
      );
    },
  );

  /// The picture at [i], asked for at [pixels] across, rounded as an album's cover on its page is. One beside the
  /// middle one goes to the middle at a tap.
  Widget _picture(int i, {required int pixels}) {
    final picture = widget.picture;
    final more = picture == null ? i : i - 1;
    final image = more < 0 || more >= _more.length
        ? LargeCover(picture, size: pixels, icon: widget.icon)
        : Image.network(
            _more[more].toString(),
            fit: BoxFit.cover,
            cacheWidth: pixels,
            // Fading in once it has loaded, over the black.
            frameBuilder: (context, child, frame, synchronously) => synchronously
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  ),
            errorBuilder: (_, _, _) => Cover(null, icon: widget.icon),
          );
    // The same tree in the middle or beside it, so that the picture stays as it comes and goes.
    final beside = i != _page;

    return MouseRegion(
      cursor: beside ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: beside ? () => turn(i - _page) : null,
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: image),
      ),
    );
  }

  /// The arrow that goes [back], or forward, over the picture beside the middle one on that side: while a mouse's
  /// pointer is over the gallery and there is one that way. Out of the focus's way: the keyboard and the remote have
  /// their own arrows.
  Widget _arrow({required bool back}) {
    final strings = AppLocalizations.of(context);
    final shown = _hovered && (back ? _page > 0 : _page < _count - 1);

    return PositionedDirectional(
      start: back ? 4 : null,
      end: back ? null : 4,
      top: 0,
      bottom: 0,
      child: Center(
        child: IgnorePointer(
          ignoring: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: ExcludeFocus(
              child: IconButton(
                tooltip: back ? strings.previousPicture : strings.nextPicture,
                icon: ThemedIcon(back ? HugeIcons.strokeRoundedArrowLeft01 : HugeIcons.strokeRoundedArrowRight01),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => turn(back ? -1 : 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
