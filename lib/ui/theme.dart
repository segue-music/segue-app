import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// The magenta of the app's icon (tool/icon.png): its rounded square.
const iconMagenta = Color(0xFFDB02A4);

/// The purple of the left half of the ring around the note, in the icon.
const iconPurple = Color(0xFF6F0180);

/// The pink of the right half of the ring.
const iconPink = Color(0xFFFD0B66);

/// The black around the icon's rounded square.
const iconBlack = Color(0xFF080606);

/// The magenta of the note, lit, in the icon: on a dark background it shines as the icon does.
const _litMagenta = Color(0xFFFC18B6);

/// The app's theme, light or dark. Whatever has the focus stands out: a TV is driven with a remote
/// from across the room, and Material's own focus highlights are faint. Buttons get a ring; lists,
/// the side rail and the tiles a strong tint (and, where an image would hide it, a FocusRing).
ThemeData segueTheme(Brightness brightness) {
  final colors = _colors(brightness);
  final ring = WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused) ? BorderSide(color: colors.onSurface, width: 3) : null,
  );
  final focusRing = ButtonStyle(side: ring);
  return ThemeData(
    colorScheme: colors,
    focusColor: colors.primary.withValues(alpha: 0.35),
    iconButtonTheme: IconButtonThemeData(style: focusRing),
    // The back arrow that Flutter puts in a page's top bar by itself, from Hugeicons as the rest.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const Icon(HugeIcons.strokeRoundedArrowLeft02),
    ),
    filledButtonTheme: FilledButtonThemeData(style: focusRing),
    textButtonTheme: TextButtonThemeData(style: focusRing),
    searchBarTheme: SearchBarThemeData(side: ring),
  );
}

/// The icon's colors, in Material's tones: the magenta, and around it everything else (in the dark, the bars and the
/// tiles are tinted with it, on the icon's black). The purple of the ring is the secondary color (the side rail's
/// selected section), and its pink the tertiary. Each comes from a scheme of its own, where it is the primary, so that the text on it
/// stays readable.
ColorScheme _colors(Brightness brightness) {
  ColorScheme seeded(Color seed) =>
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness, dynamicSchemeVariant: DynamicSchemeVariant.vibrant);

  final (purple, pink) = (seeded(iconPurple), seeded(iconPink));
  final tones = seeded(iconMagenta);
  final ink = brightness == Brightness.dark ? Colors.white : Colors.black;
  final colors = tones.copyWith(
    secondary: purple.primary,
    onSecondary: purple.onPrimary,
    secondaryContainer: purple.primaryContainer,
    onSecondaryContainer: purple.onPrimaryContainer,
    secondaryFixed: purple.primaryFixed,
    secondaryFixedDim: purple.primaryFixedDim,
    onSecondaryFixed: purple.onPrimaryFixed,
    onSecondaryFixedVariant: purple.onPrimaryFixedVariant,
    tertiary: pink.primary,
    onTertiary: pink.onPrimary,
    tertiaryContainer: pink.primaryContainer,
    onTertiaryContainer: pink.onPrimaryContainer,
    tertiaryFixed: pink.primaryFixed,
    tertiaryFixedDim: pink.primaryFixedDim,
    onTertiaryFixed: pink.onPrimaryFixed,
    onTertiaryFixedVariant: pink.onPrimaryFixedVariant,
    // Text and icons a third of the way from Material's tones to white in the dark and to black in the light, which
    // are soft next to the icon; still with the magenta's tint.
    onSurface: Color.lerp(tones.onSurface, ink, 0.3),
    onSurfaceVariant: Color.lerp(tones.onSurfaceVariant, ink, 0.3),
  );

  if (brightness == Brightness.light) {
    return colors;
  }

  // In the dark, Material's primary is a pastel, faint next to the icon: the note's magenta instead, with the darkest
  // of the magentas on it. And the background, Material's near black, is the icon's black, as its darkest surfaces.
  return colors.copyWith(
    primary: _litMagenta,
    onPrimary: colors.onPrimaryFixed,
    surfaceTint: _litMagenta,
    surface: iconBlack,
    surfaceDim: iconBlack,
    surfaceContainerLowest: iconBlack,
  );
}
