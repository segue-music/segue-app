import 'package:flutter/material.dart';

import 'player_page.dart';

/// On a wide screen, the middle of the home, between its bars (the top one, the side rail and the player's), where
/// pages open: an album, an artist, a genre, the queue, the full-screen player. The bars stay as they come and go.
///
/// Pages opened from in it find its navigator as [Navigator.of] does; [PageArea.navigatorOf] finds it from outside it
/// too, as from the player bar. Pages that cover the whole window (the cover) and sheets open in the app's.
class PageArea extends InheritedWidget {
  const PageArea({required this.navigator, required this.history, required super.child, super.key});

  final GlobalKey<NavigatorState> navigator;
  final PageHistory history;

  /// The navigator that pages open in: the page area's, where there is one; elsewhere (on a phone), the app's.
  static NavigatorState navigatorOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageArea>()?.navigator.currentState ?? Navigator.of(context);

  /// Whether [context] is in a page of the page area, rather than around it.
  static bool holds(BuildContext context) {
    final area = context.getInheritedWidgetOfExactType<PageArea>();
    return area != null && Navigator.maybeOf(context) == area.navigator.currentState;
  }

  @override
  bool updateShouldNotify(PageArea oldWidget) => navigator != oldWidget.navigator || history != oldWidget.history;
}

/// The pages opened in the page area, as a browser's history: going back closes the page on top, and going forward
/// opens again the last one closed, until another page opens.
class PageHistory extends NavigatorObserver with ChangeNotifier {
  /// The pages open, from the first, the home's sections, to the one on top.
  final _open = <Route<dynamic>>[];

  /// How to open again each page closed, the last one closed last.
  final _closed = <Route<void> Function()>[];

  /// Whether the page being opened is one closed before, rather than a new one.
  bool _reopening = false;

  /// The page on top; null before the first opens.
  Route<dynamic>? get current => _open.lastOrNull;

  bool get canGoBack => _open.length > 1;

  bool get canGoForward => _closed.isNotEmpty;

  void back() => navigator?.maybePop();

  void forward() {
    final navigator = this.navigator;

    if (navigator == null || _closed.isEmpty) {
      return;
    }

    _reopening = true;
    navigator.push(_closed.removeLast()());
  }

  /// Closes every page but the first, leaving nothing to go forward to: what the user goes to instead (a section,
  /// a search) starts over.
  void closeAll() {
    navigator?.popUntil((route) => route.isFirst);

    if (_closed.isNotEmpty) {
      _closed.clear();
      notifyListeners();
    }
  }

  /// How [route] opens again, going forward to it: as it opened, with the same page, built anew.
  static Route<void> Function()? _reopener(Route<dynamic> route) {
    if (route is PlayerRoute) {
      final lyrics = route.lyrics.value;
      return () => PlayerRoute(lyrics: lyrics);
    }

    if (route is MaterialPageRoute) {
      final builder = route.builder;
      final settings = route.settings;
      return () => MaterialPageRoute<void>(builder: builder, settings: settings);
    }

    return null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) {
      return;
    }

    // The first page, opening with the navigator, as the home builds: nothing to tell yet. Any other went with a
    // navigator before it, as when the window was narrow for a while.
    if (previousRoute == null) {
      _open
        ..clear()
        ..add(route);
      _closed.clear();
      return;
    }

    _open.add(route);

    if (!_reopening) {
      _closed.clear();
    }

    _reopening = false;
    notifyListeners();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_open.remove(route)) {
      return;
    }

    if (_reopener(route) case final reopen?) {
      _closed.add(reopen);
    }

    notifyListeners();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_open.remove(route)) {
      notifyListeners();
    }
  }

  /// A page in place of another, as the full-screen player's links open theirs: a new one.
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _open.indexOf(oldRoute);

    if (index < 0 || newRoute == null) {
      return;
    }

    _open[index] = newRoute;
    _closed.clear();
    notifyListeners();
  }
}
