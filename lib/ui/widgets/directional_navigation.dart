import 'package:flutter/widgets.dart';

/// On a TV, Flutter's directional navigation: the D-pad moves the focus, and a slider only takes
/// left and right, so that up and down go on to the controls above or below it, instead of moving
/// the song back and forth.
class DirectionalNavigation extends StatelessWidget {
  const DirectionalNavigation({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  /// Whether the remote drives the app where [context] is, as on a TV; not where no [MediaQuery] is above it.
  static bool of(BuildContext context) => MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional;

  @override
  Widget build(BuildContext context) => enabled
      ? MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: child,
        )
      : child;
}
