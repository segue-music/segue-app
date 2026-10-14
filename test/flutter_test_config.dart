import 'dart:async';

import 'package:logging/logging.dart';
import 'package:segue/log_file.dart';
import 'package:segue/ui/widgets/equalizer.dart';

/// Runs each test file here. Equalizers stand still in them, since a page with one that moves never settles
/// (`pumpAndSettle`); `equalizer_test.dart` sets them moving. What the app's loggers say goes to the console, as in the
/// app, but to no file.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Equalizer.moves = false;
  Logger.root.onRecord.listen(printRecord);
  await testMain();
}
