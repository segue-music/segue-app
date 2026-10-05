import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  test('the theme\'s colors are the icon\'s: magenta first, then the purple and the pink of the ring', () {
    for (final brightness in Brightness.values) {
      final colors = segueTheme(brightness).colorScheme;
      final roles = {
        'primary': (colors.primary, iconMagenta),
        'secondary': (colors.secondary, iconPurple),
        'tertiary': (colors.tertiary, iconPink),
      };

      // HSL's hue, which drifts a little from Material's as a color gets lighter.
      for (final MapEntry(key: role, value: (color, icon)) in roles.entries) {
        expect(hueDistance(hue(color), hue(icon)), lessThan(20), reason: '$brightness $role');
      }
    }
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
        seedColor: iconMagenta,
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
}
