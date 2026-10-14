import 'package:flutter/material.dart';

import 'directional_navigation.dart';

extension TouchScreenContext on BuildContext {
  /// Whether the app is on a touch screen, a phone's or a tablet's: by the platform, not by whether a mouse is connected,
  /// since on a computer the system says the mouse is gone whenever the pointer leaves the window. A TV, though Android,
  /// has none.
  bool get touch =>
      !television &&
      switch (Theme.of(this).platform) {
        TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
        TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
      };

  /// Whether the app is on a phone: a touch screen less than 600 across, as Material counts, by its narrower side, which
  /// turning it doesn't change. A tablet is wider; a TV, 540 across, has no touch screen.
  bool get phone => touch && MediaQuery.sizeOf(this).shortestSide < 600;
}
