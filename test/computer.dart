import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A computer's platform, for a test of what only a computer has: the wide layout (the side rail, the top bar's
/// arrows), which a touch screen as wide, a tablet's, doesn't, having the phone's; the volume. Flutter's tests are
/// otherwise on Android's.
final computer = TargetPlatformVariant.only(TargetPlatform.linux);

/// The platform of a test on a screen [size] across: a computer's where it is wider than a phone's, for the wide
/// layout; Flutter's tests' own on one as narrow.
TestVariant<Object?> platformFor(Size size) => size.width < 600 ? const DefaultTestVariant() : computer;
