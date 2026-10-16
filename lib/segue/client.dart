import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol.dart';

final _log = Logger('SegueClient');

/// Obeys a command from another device. Throwing [CommandFailed] reports it as failed.
typedef CommandHandler = Future<void> Function(Command command, String from);

/// A command this device can't carry out; [message] goes back to the device that sent it.
class CommandFailed implements Exception {
  const CommandFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

enum HubStatus { connecting, connected, offline, rejected }

/// The hub closed the connection before accepting the device.
class HubClosed implements Exception {
  const HubClosed(this.code, this.reason);

  final int? code;
  final String? reason;

  /// Retrying won't help: wrong credentials, a bad hello, or the device connected elsewhere.
  bool get isFinal => code == CloseCode.unauthorized || code == CloseCode.badHello || code == CloseCode.replaced;

  @override
  String toString() => 'hub closed the connection: $code $reason';
}

/// Talks to the hub for this device: keeps the user's other devices up to date, reports this
/// player's state and obeys commands. [start] keeps it connected; [connect] is a single attempt.
class SegueClient extends ChangeNotifier {
  SegueClient({
    required this.url,
    required this.auth,
    required this.device,
    this.onCommand,
    this.onConnected,
    WebSocketChannel Function(Uri url)? channelFactory,
    this.answerTimeout = const Duration(seconds: 25),
    this.outOfReachAfter = const Duration(seconds: 5),
  }) : _channelFactory = channelFactory ?? WebSocketChannel.connect;

  /// How long a command or a transfer waits for the hub's answer. The hub answers a command within 10 s and a transfer
  /// within 20 s, so none by then means a connection that died without a close (the hub crashed, the network went
  /// away), which a proxy can keep open on this side: it is closed, and made again. The app sends no pings to notice it
  /// sooner, which would cost a phone battery for a case that is rare (SPEC.md, section 9).
  final Duration answerTimeout;

  /// How long [devices] stay as they were after the connection ends, as [start] makes it again: time for the hub to
  /// restart, or for an app back from the background to reconnect. Without it by then, the hub is out of reach, and so
  /// is every other device: they go offline here, and the app plays on its own (SPEC.md, section 9).
  final Duration outOfReachAfter;

  /// The hub's WebSocket URL; a new one is where the next connection goes.
  Uri url;
  final Auth auth;
  final DeviceInfo device;
  CommandHandler? onCommand;

  /// Called after every (re)connection, e.g. to report the full state again.
  VoidCallback? onConnected;

  /// The user's other devices, by id: all offline once the hub has been out of reach for [outOfReachAfter].
  final devices = <String, Device>{};
  HubStatus status = HubStatus.offline;

  /// How the last connection ended; says why when [status] is [HubStatus.rejected].
  HubClosed? lastClose;

  /// The user's last playback, as of the last welcome, and the device that holds it since: the hub sends it again each
  /// time another device holds it, or none does (SPEC.md, section 7).
  LastPlayback? lastPlayback;

  final WebSocketChannel Function(Uri url) _channelFactory;
  WebSocketChannel? _channel;
  bool _open = false;
  Completer<void>? _ended;
  final _waiting = <String, Completer<Result>>{};
  int _seq = 0;
  int _clockOffset = 0; // hub time minus local time
  bool _running = false;
  Timer? _outOfReach;

  /// Hub time now, in epoch ms.
  int get hubNow => DateTime.now().millisecondsSinceEpoch + _clockOffset;

  /// Connects and keeps reconnecting, with backoff, until [close] or a final rejection.
  Future<void> start() async {
    _running = true;
    var backoff = const Duration(seconds: 1);
    // Whether the log has said the hub is out of reach since the last connection: by the time it is tried again
    // after one ends, backoff has gone up already.
    var unreachableLogged = false;

    while (_running) {
      _setStatus(HubStatus.connecting);

      try {
        await connect();
        _log.info('connected to $url');
        backoff = const Duration(seconds: 1);
        unreachableLogged = false;
        await closed;

        // This device leaving ([close]), or the hub closing the connection, with its code, or it ending with none: the
        // network, or the hub gone.
        if (!_running) {
          _log.info('left $url');
        } else if (lastClose?.code case final code?) {
          _log.info('disconnected from $url: $code ${lastClose?.reason ?? ''}'.trimRight());
        } else {
          _log.info('disconnected from $url');
        }

        // Closed by the hub after accepting us: the same device connected elsewhere (4003)
        // must not reconnect, or the two would take turns kicking each other out.
        if (lastClose?.isFinal ?? false) {
          _running = false;
          _setStatus(HubStatus.rejected);
          return;
        }
      } on HubClosed catch (e) {
        lastClose = e;

        // This device leaving ([close]) as it connected.
        if (!_running) {
          break;
        }

        _log.warning('refused by $url', e);

        if (e.isFinal) {
          _running = false;
          _setStatus(HubStatus.rejected);
          return;
        }
      } catch (e) {
        // A network error: retry below. Out of reach, the hub fails again and again, which the log says once, until it
        // connects again.
        if (!unreachableLogged) {
          _log.warning('no connection to $url', e);
          unreachableLogged = true;
        }
      }

      if (!_running) {
        break;
      }

      _setStatus(HubStatus.offline);
      await Future<void>.delayed(backoff);
      backoff = Duration(milliseconds: min(backoff.inMilliseconds * 2, 30000));
    }

    _setStatus(HubStatus.offline);
  }

  /// Completes when the current connection ends.
  Future<void> get closed => _ended?.future ?? Future.value();

  /// Opens one connection. Completes once the hub has accepted the device; throws [HubClosed] if
  /// the hub refuses it.
  Future<void> connect() async {
    final channel = _channelFactory(url);
    _channel = channel;
    await channel.ready;

    // Closed as it opened ([close]): this device leaves before it says hello.
    if (!identical(_channel, channel)) {
      await channel.sink.close(1000);
      throw const HubClosed(1000, 'closed as it opened');
    }

    _open = true;
    final welcomed = Completer<void>();
    final ended = _ended = Completer<void>();

    channel.stream.listen(
      (data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;

        _receive(msg);

        if (msg['type'] == 'welcome' && !welcomed.isCompleted) {
          welcomed.complete();
        }
      },
      onDone: () {
        _open = false;
        lastClose = HubClosed(channel.closeCode, channel.closeReason);

        for (final waiting in _waiting.values) {
          waiting.complete(const Result(ok: false, error: 'closed'));
        }

        _waiting.clear();

        if (welcomed.isCompleted) {
          _setStatus(HubStatus.offline);

          // Not as this device leaves ([close]), nor for a single attempt, which no other follows.
          if (_running) {
            _outOfReach = Timer(outOfReachAfter, _listOffline);
          }
        } else {
          welcomed.completeError(HubClosed(channel.closeCode, channel.closeReason));
        }

        ended.complete();
      },
      onError: (Object e) => _log.warning('connection to $url failed', e), // onDone follows
    );
    _send({'type': 'hello', 'protocol': protocolVersion, 'auth': auth.toJson(), 'device': device.toJson()});
    await welcomed.future;
    _setStatus(HubStatus.connected);
    onConnected?.call();
  }

  Future<void> close() async {
    _running = false;
    _outOfReach?.cancel();

    final channel = _channel;

    if (_open) {
      await channel?.sink.close(1000);
    } else {
      // A connection still opening, or that never opened (the hub out of reach), never finishes closing:
      // web_socket_channel takes the close only once it is open. [connect] closes it then, if it opens.
      _channel = null;
    }
  }

  /// Reports this device's playback. Send it on every change; the hub stamps the time.
  void sendState(PlayerState state) => _send({'type': 'state', 'state': state.toJson()});

  Future<Result> command(String target, Command command) => _logged(
    _ask({'type': 'command', 'target': target, 'command': command.toJson()}),
    '${command.action.name} on ${_nameOf(target)}',
  );

  /// Moves [from]'s queue, at its current position, to [to] (often this device: "continue here").
  /// Without [from], the last playback moves, from the device that holds it or from the hub's own
  /// record of it (SPEC.md, section 6).
  Future<Result> transfer(String? from, String to, {bool play = true}) => _logged(
    _ask({'type': 'transfer', 'from': ?from, 'to': to, 'play': play}),
    'moving ${from == null ? 'the last playback' : 'the music from ${_nameOf(from)}'} to ${_nameOf(to)}',
  );

  /// [result], which the log has where it failed, as [asked] failing.
  static Future<Result> _logged(Future<Result> result, String asked) async {
    final answer = await result;

    if (!answer.ok) {
      _log.warning('$asked failed: ${answer.error}');
    }

    return answer;
  }

  /// The name of the device whose id is [id], this one too, as the log says it: its id, where it isn't known.
  String _nameOf(String id) => id == device.id ? device.name : devices[id]?.info.name ?? id;

  /// Where a device's playback is now.
  int? positionMs(String deviceId) => devices[deviceId]?.state?.positionAt(hubNow);

  void _receive(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'welcome':
        _outOfReach?.cancel();
        _clockOffset = (msg['serverTime'] as num).toInt() - DateTime.now().millisecondsSinceEpoch;
        final last = msg['lastPlayback'] as Map<String, dynamic>?;
        lastPlayback = last == null ? null : LastPlayback.fromJson(last);
        devices
          ..clear()
          ..addEntries(
            [for (final d in msg['devices'] as List) Device.fromJson(d as Map<String, dynamic>)]
                .map((d) => MapEntry(d.id, d)),
          );
      case 'device':
        final device = Device.fromJson(msg['device'] as Map<String, dynamic>);
        devices[device.id] = device;
      case 'state':
        final device = devices[msg['deviceId']];
        final report = StampedState.fromJson(msg['state'] as Map<String, dynamic>);

        if (device != null) {
          device.state = device.state?.merge(report) ?? report;
        }
      case 'gone':
        devices.remove(msg['deviceId']);
      case 'lastPlayback':
        lastPlayback = LastPlayback.fromJson(msg['lastPlayback'] as Map<String, dynamic>);
      case 'command':
        unawaited(
          _obey(msg['id'] as String, Command.fromJson(msg['command'] as Map<String, dynamic>), msg['from'] as String),
        );
        return;
      case 'result':
        _waiting.remove(msg['re'])?.complete(Result(ok: msg['ok'] as bool, error: msg['error'] as String?));
        return;
      case 'error':
        // A message of this device's the hub couldn't take, which had no effect: a bug here (SPEC.md, section 2).
        _log.warning('a message refused by $url: ${msg['error']}');
        return;
      default:
        return;
    }

    notifyListeners();
  }

  Future<void> _obey(String id, Command command, String from) async {
    try {
      final handler = onCommand;

      if (handler == null) {
        throw const CommandFailed('unsupported');
      }

      await handler(command, from);
      _send({'type': 'result', 're': id, 'ok': true});
    } catch (e, stackTrace) {
      // With where it came from, but for a command this device turned down.
      _log.warning('${command.action.name} from ${_nameOf(from)} failed', e, e is CommandFailed ? null : stackTrace);
      _send({'type': 'result', 're': id, 'ok': false, 'error': '$e'});
    }
  }

  Future<Result> _ask(Map<String, Object?> msg) {
    if (!_open || status != HubStatus.connected) {
      return Future.value(const Result(ok: false, error: 'closed'));
    }

    final id = 'r${++_seq}';
    final answer = Completer<Result>();
    final channel = _channel;
    _waiting[id] = answer;
    _send({...msg, 'id': id});

    return answer.future.timeout(
      answerTimeout,
      onTimeout: () {
        _log.warning('no answer from $url in ${answerTimeout.inSeconds} s: the connection is dead');
        _waiting.remove(id);
        // The close finishes alone, nothing answering it, and [start] connects again.
        unawaited(channel?.sink.close());

        return const Result(ok: false, error: 'closed');
      },
    );
  }

  /// The hub out of reach for [outOfReachAfter]: so is every other device, which can't be shown nor commanded. Listed
  /// offline, as the hub lists one that closed, they leave the app controlling none of them, with the music of the one
  /// it did kept here (`ConnectController`). Their last states stay; the next welcome lists them anew.
  void _listOffline() {
    devices.updateAll((_, device) => Device(info: device.info, online: false, state: device.state));
    notifyListeners();
  }

  void _send(Map<String, Object?> msg) {
    if (_open) {
      _channel!.sink.add(jsonEncode(msg));
    }
  }

  void _setStatus(HubStatus value) {
    if (status == value) {
      return;
    }

    status = value;
    notifyListeners();
  }
}
