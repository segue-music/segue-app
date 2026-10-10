import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
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
