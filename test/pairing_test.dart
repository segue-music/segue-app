import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/jellyfin/api.dart';
import 'package:segue/pairing/pairing.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';

const subsonicCredentials = SubsonicCredentials(username: 'alice', token: 't0k3n', salt: 's4lt');

final phone = Session(
  server: Uri.parse('https://music.example'),
  credentials: subsonicCredentials,
  deviceId: 'phone',
  deviceName: 'Phone',
  hub: Uri.parse('wss://hub.example/connect/v1/ws'),
);

http.Response subsonic(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A Subsonic server that takes [subsonicCredentials] alone.
final subsonicServer = MockClient((request) async {
  final query = request.url.queryParameters;

  if (query['u'] == 'alice' && query['t'] == 't0k3n' && query['s'] == 's4lt') {
    return subsonic({});
  }

  return http.Response(
    jsonEncode({
      'subsonic-response': {
        'status': 'failed',
        'error': {'code': 40, 'message': 'Wrong username or password'},
      },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
});

/// A Jellyfin server with Quick Connect (or, without [quickConnect], with it off): its code is 123456, which the phone
/// authorizes with its own token; [authorized] says whether it has. The TV signed in by it gets a token of its own.
class JellyfinServer {
  JellyfinServer({this.quickConnect = true});

  final bool quickConnect;
  bool authorized = false;

  late final client = MockClient((request) async {
    final path = request.url.path;

    if (path.endsWith('QuickConnect/Initiate')) {
      return quickConnect
          ? http.Response(jsonEncode({'Code': '123456', 'Secret': 'qc-secret', 'Authenticated': false}), 200)
          : http.Response('Quick connect is not enabled on this server', 401);
    }

    if (path.endsWith('QuickConnect/Authorize')) {
      final ok =
          request.headers['Authorization']!.contains('Token="phone-token"') &&
          request.url.queryParameters['code'] == '123456' &&
          request.url.queryParameters['userId'] == 'u1';
      authorized |= ok;
      return http.Response(ok ? 'true' : '', ok ? 200 : 403);
    }

    if (path.endsWith('QuickConnect/Connect') && request.url.queryParameters['secret'] == 'qc-secret') {
      return http.Response(jsonEncode({'Authenticated': authorized}), 200);
    }

    if (path.endsWith('Users/AuthenticateWithQuickConnect') && authorized) {
      expect(jsonDecode(request.body), {'Secret': 'qc-secret'});
      return http.Response(
        jsonEncode({
          'User': {'Name': 'alice', 'Id': 'u1'},
          'AccessToken': 'tv-token',
        }),
        200,
      );
    }

    return http.Response('', 404);
  });
}

/// The TV listening for a phone's sign-in on the loopback, taking it as its sign-in page does, with [server] for its
/// media server; [signedIn] gets its sessions.
Future<PairingServer> tv(http.Client server, List<Session> signedIn) async {
  final pairing = await PairingServer.start(
    (offer) => takeOffer(
      offer,
      deviceId: 'tv',
      deviceName: 'TV',
      client: server,
      poll: const Duration(milliseconds: 10),
      signedIn: signedIn.add,
    ),
    address: InternetAddress.loopbackIPv4,
  );
  addTearDown(pairing!.close);

  return pairing;
}

void main() {
  test('the TV\'s QR code says where it listens, and a key for this once; nothing else is taken for one', () {
    final invite = PairingInvite.random('192.168.1.6:41234');
    final read = PairingInvite.parse('$invite')!;
    expect('$invite', startsWith('segue://pair?v=1&'));
    expect((read.address, read.id), (invite.address, invite.id));
    expect(read.key, invite.key);
    expect(read.key, hasLength(32));
    expect(read.url, Uri.parse('http://192.168.1.6:41234/pair/${invite.id}'));
    expect(PairingInvite.random('192.168.1.6:41234').key, isNot(invite.key), reason: 'another each time');

    for (final other in [
      'https://music.example',
      'segue://pair?v=2&a=x&i=y&k=${'A' * 43}',
      'segue://pair?v=1&a=x&i=y&k=short',
      'segue://other?v=1&a=x&i=y&k=${'A' * 43}',
      'hello',
    ]) {
      expect(PairingInvite.parse(other), isNull, reason: other);
    }
  });

  test('a sign-in sealed with the code\'s key opens only with it, and only at the invite\'s id', () async {
    final invite = PairingInvite.random('tv:1');
    final sealed = await PairingOffer.of(phone).seal(invite);
    expect(utf8.decode(sealed, allowMalformed: true), isNot(contains('t0k3n')), reason: 'sealed');

    final offer = await PairingOffer.open(sealed, invite);
    expect(offer.toJson(), {
      'server': 'https://music.example',
      'hub': 'wss://hub.example/connect/v1/ws',
      'api': 'subsonic',
      'username': 'alice',
      'token': 't0k3n',
      'salt': 's4lt',
    });

    final another = PairingInvite.random('tv:1');
    await expectLater(PairingOffer.open(sealed, another), throwsFormatException);
    final elsewhere = PairingInvite(address: invite.address, id: another.id, key: invite.key);
    await expectLater(PairingOffer.open(sealed, elsewhere), throwsFormatException, reason: 'another id');
  });

  test('on Subsonic, the TV signs in with the phone\'s credentials, once the server takes them, and says so', () async {
    final signedIn = <Session>[];
    final pairing = await tv(subsonicServer, signedIn);

    final device = await offerSignIn(pairing.invite, phone, SubsonicApi(phone.server, subsonicCredentials));
    expect(device, 'TV');
    final session = signedIn.single;
    expect((session.server, session.hub, session.deviceId), (phone.server, phone.hub, 'tv'));
    expect(
      session.credentials,
      isA<SubsonicCredentials>().having((c) => (c.username, c.token, c.salt), 'credentials', (
        'alice',
        't0k3n',
        's4lt',
      )),
    );
  });

  test('credentials the server refuses sign the TV in nowhere, and the phone hears why', () async {
    final signedIn = <Session>[];
    final pairing = await tv(subsonicServer, signedIn);
    const wrong = SubsonicCredentials(username: 'alice', token: 'old', salt: 's4lt');
    final session = Session(server: phone.server, credentials: wrong, deviceId: 'phone', deviceName: 'Phone');

    await expectLater(
      offerSignIn(pairing.invite, session, SubsonicApi(phone.server, wrong)),
      throwsA(isA<PairingRefused>().having((e) => e.error, 'error', PairingError.wrongCredentials)),
    );
    expect(signedIn, isEmpty);
  });

  test('a TV that can\'t reach the server says so', () async {
    final pairing = await tv(MockClient((_) => throw const SocketException('no route')), []);

    await expectLater(
      offerSignIn(pairing.invite, phone, SubsonicApi(phone.server, subsonicCredentials)),
      throwsA(isA<PairingRefused>().having((e) => e.error, 'error', PairingError.unreachable)),
    );
  });

  test('on Jellyfin, the TV signs in by Quick Connect, which the phone authorizes: a sign-in of its own', () async {
    final server = JellyfinServer();
    final signedIn = <Session>[];
    final pairing = await tv(server.client, signedIn);
    const credentials = JellyfinCredentials(username: 'alice', userId: 'u1', token: 'phone-token');
    final session = Session(server: phone.server, credentials: credentials, deviceId: 'phone', deviceName: 'Phone');

    final device = await offerSignIn(
      pairing.invite,
      session,
      JellyfinApi(phone.server, credentials, deviceId: 'phone', deviceName: 'Phone', client: server.client),
    );
    expect(device, 'TV');
    expect(server.authorized, isTrue);

    for (var i = 0; i < 100 && signedIn.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      signedIn.single.credentials,
      isA<JellyfinCredentials>().having((c) => (c.userId, c.token), 'credentials', ('u1', 'tv-token')),
    );
  });

  test('a Jellyfin server with Quick Connect off signs the TV in nowhere, which the phone hears', () async {
    final server = JellyfinServer(quickConnect: false);
    final pairing = await tv(server.client, []);
    const credentials = JellyfinCredentials(username: 'alice', userId: 'u1', token: 'phone-token');
    final session = Session(server: phone.server, credentials: credentials, deviceId: 'phone', deviceName: 'Phone');

    await expectLater(
      offerSignIn(
        pairing.invite,
        session,
        JellyfinApi(phone.server, credentials, deviceId: 'phone', deviceName: 'Phone', client: server.client),
      ),
      throwsA(isA<PairingRefused>().having((e) => e.error, 'error', PairingError.quickConnectOff)),
    );
  });

  test('the TV takes only a sign-in sealed for its code, and only at its address', () async {
    final pairing = await tv(subsonicServer, []);
    final client = http.Client();
    addTearDown(client.close);

    final forAnother = await PairingOffer.of(phone).seal(PairingInvite.random(pairing.invite.address));
    var response = await client.post(pairing.invite.url, body: forAnother);
    expect(response.statusCode, HttpStatus.badRequest);
    expect(jsonDecode(response.body), {'error': 'unreadable'});

    response = await client.post(Uri.parse('http://${pairing.invite.address}/pair/guess'), body: forAnother);
    expect(response.statusCode, HttpStatus.notFound);
    response = await client.get(pairing.invite.url);
    expect(response.statusCode, HttpStatus.notFound);
  });

  test('the TV names the API of the sign-in it is offered', () {
    expect(PairingOffer.of(phone).api, Api.subsonic);
    const credentials = JellyfinCredentials(username: 'alice', userId: 'u1', token: 'phone-token');
    final jellyfin = Session(server: phone.server, credentials: credentials, deviceId: 'phone', deviceName: 'Phone');
    expect(PairingOffer.of(jellyfin).toJson(), {'server': 'https://music.example', 'api': 'jellyfin'});
  });
}
