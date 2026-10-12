import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
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
// ([JellyfinApi.initiateQuickConnect]). The TV answers what it made of it ([PairingAnswer]). The hub has no part in it:
// the TV knows neither the server nor the hub before.

/// What the TV's QR code says: where it listens on the local network ([address], a host and a port), the path it takes
/// the phone's sign-in at ([id]), and the key the phone seals it with ([key]), both random, for this once.
class PairingInvite {
  const PairingInvite({required this.address, required this.id, required this.key});

  /// An invite at [address], with an id and a key of its own.
  factory PairingInvite.random(String address) {
    final random = Random.secure();

    List<int> bytes(int count) => [for (var i = 0; i < count; i++) random.nextInt(256)];

    return PairingInvite(address: address, id: _base64(bytes(16)), key: Uint8List.fromList(bytes(32)));
  }

  final String address;
  final String id;
  final List<int> key;

  /// The invite in [text] (a QR code's), or null where it is something else.
  static PairingInvite? parse(String text) {
    final uri = Uri.tryParse(text.trim());
    final query = uri?.queryParameters ?? const {};

    if (uri == null || !uri.isScheme(_scheme) || uri.host != 'pair' || query['v'] != '1') {
      return null;
    }

    final (address, id, key) = (query['a'], query['i'], query['k']);

    if (address == null || id == null || key == null) {
      return null;
    }

    try {
      final bytes = base64Url.decode(base64Url.normalize(key));
      return bytes.length == 32 ? PairingInvite(address: address, id: id, key: bytes) : null;
    } on FormatException {
      return null;
    }
  }

  static const _scheme = 'segue';

  /// The text of the QR code.
  @override
  String toString() => Uri(
    scheme: _scheme,
    host: 'pair',
    queryParameters: {'v': '1', 'a': address, 'i': id, 'k': _base64(key)},
  ).toString();

  /// Where the phone sends its sign-in.
  Uri get url => Uri.parse('http://$address/pair/$id');

  static String _base64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}

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

  /// It sealed with [invite]'s key, bound to its id: the nonce, the ciphertext and the tag, one after the other.
  Future<List<int>> seal(PairingInvite invite) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(toJson())),
      secretKey: SecretKey(invite.key),
      aad: utf8.encode(invite.id),
    );

    return box.concatenation();
  }

  /// The offer [sealed] with [invite]'s key ([seal]); a [FormatException] where it isn't one.
  static Future<PairingOffer> open(List<int> sealed, PairingInvite invite) async {
    try {
      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: _cipher.nonceLength,
        macLength: _cipher.macAlgorithm.macLength,
      );
      final json = await _cipher.decrypt(box, secretKey: SecretKey(invite.key), aad: utf8.encode(invite.id));

      return PairingOffer.fromJson(jsonDecode(utf8.decode(json)) as Map<String, Object?>);
    } on Object catch (e) {
      throw FormatException('not a sign-in sealed for this invite: $e');
    }
  }

  static final _cipher = AesGcm.with256bits();
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
  PairingServer._(this._server, this.invite, this._onOffer) {
    _server.listen(_serve, onError: (Object _) {});
  }

  /// Listens at a port of its own, at [address], or else on every network, the invite saying the device's address on
  /// the local network; none where it has none (no network), or can't listen.
  static Future<PairingServer?> start(
    Future<PairingAnswer> Function(PairingOffer offer) onOffer, {
    InternetAddress? address,
  }) async {
    try {
      final host = address ?? await _localAddress();

      if (host == null) {
        return null;
      }

      final server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, 0);

      return PairingServer._(server, PairingInvite.random('${host.address}:${server.port}'), onOffer);
    } on SocketException {
      return null;
    }
  }

  final HttpServer _server;
  final PairingInvite invite;
  final Future<PairingAnswer> Function(PairingOffer offer) _onOffer;
  bool _busy = false;

  /// How big a sign-in can be.
  static const _maxBytes = 16 * 1024;

  /// Stops listening, letting an answer on its way go.
  Future<void> close() => _server.close();

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;

    try {
      if (request.method != 'POST' || request.uri.path != '/pair/${invite.id}') {
        response.statusCode = HttpStatus.notFound;
        return;
      }

      final answer = await _answer(request);
      response
        ..statusCode = answer.statusCode
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(answer.toJson()));
    } on Object {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  Future<PairingAnswer> _answer(HttpRequest request) async {
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

  /// This device's address on the local network: of its IPv4 addresses, a private one (192.168, 10, 172.16 to 31), or
  /// else the first; none without any.
  static Future<InternetAddress?> _localAddress() async {
    final addresses = [
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final address in interface.addresses)
          if (!address.isLoopback && !address.isLinkLocal) address,
    ];

    bool private(InternetAddress address) {
      final [a, b, ...] = address.rawAddress;
      return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b < 32);
    }

    return addresses.where(private).firstOrNull ?? addresses.firstOrNull;
  }
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
    final Object? json;

    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PairingRefused(PairingError.unreadable);
    }

    switch (PairingAnswer.fromJson(json is Map<String, Object?> ? json : const {})) {
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
