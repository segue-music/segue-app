import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger('Reachability');

/// Whether the media server answers: true until a request to it fails for the network (no route to it, no answer, a
/// connection cut short), and from then false, until a ping, one every [retry], gets an answer, or one past its
/// [timeout] gets one after all. Any answer counts, a refusal too: the server is there.
class Reachability extends ValueNotifier<bool> {
  /// [ping] asks the server for as little as it can answer.
  Reachability(this._ping, {this.retry = const Duration(seconds: 30), this.timeout = const Duration(seconds: 5)})
    : super(true);

  final Future<void> Function() _ping;

  /// How often the server is asked again while out of reach.
  final Duration retry;

  /// How long a ping waits for an answer: a server out of reach may leave a request waiting for minutes.
  final Duration timeout;

  Timer? _again;
  bool _disposed = false;

  /// The ping under way; null, none.
  Future<bool>? _checking;

  /// [value] once the ping under way, if any, has answered: until the first one does, as the app opens, that the server
  /// is in reach is only a guess, and a request to a server out of reach may wait for minutes. Out of reach, at once,
  /// rather than after the ping every [retry].
  Future<bool> get settled async => value ? await (_checking ?? Future.value(true)) : false;

  /// Asks the server now, unless a ping is under way already; whether it answered.
  Future<bool> check() => _checking ??= _check().whenComplete(() => _checking = null);

  Future<bool> _check() async {
    _again?.cancel();

    final ping = _ping();

    try {
      await ping.timeout(timeout);
      _set(true);
    } on TimeoutException catch (error) {
      lost(error);
      // The ping goes on, and an answer after all has the server in reach then, rather than at the next ping: as the
      // app opens, a phone's VPN, waking, may take longer than [timeout] to let the first request through.
      unawaited(
        ping.then(
          (_) => _answered(),
          onError: (Object error) {
            if (!isNetworkFailure(error)) {
              _answered();
            }
          },
        ),
      );
    } on Object catch (error) {
      if (isNetworkFailure(error)) {
        lost(error);
      } else {
        _set(true);
      }
    }

    return value;
  }

  /// A ping past its [timeout] got an answer.
  void _answered() {
    _again?.cancel();
    _set(true);
  }

  /// A request to the server failed for the network, with [error]: it is out of reach until a ping gets an answer.
  void lost([Object? error]) {
    _set(false, error);
    _again?.cancel();

    if (!_disposed) {
      _again = Timer(retry, () => unawaited(check()));
    }
  }

  /// [value], which the log has as it changes, when the server went, with why ([error]), and when it came back.
  void _set(bool reachable, [Object? error]) {
    if (_disposed) {
      return;
    }

    if (reachable && !value) {
      _log.info('media server back in reach');
    } else if (!reachable && value) {
      _log.warning('media server out of reach', error);
    }

    value = reachable;
  }

  @override
  void dispose() {
    _disposed = true;
    _again?.cancel();
    super.dispose();
  }
}

/// Whether [error], from a request to the media server, says the request got no answer, as the network failed it,
/// rather than that the server refused it.
bool isNetworkFailure(Object error) =>
    error is SocketException ||
    error is http.ClientException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is HttpException;
