import 'package:flutter/widgets.dart';

/// On a TV, Flutter's directional navigation: the D-pad moves the focus, and a slider only takes
/// left and right, so that up and down go on to the controls above or below it, instead of moving
/// the song back and forth.
class DirectionalNavigation extends StatelessWidget {
  const DirectionalNavigation({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => enabled
      ? MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: child,
        )
      : child;
}

extension TelevisionContext on BuildContext {
  /// Whether the remote drives the app here, as on a TV: the navigation mode [DirectionalNavigation] sets, read from
  /// the tree rather than asked of the platform, so that a test's tree, or a screenshot's, says it for itself. Not where
  /// no [MediaQuery] is above.
  bool get television => MediaQuery.maybeNavigationModeOf(this) == NavigationMode.directional;
}
