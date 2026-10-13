import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../theme_choice.dart';
import '../widgets/themed_icon.dart';
import 'swipe_back.dart';

/// The pink of the app's icon (tool/icon.png): its rounded square.
const iconPink = Color(0xFFF9358E);

/// The deep pink of the left half of the ring around the note, in the icon.
const iconDeepPink = Color(0xFFDD0365);

/// The light pink of the right half of the ring.
const iconLightPink = Color(0xFFFD73AD);

/// The black around the icon's rounded square.
const iconBlack = Color(0xFF090909);

/// The wine inside the icon's rounded square, around the ring.
const iconWine = Color(0xFF1A020E);

/// The back arrow that Flutter puts in a page's top bar by itself.
const backArrow = HugeIcons.strokeRoundedArrowLeft02;

/// Each platform's page transitions, Flutter's, with a swipe to the right as a page's back arrow too. One for every
/// theme made, so that a theme made again is the same, as Flutter's builders are constants.
final _pageTransitions = PageTransitionsTheme(
  builders: {
    for (final MapEntry(key: platform, value: builder) in const PageTransitionsTheme().builders.entries)
      platform: SwipeBackPageTransitionsBuilder(builder),
  },
);

/// The app's theme, light or dark, in [palette]'s colors, with stronger text and outlines where [highContrast]. Whatever
/// has the focus stands out: a TV is driven with a remote from across the room, and Material's own focus highlights are
/// faint. Buttons get a ring; lists, the side rail and the tiles a strong tint (and, where an image would hide it, a
/// FocusRing).
///
/// On a computer the pointer is a hand over what can be clicked: Flutter leaves the arrow over buttons
/// and lists there, as native apps do, and the hand only on the web. The theme gives buttons and list
/// tiles the hand; an InkWell, which has no theme for it, says so itself.
ThemeData segueTheme(Brightness brightness, {Palette palette = Palette.segue, bool highContrast = false}) {
  final colors = segueColors(brightness, palette: palette, highContrast: highContrast);
  final ring = WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused) ? BorderSide(color: colors.onSurface, width: 3) : null,
  );
  final buttons = ButtonStyle(side: ring, mouseCursor: WidgetStateMouseCursor.clickable);

  return ThemeData(
    colorScheme: colors,
    focusColor: colors.primary.withValues(alpha: 0.35),
    // The top bar in the background's color, always: Material's tints it as a page scrolls under it.
    appBarTheme: AppBarThemeData(
      backgroundColor: colors.surface,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    iconButtonTheme: IconButtonThemeData(style: buttons),
    // The back arrow that Flutter puts in a page's top bar by itself, from Hugeicons as the rest.
    actionIconTheme: ActionIconThemeData(backButtonIconBuilder: (context) => const ThemedIcon(backArrow)),
    pageTransitionsTheme: _pageTransitions,
    filledButtonTheme: FilledButtonThemeData(style: buttons),
    textButtonTheme: TextButtonThemeData(style: buttons),
    listTileTheme: const ListTileThemeData(mouseCursor: WidgetStateMouseCursor.clickable),
    popupMenuTheme: const PopupMenuThemeData(mouseCursor: WidgetStateMouseCursor.clickable),
    searchBarTheme: SearchBarThemeData(side: ring),
  );
}

/// The icon's colors, in Material's tones, in [palette]: its pink, and around it everything else (in the dark, the bars
/// and the tiles on the icon's black, or on its wine). The deep pink of the ring is the secondary color (the side
/// rail's selected section), and its light pink the tertiary. Each comes from a scheme of its own, where it is the
/// primary, so that the text on it stays readable. [highContrast] takes Material's tones of the highest contrast, every
/// text at 7:1 at least on what it is on.
ColorScheme segueColors(Brightness brightness, {Palette palette = Palette.segue, bool highContrast = false}) {
  ColorScheme seeded(Color seed, {DynamicSchemeVariant variant = DynamicSchemeVariant.vibrant, double? contrast}) =>
      ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
        dynamicSchemeVariant: variant,
        contrastLevel: contrast ?? (highContrast ? 1 : 0),
      );

  final (deep, light) = (seeded(iconDeepPink), seeded(iconLightPink));
  final tones = seeded(iconPink);
  // The background, the bars and the tiles, the text on them and the outlines: the pink's tones, or, in the neutral
  // palette, Material's tones without a hue.
  final surfaces = palette == Palette.neutral ? seeded(iconPink, variant: DynamicSchemeVariant.monochrome) : tones;
  final dark = brightness == Brightness.dark;
  final ink = dark ? Colors.white : Colors.black;
  final colors = tones.copyWith(
    secondary: deep.primary,
    onSecondary: deep.onPrimary,
    secondaryContainer: deep.primaryContainer,
    onSecondaryContainer: deep.onPrimaryContainer,
    secondaryFixed: deep.primaryFixed,
    secondaryFixedDim: deep.primaryFixedDim,
    onSecondaryFixed: deep.onPrimaryFixed,
    onSecondaryFixedVariant: deep.onPrimaryFixedVariant,
    tertiary: light.primary,
    onTertiary: light.onPrimary,
    tertiaryContainer: light.primaryContainer,
    onTertiaryContainer: light.onPrimaryContainer,
    tertiaryFixed: light.primaryFixed,
    tertiaryFixedDim: light.primaryFixedDim,
    onTertiaryFixed: light.onPrimaryFixed,
    onTertiaryFixedVariant: light.onPrimaryFixedVariant,
    surface: surfaces.surface,
    surfaceDim: surfaces.surfaceDim,
    surfaceBright: surfaces.surfaceBright,
    surfaceContainerLowest: surfaces.surfaceContainerLowest,
    surfaceContainerLow: surfaces.surfaceContainerLow,
    surfaceContainer: surfaces.surfaceContainer,
    surfaceContainerHigh: surfaces.surfaceContainerHigh,
    surfaceContainerHighest: surfaces.surfaceContainerHighest,
    // Text and icons a third of the way from Material's tones to white in the dark and to black in the light, which
    // are soft next to the icon; still with the pink's tint, but in the neutral palette.
    onSurface: Color.lerp(surfaces.onSurface, ink, 0.3),
    onSurfaceVariant: Color.lerp(surfaces.onSurfaceVariant, ink, 0.3),
    outline: surfaces.outline,
    outlineVariant: surfaces.outlineVariant,
    inverseSurface: surfaces.inverseSurface,
    onInverseSurface: surfaces.onInverseSurface,
  );

  if (!dark) {
    return palette == Palette.wine ? _rose(colors) : colors;
  }

  // In the dark, Material's primary is a pastel, faint next to the icon: the icon's pink itself instead, with the
  // darkest of the pinks on it. Where the contrast is the highest, Material's is nearly white, the pink gone: the pastel
  // then, of the usual contrast, which is 7:1 on the bars still. And the background, Material's near black, is the
  // icon's black, as its darkest surfaces, or in the wine palette the wine inside it.
  final pastel = highContrast ? seeded(iconPink, contrast: 0) : null;
  final background = palette == Palette.wine ? iconWine : iconBlack;
  final darkColors = colors.copyWith(
    primary: pastel?.primary ?? iconPink,
    onPrimary: pastel?.onPrimary ?? colors.onPrimaryFixed,
    surfaceTint: pastel?.primary ?? iconPink,
    surface: background,
    surfaceDim: background,
    surfaceContainerLowest: background,
  );

  return palette == Palette.wine ? _onWine(darkColors) : darkColors;
}

/// The wine palette's dark [colors]: the bars and the tiles the icon's wine with more and more of its pink over it, the
/// higher they rise from the background, the wine itself.
ColorScheme _onWine(ColorScheme colors) {
  Color tinted(double amount) => Color.alphaBlend(iconPink.withValues(alpha: amount), iconWine);

  return colors.copyWith(
    surfaceContainerLow: tinted(0.06),
    surfaceContainer: tinted(0.1),
    surfaceContainerHigh: tinted(0.14),
    surfaceContainerHighest: tinted(0.18),
    surfaceBright: tinted(0.22),
  );
}

/// The wine palette's light [colors], a rosé: the background, the bars and the tiles white with more and more of the
/// icon's light pink over it, rosier than Material's tones, and the text and icons on them in the icon's wine. What is
/// selected on them (the bars' section, a chip), whose pink in Material's tones is as light as they are, is the light
/// pink at half, to stand out.
ColorScheme _rose(ColorScheme colors) {
  Color tinted(double amount) => Color.alphaBlend(iconLightPink.withValues(alpha: amount), Colors.white);

  return colors.copyWith(
    surfaceContainerLowest: tinted(0.07),
    surface: tinted(0.14),
    surfaceBright: tinted(0.14),
    surfaceContainerLow: tinted(0.19),
    surfaceContainer: tinted(0.24),
    surfaceContainerHigh: tinted(0.29),
    surfaceContainerHighest: tinted(0.34),
    surfaceDim: tinted(0.4),
    secondaryContainer: tinted(0.5),
    onSecondaryContainer: iconWine,
    onSurface: iconWine,
    onSurfaceVariant: Color.lerp(iconWine, colors.onSurfaceVariant, 0.5),
  );
}
