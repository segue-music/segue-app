import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' show decodePng;
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/theme_choice.dart';
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

/// How far a color is from a gray: the difference between its strongest channel and its weakest, from 0 to 1.
double tint(Color color) => [color.r, color.g, color.b].reduce(max) - [color.r, color.g, color.b].reduce(min);

/// Every theme the app has, light and dark, in each palette, with Material's contrast and the highest.
final themes = [
  for (final brightness in Brightness.values)
    for (final palette in Palette.values)
      for (final highContrast in [false, true]) (brightness: brightness, palette: palette, highContrast: highContrast),
];

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
      'the wine inside the square': (iconWine, at(330, 105)),
    };

    for (final MapEntry(key: part, value: (color, painted)) in parts.entries) {
      expect(colorDistance(color, painted), lessThan(12 / 255), reason: '$part: $color, and $painted in the artwork');
    }
  });

  test('the theme\'s colors are the icon\'s: its pink first, then the deep and the light pink of the ring, in every '
      'palette, and with the highest contrast too', () {
    for (final (:brightness, :palette, :highContrast) in themes) {
      final colors = segueTheme(brightness, palette: palette, highContrast: highContrast).colorScheme;
      final roles = {
        'primary': (colors.primary, iconPink),
        'secondary': (colors.secondary, iconDeepPink),
        'tertiary': (colors.tertiary, iconLightPink),
      };

      // HSL's hue, which drifts a little from Material's as a color gets lighter.
      for (final MapEntry(key: role, value: (color, icon)) in roles.entries) {
        expect(hueDistance(hue(color), hue(icon)), lessThan(20), reason: '$brightness $palette $highContrast $role');
      }
    }
  });

  test(
    'in the dark, the theme\'s color is the icon\'s pink itself, rather than Material\'s pastel, in every palette',
    () {
      for (final palette in Palette.values) {
        expect(segueTheme(Brightness.dark, palette: palette).colorScheme.primary, iconPink, reason: '$palette');
      }
    },
  );

  test(
    'in the dark with the highest contrast, the theme\'s color is a pink still, rather than Material\'s near white',
    () {
      for (final palette in Palette.values) {
        final primary = segueTheme(Brightness.dark, palette: palette, highContrast: true).colorScheme.primary;
        expect(HSLColor.fromColor(primary).saturation, greaterThan(0.5), reason: '$palette');
        expect(HSLColor.fromColor(primary).lightness, lessThan(0.9), reason: '$palette');
      }
    },
  );

  test(
    'in the dark, the app\'s background is the icon\'s black, or in the wine palette the wine inside it, and the bars '
    'and tiles stand out on it',
    () {
      for (final (palette, background) in [
        (Palette.segue, iconBlack),
        (Palette.wine, iconWine),
        (Palette.neutral, iconBlack),
      ]) {
        final theme = segueTheme(Brightness.dark, palette: palette);
        final colors = theme.colorScheme;
        expect(colors.surface, background, reason: '$palette');
        expect(theme.scaffoldBackgroundColor, background, reason: '$palette');
        expect(background.computeLuminance(), lessThan(0.003), reason: '$palette: nearly black');
        var below = colors.surface;

        for (final container in [
          colors.surfaceContainerLow,
          colors.surfaceContainer,
          colors.surfaceContainerHigh,
          colors.surfaceContainerHighest,
        ]) {
          expect(container.computeLuminance(), greaterThan(below.computeLuminance()), reason: '$palette');
          below = container;
        }
      }
    },
  );

  test('in the wine palette, the dark\'s bars and tiles are wines too, and the light\'s backgrounds rosier than the '
      'first palette\'s, under text in the wine', () {
    final dark = segueTheme(Brightness.dark, palette: Palette.wine).colorScheme;

    for (final container in [dark.surfaceContainer, dark.surfaceContainerHighest]) {
      expect(hueDistance(hue(container), hue(iconWine)), lessThan(10));
      expect(HSLColor.fromColor(container).saturation, greaterThan(0.5));
    }

    final (rose, pink) = (
      segueTheme(Brightness.light, palette: Palette.wine).colorScheme,
      segueTheme(Brightness.light).colorScheme,
    );
    expect(rose.onSurface, iconWine);

    for (final (role, color, first) in [
      ('surface', rose.surface, pink.surface),
      ('surfaceContainer', rose.surfaceContainer, pink.surfaceContainer),
    ]) {
      expect(hueDistance(hue(color), hue(iconLightPink)), lessThan(10), reason: role);
      expect(tint(color), greaterThan(tint(first) * 1.3), reason: '$role, rosier');
    }
  });

  test('in the neutral palette, the backgrounds, the bars and the tiles are grays, and the theme\'s colors pinks', () {
    for (final brightness in Brightness.values) {
      final colors = segueTheme(brightness, palette: Palette.neutral).colorScheme;

      for (final (role, color) in [
        ('surface', colors.surface),
        ('surfaceContainerLow', colors.surfaceContainerLow),
        ('surfaceContainer', colors.surfaceContainer),
        ('surfaceContainerHighest', colors.surfaceContainerHighest),
        ('onSurface', colors.onSurface),
        ('outlineVariant', colors.outlineVariant),
      ]) {
        expect(HSLColor.fromColor(color).saturation, lessThan(0.02), reason: '$brightness $role');
      }

      expect(HSLColor.fromColor(colors.primary).saturation, greaterThan(0.5), reason: '$brightness');
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

  test(
    'text on the theme\'s colors is readable, as is the theme\'s color on the background, in every palette, and with '
    'the highest contrast more so',
    () {
      for (final (:brightness, :palette, :highContrast) in themes) {
        final colors = segueTheme(brightness, palette: palette, highContrast: highContrast).colorScheme;
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
          expect(contrast(text, background), greaterThanOrEqualTo(4.5), reason: '$brightness $palette $name');
        }

        if (!highContrast) {
          continue;
        }

        // WCAG's AAA, Material's highest contrast, for the text on the background and the bars.
        for (final background in [colors.surface, colors.surfaceContainer]) {
          for (final (name, text) in [
            ('onSurface', colors.onSurface),
            ('onSurfaceVariant', colors.onSurfaceVariant),
            ('primary', colors.primary),
          ]) {
            expect(contrast(text, background), greaterThanOrEqualTo(7), reason: '$brightness $palette $name');
          }
        }
      }
    },
  );

  testWidgets('a top bar keeps its color as a page scrolls under it, in the light and in the dark', (tester) async {
    for (final brightness in Brightness.values) {
      final theme = segueTheme(brightness);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('pt')],
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
