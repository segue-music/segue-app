import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/player/television_player.dart';
import 'package:segue/ui/widgets/cover.dart';

/// A picture 40 pixels square, [paint] drawn on it.
Future<ui.Image> picture(WidgetTester tester, void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await tester.runAsync(() => recorder.endRecording().toImage(40, 40));
  addTearDown(image!.dispose);

  return image;
}

void main() {
  testWidgets('a cover\'s color is the hue most of its colored pixels have, not their average; of one with hardly any '
      'color, a gray', (tester) async {
    Future<Color?> colorOf(ui.Image image) => tester.runAsync<Color?>(() => prominentColorOf(image));
    void fill(Canvas canvas, Rect rect, Color color) => canvas.drawRect(rect, Paint()..color = color);

    // A quarter of it red, the rest gray: the gray, a lot of it, has no color, and the red is what it's of.
    final redOnGray = await picture(tester, (canvas) {
      fill(canvas, const Rect.fromLTWH(0, 0, 40, 40), const Color(0xFF808080));
      fill(canvas, const Rect.fromLTWH(0, 0, 20, 20), const Color(0xFFDC1E1E));
    });
    expect(await colorOf(redOnGray), const Color(0xFFDC1E1E));

    // Mostly blue, some yellow: blue, rather than the gray their average is.
    final blueAndYellow = await picture(tester, (canvas) {
      fill(canvas, const Rect.fromLTWH(0, 0, 40, 24), const Color(0xFF1E3CC8));
      fill(canvas, const Rect.fromLTWH(0, 24, 40, 16), const Color(0xFFF0DC28));
    });
    expect(await colorOf(blueAndYellow), const Color(0xFF1E3CC8));

    // Two blues of hues side by side: one color, between them, weighed by how much of each there is.
    final blues = await picture(tester, (canvas) {
      fill(canvas, const Rect.fromLTWH(0, 0, 40, 20), const Color(0xFF0000FF));
      fill(canvas, const Rect.fromLTWH(0, 20, 40, 20), const Color(0xFF0020FF));
    });
    expect(await colorOf(blues), const Color(0xFF0010FF));

    // A black and white photo, a speck of red in it: gray.
    final blackAndWhite = await picture(tester, (canvas) {
      fill(canvas, const Rect.fromLTWH(0, 0, 40, 20), Colors.black);
      fill(canvas, const Rect.fromLTWH(0, 20, 40, 20), Colors.white);
      fill(canvas, const Rect.fromLTWH(0, 0, 4, 4), const Color(0xFFDC1E1E));
    });
    final gray = HSLColor.fromColor((await colorOf(blackAndWhite))!);
    expect(gray.saturation, lessThan(0.1));
    expect(gray.lightness, closeTo(0.5, 0.05));
  });

  test('the TV player\'s background has its cover\'s hue, dark in the dark theme and light in the light one, not too '
      'vivid; a gray cover\'s, gray', () {
    final red = HSLColor.fromColor(const Color(0xFFDC1E1E));

    for (final (brightness, lightness) in [(Brightness.dark, 0.18), (Brightness.light, 0.88)]) {
      final backdrop = HSLColor.fromColor(CoverBackground.backdrop(const Color(0xFFDC1E1E), brightness));
      expect(backdrop.hue, closeTo(red.hue, 1), reason: '$brightness');
      expect(backdrop.lightness, closeTo(lightness, 0.01), reason: '$brightness');
      expect(backdrop.saturation, closeTo(0.6, 0.01), reason: '$brightness');
    }

    final gray = HSLColor.fromColor(CoverBackground.backdrop(const Color(0xFF808080), Brightness.dark));
    expect(gray.saturation, 0);
  });
}
