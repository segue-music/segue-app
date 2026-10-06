import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' show decodePng;
import 'package:segue/ui/theme.dart';

double hue(Color color) => HSLColor.fromColor(color).hue;

/// How far apart two hues are, around the circle.
double hueDistance(double a, double b) {
  final distance = (a - b).abs() % 360;
  return distance > 180 ? 360 - distance : distance;
}

/// WCAG's contrast ratio, from 1 (none) to 21 (black on white).
double contrast(Color a, Color b) {
  final (light, dark) = (a.computeLuminance(), b.computeLuminance());
  return light > dark ? (light + 0.05) / (dark + 0.05) : (dark + 0.05) / (light + 0.05);
}

/// How far apart two colors are: the largest difference between their channels, from 0 to 1.
double colorDistance(Color a, Color b) => [(a.r - b.r).abs(), (a.g - b.g).abs(), (a.b - b.b).abs()].reduce(max);

void main() {
  test('the icon\'s colors are those of its artwork, tool/icon.png', () {
    final artwork = decodePng(File('tool/icon.png').readAsBytesSync())!;

    // The mean color of the 5 × 5 pixels around (x, y).
    Color at(int x, int y) {
      var (r, g, b) = (0.0, 0.0, 0.0);

      for (var j = -2; j <= 2; j++) {
        for (var i = -2; i <= 2; i++) {
          final pixel = artwork.getPixel(x + i, y + j);
          r += pixel.r;
          g += pixel.g;
          b += pixel.b;
        }
      }

      return Color.fromARGB(255, (r / 25).round(), (g / 25).round(), (b / 25).round());
    }

    // Where each part is in the artwork, as measured on it: a new artwork needs these taken again, as it needs
    // tool/icons.dart measured again.
    final parts = {
      'the rounded square': (iconPink, at(74, 330)),
      'the left half of the ring': (iconDeepPink, at(131, 338)),
      'the right half of the ring': (iconLightPink, at(525, 338)),
      'the black around the square': (iconBlack, at(20, 20)),
    };

    for (final MapEntry(key: part, value: (color, painted)) in parts.entries) {
      expect(colorDistance(color, painted), lessThan(12 / 255), reason: '$part: $color, and $painted in the artwork');
    }
  });

  test('the theme\'s colors are the icon\'s: its pink first, then the deep and the light pink of the ring', () {
    for (final brightness in Brightness.values) {
      final colors = segueTheme(brightness).colorScheme;
      final roles = {
        'primary': (colors.primary, iconPink),
        'secondary': (colors.secondary, iconDeepPink),
        'tertiary': (colors.tertiary, iconLightPink),
      };

      // HSL's hue, which drifts a little from Material's as a color gets lighter.
      for (final MapEntry(key: role, value: (color, icon)) in roles.entries) {
        expect(hueDistance(hue(color), hue(icon)), lessThan(20), reason: '$brightness $role');
      }
    }
  });

  test('in the dark, the theme\'s color is the icon\'s pink itself, rather than Material\'s pastel', () {
    expect(segueTheme(Brightness.dark).colorScheme.primary, iconPink);
  });

  test('in the dark, the app\'s background is the icon\'s black, and the bars and tiles stand out on it', () {
    final theme = segueTheme(Brightness.dark);
    final colors = theme.colorScheme;
    expect(colors.surface, iconBlack);
    expect(theme.scaffoldBackgroundColor, iconBlack);
    expect(iconBlack.computeLuminance(), lessThan(0.003), reason: 'black');

    for (final container in [colors.surfaceContainer, colors.surfaceContainerHigh, colors.surfaceContainerHighest]) {
      expect(container.computeLuminance(), greaterThan(colors.surface.computeLuminance()));
    }
  });

  test('text and icons are a little nearer white in the dark, and black in the light, than Material\'s tones', () {
    for (final brightness in Brightness.values) {
      final colors = segueTheme(brightness).colorScheme;
      final material = ColorScheme.fromSeed(
        seedColor: iconPink,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      );
      final ink = brightness == Brightness.dark ? Colors.white : Colors.black;
      final roles = {
        'onSurface': (colors.onSurface, material.onSurface),
        'onSurfaceVariant': (colors.onSurfaceVariant, material.onSurfaceVariant),
      };

      for (final MapEntry(key: role, value: (color, tone)) in roles.entries) {
        expect(contrast(color, ink), lessThan(contrast(tone, ink)), reason: '$brightness $role: nearer the ink');
        expect(contrast(color, ink), greaterThan(1.05), reason: '$brightness $role: still tinted, not the ink');
      }
    }
  });

  test('text on the theme\'s colors is readable, as is the theme\'s color on the background', () {
    for (final brightness in Brightness.values) {
      final colors = segueTheme(brightness).colorScheme;
      final pairs = {
        'onPrimary': (colors.onPrimary, colors.primary),
        'onPrimaryContainer': (colors.onPrimaryContainer, colors.primaryContainer),
        'onSecondary': (colors.onSecondary, colors.secondary),
        'onSecondaryContainer': (colors.onSecondaryContainer, colors.secondaryContainer),
        'onTertiary': (colors.onTertiary, colors.tertiary),
        'onTertiaryContainer': (colors.onTertiaryContainer, colors.tertiaryContainer),
        'onSurface': (colors.onSurface, colors.surface),
        'onSurfaceVariant': (colors.onSurfaceVariant, colors.surface),
        // The current song, in the theme's color.
        'primary on surface': (colors.primary, colors.surface),
        'primary on surfaceContainer': (colors.primary, colors.surfaceContainer),
      };

      for (final MapEntry(key: name, value: (text, background)) in pairs.entries) {
        expect(contrast(text, background), greaterThanOrEqualTo(4.5), reason: '$brightness $name');
      }
    }
  });

  testWidgets('a top bar keeps its color as a page scrolls under it, in the light and in the dark', (tester) async {
    for (final brightness in Brightness.values) {
      final theme = segueTheme(brightness);
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(brightness), // each from the start, rather than the one before turning into it
          theme: theme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Álbuns')),
            body: ListView(children: [for (var i = 0; i < 100; i++) ListTile(title: Text('Album $i'))]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      (Color?, double) bar() {
        final material = tester.widget<Material>(
          find.descendant(of: find.byType(AppBar), matching: find.byType(Material)).first,
        );
        return (material.color, material.elevation);
      }

      expect(bar(), (theme.colorScheme.surface, 0), reason: '$brightness');
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(bar(), (theme.colorScheme.surface, 0), reason: '$brightness, scrolled under');
    }
  });
}
