import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:segue/server/reachability.dart';
import 'package:segue/server/server.dart';

void main() {
  test('a server that answers is in reach, a refusal too', () async {
    var refuse = false;
    final reachability = Reachability(() async {
      if (refuse) {
        throw const ServerError('wrong password', isAuth: true);
      }
    });

    addTearDown(reachability.dispose);
    expect(await reachability.check(), isTrue);
    refuse = true;
    expect(await reachability.check(), isTrue);
  });

  test('out of reach, the server is asked again every so often, until it answers', () {
    fakeAsync((time) {
      var reachable = false;
      var pings = 0;
      final reachability = Reachability(() async {
        pings++;

        if (!reachable) {
          throw const SocketException('no route to host');
        }
      }, retry: const Duration(seconds: 30));

      unawaited(reachability.check());
      time.flushMicrotasks();
      expect(reachability.value, isFalse);
      expect(pings, 1);

      time.elapse(const Duration(seconds: 30));
      expect(pings, 2);
      expect(reachability.value, isFalse);

      reachable = true;
      time.elapse(const Duration(seconds: 30));
      expect(pings, 3);
      expect(reachability.value, isTrue);

      // In reach, nothing more.
      time.elapse(const Duration(minutes: 5));
      expect(pings, 3);
      reachability.dispose();
    });
  });

  test('the log says as the server goes out of reach, with why, and as it comes back, once each', () {
    fakeAsync((time) {
      var reachable = false;
      final said = <String>[];
      final subscription = Logger.root.onRecord.listen(
        (record) =>
            said.add('${record.level.name} ${record.message}${record.error == null ? '' : ': ${record.error}'}'),
      );
      final reachability = Reachability(() async {
        if (!reachable) {
          throw const SocketException('no route to host');
        }
      }, retry: const Duration(seconds: 30));

      unawaited(reachability.check());
      time.elapse(const Duration(minutes: 2));
      reachability.lost(const SocketException('connection reset'));
      reachable = true;
      time.elapse(const Duration(seconds: 30));
      unawaited(reachability.check());
      time.flushMicrotasks();
      expect(said, [
        'WARNING media server out of reach: SocketException: no route to host',
        'INFO media server back in reach',
      ]);
      reachability.dispose();
      unawaited(subscription.cancel());
    });
  });

  test('as the first ping goes, whether the server is in reach is known once it answers; out of reach, at once', () {
    fakeAsync((time) {
      var pings = 0;
      final reachability = Reachability(() async {
        pings++;
        await Future<void>.delayed(const Duration(seconds: 1));
      }, retry: const Duration(seconds: 30));

      bool? settled;

      unawaited(reachability.check());
      unawaited(reachability.check());
      unawaited(reachability.settled.then((value) => settled = value));
      time.elapse(const Duration(milliseconds: 500));
      expect(pings, 1, reason: 'one ping at a time');
      expect(settled, isNull);
      time.elapse(const Duration(milliseconds: 500));
      expect(settled, isTrue);

      // Out of reach, not after the ping that goes every 30 s.
      reachability.lost();
      time.elapse(const Duration(seconds: 30));
      settled = null;
      unawaited(reachability.settled.then((value) => settled = value));
      time.flushMicrotasks();
      expect(pings, 2);
      expect(settled, isFalse);
      reachability.dispose();
    });
  });

  test('a server that doesn\'t answer in time is out of reach', () {
    fakeAsync((time) {
      final reachability = Reachability(() => Completer<void>().future, timeout: const Duration(seconds: 5));

      unawaited(reachability.check());
      time.elapse(const Duration(seconds: 5));
      expect(reachability.value, isFalse);
      reachability.dispose();
    });
  });
}
