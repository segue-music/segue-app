import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../services.dart';
import 'equalizer.dart';
import 'themed_icon.dart';

/// A cover from the media server, or a placeholder.
class Cover extends StatelessWidget {
  const Cover(this.id, {this.size = 300, this.icon = HugeIcons.strokeRoundedCd, this.gapless = false, super.key});

  final String? id;

  /// Pixels asked of the server.
  final int size;

  /// What the placeholder shows.
  final HugeIconData icon;

  /// Whether, as [id] changes, the cover shown stays until the new one has loaded, rather than leaving nothing: for
  /// the cover of what plays, which changes with the song. A media server may give each song of an album a cover of
  /// its own, the same picture, which would otherwise go and come back.
  final bool gapless;

  /// Loads the cover [id], at [size] pixels, ahead of a [Cover] that shows it, which then shows it at once. One that
  /// can't be loaded is left to that cover's placeholder.
  static Future<void> preload(BuildContext context, String id, {int size = 300}) =>
      precacheImage(_image(context, id, size), context, onError: (_, _) {});

  /// The color of the cover [id], at [size] pixels, on average over the part of it that [region] picks by its size (as
  /// where a bar goes over it); null where it can't be loaded.
  static Future<Color?> averageColor(
    BuildContext context,
    String id, {
    required Rect Function(Size image) region,
    int size = 300,
  }) async {
    final loaded = Completer<ImageInfo?>();
    final stream = _image(context, id, size).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (image, _) => loaded.isCompleted ? image.dispose() : loaded.complete(image),
      onError: (_, _) => loaded.isCompleted ? null : loaded.complete(null),
    );
    stream.addListener(listener);
    final info = await loaded.future;
    stream.removeListener(listener);

    if (info == null) {
      return null;
    }

    try {
      final image = info.image;
      return await averageColorOf(image, region(Size(image.width.toDouble(), image.height.toDouble())));
    } finally {
      info.dispose();
    }
  }

  static ImageProvider _image(BuildContext context, String id, int size) =>
      NetworkImage(ServicesScope.of(context).api.coverArtUrl(id, size: size).toString());

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: ThemedIcon(icon)),
    );
    final id = this.id;

    if (id == null) {
      return placeholder;
    }

    return Image(
      image: _image(context, id, size),
      fit: BoxFit.cover,
      gaplessPlayback: gapless,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// The color of [image] on average over [region], as see-through as the image is there, on average; null where the
/// region has none of it.
Future<Color?> averageColorOf(ui.Image image, Rect region) async {
  final bytes = await image.toByteData();
  final area = region.intersect(Offset.zero & Size(image.width.toDouble(), image.height.toDouble()));

  if (bytes == null || area.isEmpty) {
    return null;
  }

  var (red, green, blue, alpha, pixels) = (0, 0, 0, 0, 0);

  for (var y = area.top.floor(); y < area.bottom.ceil(); y++) {
    for (var x = area.left.floor(); x < area.right.ceil(); x++) {
      final at = (y * image.width + x) * 4;
      red += bytes.getUint8(at);
      green += bytes.getUint8(at + 1);
      blue += bytes.getUint8(at + 2);
      alpha += bytes.getUint8(at + 3);
      pixels++;
    }
  }

  if (alpha == 0) {
    return const Color(0x00000000);
  }

  // The bytes are premultiplied by the alpha: over the alpha's sum, each channel's sum is the color's own.
  int channel(int sum) => min(sum * 255 ~/ alpha, 255);
  return Color.fromARGB(alpha ~/ pixels, channel(red), channel(green), channel(blue));
}

/// A cover asked of the server at [size] pixels, more than [Cover]'s usual: the usual one, which the page that led here
/// has likely loaded already, shows under it until it comes.
class LargeCover extends StatelessWidget {
  const LargeCover(this.id, {required this.size, this.icon = HugeIcons.strokeRoundedCd, super.key});

  final String? id;

  /// Pixels asked of the server.
  final int size;

  /// What the placeholder shows.
  final HugeIconData icon;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Cover(id, icon: icon),
      Cover(id, size: size, icon: icon),
    ],
  );
}

/// A small cover, for a list.
class Thumbnail extends StatelessWidget {
  const Thumbnail(this.coverArt, {this.round = false, this.playing = false, this.icon, super.key});

  final String? coverArt;

  /// An artist's: round, with a person for a placeholder.
  final bool round;

  /// What the placeholder shows, where it isn't an album's or an artist's: a playlist's.
  final HugeIconData? icon;

  /// A song's that plays: the equalizer goes over it, on a veil.
  final bool playing;

  /// How big it is, square.
  static const size = 48.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: round
        ? ClipOval(child: Cover(coverArt, size: 96, icon: icon ?? HugeIcons.strokeRoundedUser))
        : ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(coverArt, size: 96, icon: icon ?? HugeIcons.strokeRoundedCd),
                // The primary color's light tone in either theme, which stands out on the dark veil.
                if (playing)
                  ColoredBox(
                    color: Colors.black54,
                    child: Equalizer(color: Theme.of(context).colorScheme.primaryFixedDim),
                  ),
              ],
            ),
          ),
  );
}
