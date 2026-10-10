import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'swipe_back.dart';
import 'themed_icon.dart';

/// The pink of the app's icon (tool/icon.png): its rounded square.
const iconPink = Color(0xFFF9358E);

/// The deep pink of the left half of the ring around the note, in the icon.
const iconDeepPink = Color(0xFFDD0365);

/// The light pink of the right half of the ring.
const iconLightPink = Color(0xFFFD73AD);

/// The black around the icon's rounded square.
const iconBlack = Color(0xFF090909);

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

/// The app's theme, light or dark. Whatever has the focus stands out: a TV is driven with a remote
/// from across the room, and Material's own focus highlights are faint. Buttons get a ring; lists,
/// the side rail and the tiles a strong tint (and, where an image would hide it, a FocusRing).
///
/// On a computer the pointer is a hand over what can be clicked: Flutter leaves the arrow over buttons
/// and lists there, as native apps do, and the hand only on the web. The theme gives buttons and list
/// tiles the hand; an InkWell, which has no theme for it, says so itself.
ThemeData segueTheme(Brightness brightness) {
  final colors = _colors(brightness);
  final ring = WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused) ? BorderSide(color: colors.onSurface, width: 3) : null,
  );
  final buttons = ButtonStyle(side: ring, mouseCursor: WidgetStateMouseCursor.clickable);
  return ThemeData(
    colorScheme: colors,
    focusColor: colors.primary.withValues(alpha: 0.35),
    // The top bar in the background's color, always: Material's tints it as a page scrolls under it.
    appBarTheme: AppBarTheme(
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

/// The icon's colors, in Material's tones: its pink, and around it everything else (in the dark, the bars and the tiles
/// are tinted with it, on the icon's black). The deep pink of the ring is the secondary color (the side rail's selected
/// section), and its light pink the tertiary. Each comes from a scheme of its own, where it is the primary, so that the
/// text on it stays readable.
ColorScheme _colors(Brightness brightness) {
  ColorScheme seeded(Color seed) =>
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness, dynamicSchemeVariant: DynamicSchemeVariant.vibrant);

  final (deep, light) = (seeded(iconDeepPink), seeded(iconLightPink));
  final tones = seeded(iconPink);
  final ink = brightness == Brightness.dark ? Colors.white : Colors.black;
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
    // Text and icons a third of the way from Material's tones to white in the dark and to black in the light, which
    // are soft next to the icon; still with the pink's tint.
    onSurface: Color.lerp(tones.onSurface, ink, 0.3),
    onSurfaceVariant: Color.lerp(tones.onSurfaceVariant, ink, 0.3),
  );

  if (brightness == Brightness.light) {
    return colors;
  }

  // In the dark, Material's primary is a pastel, faint next to the icon: the icon's pink itself instead, with the
  // darkest of the pinks on it. And the background, Material's near black, is the icon's black, as its darkest surfaces.
  return colors.copyWith(
    primary: iconPink,
    onPrimary: colors.onPrimaryFixed,
    surfaceTint: iconPink,
    surface: iconBlack,
    surfaceDim: iconBlack,
    surfaceContainerLowest: iconBlack,
  );
}
