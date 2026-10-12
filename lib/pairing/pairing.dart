import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../jellyfin/api.dart';
import '../segue/protocol.dart';
import '../server/server.dart';
import '../session.dart';
import '../subsonic/api.dart';

// Signing a TV in from a phone that is signed in, over the local network, the TV's remote typing nothing. The TV, as
// its sign-in shows, listens for a while ([PairingServer]) and shows a QR code ([PairingInvite]): where it listens, and
// a key for this once. The phone reads it and sends the TV its sign-in ([PairingOffer]), sealed with that key, which
// only what read the code has: a Subsonic server's credentials themselves; for Jellyfin, which keeps a sign-in per
// device, its server alone, the TV then asking it for a Quick Connect code, which the phone authorizes
// ([JellyfinApi.initiateQuickConnect]). The TV answers what it made of it ([PairingAnswer]), sealed with the same key.
// The hub has no part in it: the TV knows neither the server nor the hub before.
//
// What it keeps from: a code made to look like a TV's, which would have the phone send its sign-in to whoever made
// it (the phone sends it only to an address on the local network, and says which TV, by its name and its address,
// which the TV's sign-in shows too); someone on the network answering in the TV's place, with a Quick Connect code of
// their own for the phone to authorize (the answer opens only with the code's key); a code seen, on a photo of the
// screen, signing the TV in later (it is good for one sign-in, the TV showing another after it).

/// What the TV's QR code says: where it listens on the local network ([address], a host and a port), its [name], the
/// path it takes the phone's sign-in at ([id]), and the key the phone seals it with ([key]), both random, for this
/// once.
class PairingInvite {
  const PairingInvite({required this.address, required this.name, required this.id, required this.key});

  /// An invite at [address], from the TV called [name], with an id and a key of its own.
  factory PairingInvite.random(String address, String name) {
    final random = Random.secure();

    List<int> bytes(int count) => [for (var i = 0; i < count; i++) random.nextInt(256)];

    return PairingInvite(address: address, name: name, id: _base64(bytes(16)), key: Uint8List.fromList(bytes(32)));
  }

  final String address;

  /// The TV's name, as its system calls it, which the phone shows before sending its sign-in: what the user knows it
  /// by. It is the code's word, though, which anyone can write: [host] is what the phone holds to.
  final String name;
  final String id;
  final List<int> key;

  /// The invite in [text] (a QR code's), or null where it is something else, or sends the sign-in elsewhere than to
  /// the local network ([isLocal]).
  static PairingInvite? parse(String text) {
    final uri = Uri.tryParse(text.trim());
    final query = uri?.queryParameters ?? const {};

    if (uri == null || !uri.isScheme(_scheme) || uri.host != 'pair' || query['v'] != _version) {
      return null;
    }

    final (address, name, id, key) = (query['a'], query['n'], query['i'], query['k']);

    if (address == null || !isLocal(address) || name == null || name.trim().isEmpty || id == null || key == null) {
      return null;
    }

    try {
      final bytes = base64Url.decode(base64Url.normalize(key));
      return bytes.length == 32 ? PairingInvite(address: address, name: name.trim(), id: id, key: bytes) : null;
    } on FormatException {
      return null;
    }
  }

  /// Whether [address] is a host and a port on the local network, as a TV writes it: a private IPv4 address (10,
  /// 172.16 to 31, 192.168) and its port, nothing more. A code that has the sign-in go anywhere else, as to the
  /// internet, isn't a TV's.
  static bool isLocal(String address) {
    final uri = Uri.tryParse('http://$address');
    final host = InternetAddress.tryParse(uri?.host ?? '');

    return host != null && _isPrivate(host) && address == '${host.address}:${uri!.port}';
  }

  static const _scheme = 'segue';

  /// The version of the code and of what goes with it: a phone takes only a TV's of its own.
  static const _version = '2';

  /// The text of the QR code.
  @override
  String toString() => Uri(
    scheme: _scheme,
    host: 'pair',
    queryParameters: {'v': _version, 'a': address, 'n': name, 'i': id, 'k': _base64(key)},
  ).toString();

  /// The TV's address on the network, without the port.
  String get host => url.host;

  /// Where the phone sends its sign-in.
  Uri get url => Uri.parse('http://$address/pair/$id');

  static String _base64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}

/// Whether [address] is a private IPv4 address, of a local network: 10, 172.16 to 31, 192.168.
bool _isPrivate(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) {
    return false;
  }

  final [a, b, ...] = address.rawAddress;

  return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b < 32);
}

/// What goes one way or the other, sealed with [invite]'s key: its nonce, its ciphertext and its tag, one after the
/// other. Bound to the invite's id and to the way it goes ([purpose]), so that a sign-in passes neither for another
/// invite's nor for an answer.
Future<List<int>> _seal(Object? json, PairingInvite invite, String purpose) async {
  final box = await _cipher.encrypt(
    utf8.encode(jsonEncode(json)),
    secretKey: SecretKey(invite.key),
    aad: utf8.encode('$purpose ${invite.id}'),
  );

  return box.concatenation();
}

/// What [sealed] says, sealed with [invite]'s key for [purpose] ([_seal]); a [FormatException] where it isn't.
Future<Object?> _open(List<int> sealed, PairingInvite invite, String purpose) async {
  try {
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
    );
    final json = await _cipher.decrypt(
      box,
      secretKey: SecretKey(invite.key),
      aad: utf8.encode('$purpose ${invite.id}'),
    );

    return jsonDecode(utf8.decode(json));
  } on Object catch (e) {
    throw FormatException('not sealed for this invite: $e');
  }
}

final _cipher = AesGcm.with256bits();

/// The sign-in a phone offers the TV: its media server and hub, and on Subsonic its [credentials]; on Jellyfin none,
/// the TV signing in by Quick Connect.
class PairingOffer {
  const PairingOffer({required this.server, required this.api, this.hub, this.credentials});

  /// [session]'s sign-in.
  factory PairingOffer.of(Session session) => PairingOffer(
    server: session.server,
    hub: session.hub,
    api: session.credentials is SubsonicCredentials ? Api.subsonic : Api.jellyfin,
    credentials: switch (session.credentials) {
      final SubsonicCredentials credentials => credentials,
      _ => null,
    },
  );

  factory PairingOffer.fromJson(Map<String, Object?> json) {
    final api = Api.values.byName(json['api']! as String);
    final hub = json['hub'] as String?;

    return PairingOffer(
      server: Uri.parse(json['server']! as String),
      hub: hub == null ? null : Uri.parse(hub),
      api: api,
      credentials: api == Api.subsonic
          ? SubsonicCredentials(
              username: json['username']! as String,
              token: json['token']! as String,
              salt: json['salt']! as String,
            )
          : null,
    );
  }

  final Uri server;
  final Uri? hub;
  final Api api;
  final SubsonicCredentials? credentials;

  Map<String, Object?> toJson() => {
    'server': '$server',
    'hub': ?hub?.toString(),
    'api': api.name,
    if (credentials case final credentials?) ...{
      'username': credentials.username,
      'token': credentials.token,
      'salt': credentials.salt,
    },
  };

  /// It sealed with [invite]'s key.
  Future<List<int>> seal(PairingInvite invite) => _seal(toJson(), invite, 'offer');

  /// The offer [sealed] with [invite]'s key ([seal]); a [FormatException] where it isn't one.
  static Future<PairingOffer> open(List<int> sealed, PairingInvite invite) async {
    final json = await _open(sealed, invite, 'offer');

    try {
      return PairingOffer.fromJson(json! as Map<String, Object?>);
    } on Object catch (e) {
      throw FormatException('not a sign-in: $e');
    }
  }
}

/// Why a TV took no sign-in.
enum PairingError {
  /// What came wasn't a sign-in sealed with its key, or a sign-in it knows.
  unreadable,

  /// The media server refused the credentials.
  wrongCredentials,

  /// The TV can't reach the media server at the address the phone uses.
  unreachable,

  /// The Jellyfin server has Quick Connect off, or none (Navidrome's).
  quickConnectOff,

  /// It is signing in already, with another sign-in.
  busy,
}

/// What the TV made of a sign-in, which it tells the phone.
sealed class PairingAnswer {
  const PairingAnswer();

  factory PairingAnswer.fromJson(Map<String, Object?> json) => switch (json) {
    {'signedIn': final String device} => SignedIn(device),
    {'quickConnect': final String code, 'device': final String device} => QuickConnectCode(code, device),
    {'error': final String error} => PairingRefused(PairingError.values.asNameMap()[error] ?? PairingError.unreadable),
    _ => const PairingRefused(PairingError.unreadable),
  };

  Map<String, Object?> toJson();

  int get statusCode;

  /// It sealed with [invite]'s key, as the sign-in it answers was.
  Future<List<int>> seal(PairingInvite invite) => _seal(toJson(), invite, 'answer');

  /// The answer [sealed] with [invite]'s key ([seal]); a [FormatException] where it isn't one: anyone on the network
  /// could have answered in the TV's place.
  static Future<PairingAnswer> open(List<int> sealed, PairingInvite invite) async {
    final json = await _open(sealed, invite, 'answer');

    return PairingAnswer.fromJson(json is Map<String, Object?> ? json : const {});
  }
}

/// Signed in, as [device].
class SignedIn extends PairingAnswer {
  const SignedIn(this.device);

  final String device;

  @override
  Map<String, Object?> toJson() => {'signedIn': device};

  @override
  int get statusCode => HttpStatus.ok;
}

/// Signing in by Quick Connect, as [device]: the phone authorizes [code].
class QuickConnectCode extends PairingAnswer {
  const QuickConnectCode(this.code, this.device);

  final String code;
  final String device;

  @override
  Map<String, Object?> toJson() => {'quickConnect': code, 'device': device};

  @override
  int get statusCode => HttpStatus.accepted;
}

class PairingRefused extends PairingAnswer implements Exception {
  const PairingRefused(this.error);

  final PairingError error;

  @override
  Map<String, Object?> toJson() => {'error': error.name};

  @override
  int get statusCode => switch (error) {
    PairingError.unreadable => HttpStatus.badRequest,
    PairingError.wrongCredentials => HttpStatus.forbidden,
    PairingError.unreachable || PairingError.quickConnectOff => HttpStatus.badGateway,
    PairingError.busy => HttpStatus.conflict,
  };

  @override
  String toString() => 'pairing refused: ${error.name}';
}

/// On the TV, for as long as its sign-in shows: listens on the local network for a phone's sign-in, at its [invite]'s
/// address, and gives what comes to [onOffer], one at a time, which answers it.
class PairingServer {
  PairingServer._(this._server, PairingInvite invite, this._onOffer) : _invite = ValueNotifier(invite) {
    _server.listen(_serve, onError: (Object _) {});
  }

  /// Listens at a port of its own, at [address], or else on every network, the invite saying the device's address on
  /// the local network and its [name]; none where it has none (no network, or none a phone sends a sign-in to), or
  /// can't listen.
  static Future<PairingServer?> start(
    Future<PairingAnswer> Function(PairingOffer offer) onOffer, {
    required String name,
    InternetAddress? address,
  }) async {
    try {
      final host = address ?? await _localAddress();

      if (host == null) {
        return null;
      }

      final server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, 0);

      return PairingServer._(server, PairingInvite.random('${host.address}:${server.port}', name), onOffer);
    } on SocketException {
      return null;
    }
  }

  final HttpServer _server;
  final ValueNotifier<PairingInvite> _invite;
  final Future<PairingAnswer> Function(PairingOffer offer) _onOffer;
  bool _busy = false;

  /// What the QR code says: another as each sign-in comes, whatever comes of it, so that a code seen (on a photo of
  /// the screen) signs the TV in nowhere afterwards.
  ValueListenable<PairingInvite> get invite => _invite;

  /// How big a sign-in can be.
  static const _maxBytes = 16 * 1024;

  /// Stops listening, letting an answer on its way go.
  Future<void> close() => _server.close();

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final invite = _invite.value;

    try {
      if (request.method != 'POST' || request.uri.path != '/pair/${invite.id}') {
        response.statusCode = HttpStatus.notFound;
        return;
      }

      // Spent: the next sign-in takes the next code.
      _invite.value = PairingInvite.random(invite.address, invite.name);
      final answer = await _answer(request, invite);
      response
        ..statusCode = answer.statusCode
        ..headers.contentType = ContentType.binary
        ..add(await answer.seal(invite));
    } on Object {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  Future<PairingAnswer> _answer(HttpRequest request, PairingInvite invite) async {
    final body = BytesBuilder(copy: false);

    await for (final chunk in request) {
      body.add(chunk);

      if (body.length > _maxBytes) {
        return const PairingRefused(PairingError.unreadable);
      }
    }

    final PairingOffer offer;

    try {
      offer = await PairingOffer.open(body.takeBytes(), invite);
    } on FormatException {
      return const PairingRefused(PairingError.unreadable);
    }

    if (_busy) {
      return const PairingRefused(PairingError.busy);
    }

    _busy = true;

    try {
      return await _onOffer(offer);
    } finally {
      _busy = false;
    }
  }

  /// This device's address on the local network: a private IPv4 one, the only kind a phone sends a sign-in to
  /// ([PairingInvite.isLocal]); none without it.
  static Future<InternetAddress?> _localAddress() async => [
    for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final address in interface.addresses)
        if (_isPrivate(address)) address,
  ].firstOrNull;
}

/// On the TV, what it does with a phone's [offer]: signs in with it, on Subsonic at once, answering [SignedIn], and
/// gives [signedIn] the session; on Jellyfin, asks the server for a Quick Connect code, answering it
/// ([QuickConnectCode]) for the phone to authorize, and then asks the server every [poll] whether it has, for
/// [patience] at most, before signing in and giving [signedIn] the session.
Future<PairingAnswer> takeOffer(
  PairingOffer offer, {
  required String deviceId,
  required String deviceName,
  required FutureOr<void> Function(Session session) signedIn,
  http.Client? client,
  Duration poll = const Duration(seconds: 2),
  Duration patience = const Duration(minutes: 3),
}) async {
  Session sessionOf(Credentials credentials) => Session(
    server: offer.server,
    credentials: credentials,
    deviceId: deviceId,
    deviceName: deviceName,
    hub: offer.hub,
  );

  try {
    if (offer.credentials case final credentials?) {
      final api = SubsonicApi(offer.server, credentials, client: client);

      try {
        await api.ping();
      } finally {
        if (client == null) {
          api.close();
        }
      }

      await signedIn(sessionOf(credentials));
      return SignedIn(deviceName);
    }

    final (:code, :secret) = await JellyfinApi.initiateQuickConnect(
      offer.server,
      deviceId: deviceId,
      deviceName: deviceName,
      client: client,
    );
    unawaited(
      _awaitQuickConnect(
        offer.server,
        secret,
        deviceId: deviceId,
        deviceName: deviceName,
        client: client,
        poll: poll,
        patience: patience,
      ).then((credentials) => credentials == null ? null : signedIn(sessionOf(credentials)), onError: (Object _) {}),
    );

    return QuickConnectCode(code, deviceName);
  } on ServerError catch (e) {
    return PairingRefused(switch ((e.isAuth, offer.api)) {
      (true, Api.subsonic) => PairingError.wrongCredentials,
      (true, Api.jellyfin) => PairingError.quickConnectOff,
      // Navidrome's Jellyfin API has no Quick Connect.
      (false, Api.jellyfin) => PairingError.quickConnectOff,
      (false, Api.subsonic) => PairingError.unreachable,
    });
  } on Exception {
    return const PairingRefused(PairingError.unreachable);
  }
}

/// The credentials Jellyfin gives for the Quick Connect of [secret], once the phone has authorized it; none where it
/// hasn't within [patience].
Future<JellyfinCredentials?> _awaitQuickConnect(
  Uri server,
  String secret, {
  required String deviceId,
  required String deviceName,
  required http.Client? client,
  required Duration poll,
  required Duration patience,
}) async {
  final until = DateTime.now().add(patience);

  while (DateTime.now().isBefore(until)) {
    await Future<void>.delayed(poll);

    final authorized = await JellyfinApi.quickConnectAuthorized(
      server,
      secret,
      deviceId: deviceId,
      deviceName: deviceName,
      client: client,
    );

    if (authorized) {
      final api = await JellyfinApi.signInWithQuickConnect(
        server,
        secret,
        deviceId: deviceId,
        deviceName: deviceName,
        client: client,
      );
      final credentials = api.credentials;

      if (client == null) {
        api.close();
      }

      return credentials;
    }
  }

  return null;
}

/// On the phone: offers the TV of [invite] the sign-in of [session], whose media server is [api]; on Jellyfin,
/// authorizing the Quick Connect code the TV answers with. The TV's name, signed in or about to be; [PairingRefused]
/// where it took none, or the network's error where it can't be reached.
Future<String> offerSignIn(PairingInvite invite, Session session, MediaServer api, {http.Client? client}) async {
  final httpClient = client ?? http.Client();

  try {
    final response = await httpClient
        .post(
          invite.url,
          headers: {'Content-Type': 'application/octet-stream'},
          body: await PairingOffer.of(session).seal(invite),
        )
        .timeout(const Duration(seconds: 30));
    final PairingAnswer answer;

    try {
      answer = await PairingAnswer.open(response.bodyBytes, invite);
    } on FormatException {
      // Not the TV's answer: the code was spent (a 404), or someone else answered in its place.
      throw const PairingRefused(PairingError.unreadable);
    }

    switch (answer) {
      case SignedIn(:final device):
        return device;
      case QuickConnectCode(:final code, :final device):
        if (api is! JellyfinApi) {
          throw const PairingRefused(PairingError.unreadable);
        }

        await api.authorizeQuickConnect(code);
        return device;
      case final PairingRefused refused:
        throw refused;
    }
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}
