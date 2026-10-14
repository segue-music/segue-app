// Makes the app's icons from tool/icon.png, the artwork: a pink rounded square, with a ring around the note, on a
// near-black background. The square's pink edge says nothing, so no icon has it: where the system gives the icon no
// shape of its own, it is the ring and what is in it, round, in the room the square took. Run it after changing the
// artwork: DART=1 tool/flutter.sh run tool/icons.dart
//
// - Android: the launcher icon, adaptive (Android 8 and later, mipmap-anydpi-v26/ic_launcher.xml) and as a plain image
//   before that, the Android TV banner, and the media notification's icon.
// - Linux: the window's icon, also the one of the menu entry that install-desktop-entry.sh adds.
// - iOS: one 1024 px icon, from which Xcode makes the smaller ones.
// - macOS: the icon at each size its asset catalog lists.
// - Windows: one .ico, with the sizes Windows picks from.
// - The app itself: the icon in its top bar, which goes to the home, and the one over the sign-in form.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart';

/// The rounded square in the artwork, in its pixels, and how far the drawing in it reaches from the square's centre
/// (the outer edge of the ring around the note), as measured on it. A new artwork needs these measured again.
const _left = 68.8, _top = 76.8, _right = 590.9, _bottom = 582.7, _radius = 94.0, _reach = 220.0;

/// The ring around the note, as measured on the artwork: the centre of the box around it (a little lower than the
/// square's, and the ring not quite round: 430 × 419 px) and that box's width, and two distances from that centre, one
/// within the ring's band all the way round but for its two gaps (at the top and the bottom), and one past it.
const _ringX = 328.0, _ringY = 338.5, _ringWidth = 430.0, _ringBand = 200.0, _ringPast = 219.0;

const _res = 'android/app/src/main/res';

/// Android's densities, as pixels per dp.
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

void main() {
  final art = _Artwork(decodePng(File('tool/icon.png').readAsBytesSync())!);

  for (final MapEntry(key: density, value: scale) in _densities.entries) {
    // Before Android 8: the ring, at the size of the round icons in the 48 dp grid (44 dp).
    _write('$_res/mipmap-$density/ic_launcher.png', art.round((48 * scale).round(), 44 / 48));
    // Android 8 and later: the launcher cuts the icon to its own shape (a circle, a squircle...), so the foreground
    // layer, 108 dp of which 72 dp show, is the inside of the square without its edge, stretched to the layer's
    // borders. The ring fits in the 66 dp circle that every shape keeps.
    _write('$_res/mipmap-$density/ic_launcher_foreground.png', art.inside((108 * scale).round(), 66 / 108));
    // The media notification's icon (lib/player/media_controls.dart), also in the status bar: 24 dp, of which the ring
    // takes the 20 dp a round icon of Material's takes.
    _write('$_res/drawable-$density/ic_notification.png', art.silhouette((24 * scale).round(), 20 / 24));
  }

  // The Android TV banner, 320 × 180 dp: the ring, on the artwork's background.
  _write('$_res/drawable-xhdpi/banner.png', art.banner(640, 360, 0.8));
  // A round icon looks smaller than a square one as wide, so the ring takes a little more than the square took (0.84).
  _write('linux/runner/resources/app_icon.png', art.round(256, 0.88));
  // iOS cuts the icon to its own rounded square, so it is the artwork's square from edge to edge, the drawing as big in
  // it as in the artwork. Opaque: App Store Connect refuses an icon with an alpha channel.
  _write(
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    art.inside(1024, 2 * _reach / (_right - _left)).convert(numChannels: 3),
  );

  // macOS shows the icon as it is, but every app's in the same rounded square, Apple's: 824 px of 1024, its corners
  // 185.4 px, with the rest transparent. The inside of the artwork's square fills it, as on iOS.
  for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
    _write(
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
      art.tile(size, 824 / 1024, 185.4 / 824),
    );
  }

  // Windows: the ring from edge to edge, at the sizes Windows picks from for the taskbar, the title bar and Explorer, at
  // 100 to 200 % scaling. Not with Linux's margin: Windows's icons fill their square, and the disk's dark inside
  // disappears on a dark taskbar, so with the margin the ring showed smaller than the other apps' icons. Each one is a
  // PNG inside the .ico, which Windows reads since Vista.
  final windowsSizes = [16, 20, 24, 32, 40, 48, 64, 256];

  _writeBytes(
    'windows/runner/resources/app_icon.ico',
    IcoEncoder().encodeImages([for (final size in windowsSizes) art.round(size, 1)]),
  );

  // In the app's top bar: the ring from edge to edge, 32 logical pixels, at each density Flutter picks an asset's
  // variant for (assets/2.0x/logo.png for 2 physical pixels per logical one, and so on). Over the sign-in form, in place
  // of the app's name: the same, 96 logical pixels (logo_large.png).
  for (final density in [1, 2, 3, 4]) {
    final directory = density == 1 ? 'assets' : 'assets/$density.0x';

    _write('$directory/logo.png', art.round(32 * density, 1));
    _write('$directory/logo_large.png', art.round(96 * density, 1));
  }
}

void _write(String path, Image image) => _writeBytes(path, encodePng(image, level: 9));

void _writeBytes(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  stdout.writeln(path);
}

/// A colour with its alpha, straight (not premultiplied), each channel from 0 to 1.
typedef _Rgba = (double, double, double, double);

class _Artwork {
  _Artwork(Image image)
    : width = image.width,
      height = image.height,
      _rgb = image.convert(numChannels: 3).getBytes(order: ChannelOrder.rgb);

  final int width, height;
  final Uint8List _rgb;

  static const _cx = (_left + _right) / 2, _cy = (_top + _bottom) / 2;

  /// The ring and what is in it, with what is around it transparent, [fill] of a [size] × [size] image wide.
  Image round(int size, double fill) =>
      _render(size, size, _ringWidth / (size * fill), _ring, centre: (_ringX, _ringY));

  /// The inside of the rounded square, 16 px from its edge, carried on to the image's borders by repeating that edge
  /// outwards: opaque, with nothing of the square's shape left. [fill] is how much of the image the drawing takes.
  Image inside(int size, double fill) {
    const inset = 16.0;
    final scale = 2 * _reach / (size * fill);

    return _render(size, size, scale, (x, y) {
      final (px, py) = _nearestInside(x, y, inset);
      final (r, g, b) = _sample(px, py);

      return (r, g, b, 1);
    });
  }

  /// [inside]'s image in a rounded square of its own, [fill] of a [size] × [size] image wide, its corners [radius] of
  /// its side, with what is around it transparent. The drawing takes as much of it as of the artwork's square.
  Image tile(int size, double fill, double radius) {
    const inset = 16.0, side = _right - _left;
    final corner = radius * side;
    // The square of the corners' centres, as in [_nearestInside].
    final k = side / 2 - corner;

    return _render(size, size, side / (size * fill), (x, y) {
      final (px, py) = _nearestInside(x, y, inset);
      final (r, g, b) = _sample(px, py);
      final dx = max((x - _cx).abs() - k, 0.0), dy = max((y - _cy).abs() - k, 0.0);

      return (r, g, b, dx * dx + dy * dy <= corner * corner ? 1 : 0);
    });
  }

  /// The ring and the note alone, in white, opaque where they are pink and transparent where the square is dark, as
  /// Android wants a notification's icon, of which it takes only the alpha. [fill] is how much of the image the ring
  /// takes.
  Image silhouette(int size, double fill) {
    final scale = 2 * _reach / (size * fill);

    return _render(size, size, scale, (x, y) {
      final dx = x - _cx, dy = y - _cy;

      // Past the ring, before the square's edge, which is pink too.
      if (dx * dx + dy * dy > (_reach + 12) * (_reach + 12)) {
        return (1, 1, 1, 0);
      }

      final (red, _, _) = _sample(x, y);

      return (1, 1, 1, _pinkness(red));
    });
  }

  /// The ring and what is in it, [fill] of the image's height, on the colour of the artwork's borders.
  Image banner(int width, int height, double fill) {
    final (br, bg, bb) = _borderColour();

    return _render(width, height, _ringWidth / (height * fill), centre: (_ringX, _ringY), (x, y) {
      final (r, g, b, a) = _ring(x, y);

      return (r * a + br * (1 - a), g * a + bg * (1 - a), b * a + bb * (1 - a), 1);
    });
  }

  /// The colour at (x, y) of the ring and what is in it, transparent around it: within the ring's band, the artwork as
  /// it is; past it, the ring's pink alone, as opaque as it is pink, so that the cut follows the ring's edge, which
  /// isn't quite round. Where the ring has its gaps, the cut goes into them.
  _Rgba _ring(double x, double y) {
    final dx = x - _ringX, dy = y - _ringY;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance > _ringPast) {
      return (0, 0, 0, 0);
    }

    final (r, g, b) = _sample(x, y);

    return (r, g, b, distance <= _ringBand ? 1 : _pinkness(r));
  }

  /// A width × height image centred on [centre], or else on the rounded square, each pixel [scale] artwork pixels wide.
  /// [paint] gives the colour at a point of the artwork; each pixel averages it over a grid of points at least as fine
  /// as the artwork's.
  Image _render(
    int width,
    int height,
    double scale,
    _Rgba Function(double x, double y) paint, {
    (double, double) centre = (_cx, _cy),
  }) {
    final n = max(1, scale.ceil());
    final image = Image(width: width, height: height, numChannels: 4);
    final (cx, cy) = centre;
    final x0 = cx - width * scale / 2, y0 = cy - height * scale / 2;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0;

        for (var j = 0; j < n; j++) {
          for (var i = 0; i < n; i++) {
            final (pr, pg, pb, pa) = paint(x0 + (x + (i + 0.5) / n) * scale, y0 + (y + (j + 0.5) / n) * scale);
            r += pr * pa;
            g += pg * pa;
            b += pb * pa;
            a += pa;
          }
        }

        // Averaged premultiplied, so the transparent pixels around the shape don't darken its edge.
        if (a > 0) {
          image.setPixelRgba(x, y, 255 * r / a, 255 * g / a, 255 * b / a, 255 * a / (n * n));
        }
      }
    }

    return image;
  }

  /// The artwork's colour at (x, y), between its pixels' centres.
  (double, double, double) _sample(double x, double y) {
    final fx = (x - 0.5).clamp(0.0, width - 1.0), fy = (y - 0.5).clamp(0.0, height - 1.0);
    final x0 = fx.floor(), y0 = fy.floor();
    final x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1);
    final tx = fx - x0, ty = fy - y0;

    double channel(int c) {
      double at(int x, int y) => _rgb[(y * width + x) * 3 + c] / 255;

      final top = at(x0, y0) * (1 - tx) + at(x1, y0) * tx;
      final bottom = at(x0, y1) * (1 - tx) + at(x1, y1) * tx;

      return top * (1 - ty) + bottom * ty;
    }

    return (channel(0), channel(1), channel(2));
  }

  /// The mean colour of the artwork's outermost pixels.
  (double, double, double) _borderColour() {
    var r = 0.0, g = 0.0, b = 0.0, n = 0;

    void add(int x, int y) {
      final i = (y * width + x) * 3;
      r += _rgb[i];
      g += _rgb[i + 1];
      b += _rgb[i + 2];
      n++;
    }

    for (var x = 0; x < width; x++) {
      add(x, 0);
      add(x, height - 1);
    }

    for (var y = 1; y < height - 1; y++) {
      add(0, y);
      add(width - 1, y);
    }

    return (r / n / 255, g / n / 255, b / n / 255);
  }

  /// How pink a colour of the artwork is, by its red, from 0 (the dark of the square's inside) to 1: the dark is
  /// nearly without red, every pink of the ring and the note nearly all red.
  static double _pinkness(double red) => ((red - 0.2) / 0.4).clamp(0.0, 1.0);

  /// The point of the rounded square shrunk by [inset] nearest to (x, y): (x, y) itself when it is inside.
  static (double, double) _nearestInside(double x, double y, double inset) {
    final radius = _radius - inset;
    // The rectangle of the corners' centres; the shape is every point within [radius] of it.
    final kx = (_right - _left) / 2 - inset - radius, ky = (_bottom - _top) / 2 - inset - radius;
    final qx = (x - _cx).clamp(-kx, kx), qy = (y - _cy).clamp(-ky, ky);
    final dx = x - _cx - qx, dy = y - _cy - qy;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance <= radius) {
      return (x, y);
    }

    return (_cx + qx + dx * radius / distance, _cy + qy + dy * radius / distance);
  }
}
