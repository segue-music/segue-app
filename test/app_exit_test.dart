import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/app.dart';

void main() {
  testWidgets('a window closing on a computer cancels Flutter\'s exit, and the app, once closed, ends itself, asking '
      'its listeners nothing more', (tester) async {
    final failures = <Object>[];
    late Future<AppExitResponse> response;

    await tester.pumpWidget(const SegueApp(session: null));
    // An exit that asks nothing (AppExitType.required), which the test's binding refuses, failing in the app's zone.
    runZonedGuarded(() => response = tester.binding.handleRequestAppExit(), (error, _) => failures.add(error));
    expect(await response, AppExitResponse.cancel);
    await tester.pump();
    expect(failures, [
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        'Unexpected application exit request while running test',
      ),
    ]);
  });
}
