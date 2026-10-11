import 'dart:async';

import 'package:segue/ui/widgets/equalizer.dart';

/// Runs each test file here. Equalizers stand still in them, since a page with one that moves never settles
/// (`pumpAndSettle`); `equalizer_test.dart` sets them moving.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Equalizer.moves = false;
  await testMain();
}
