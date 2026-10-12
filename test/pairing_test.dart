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
    name: 'TV',
    address: InternetAddress.loopbackIPv4,
  );
  addTearDown(pairing!.close);

  return pairing;
}

void main() {
  test('the TV\'s QR code says where it listens, its name, and a key for this once; nothing else is taken for one', () {
    final invite = PairingInvite.random('192.168.1.6:41234', 'Living room');
    final read = PairingInvite.parse('$invite')!;
    expect('$invite', startsWith('segue://pair?v=2&'));
    expect((read.address, read.name, read.id), (invite.address, 'Living room', invite.id));
    expect(read.key, invite.key);
    expect(read.key, hasLength(32));
    expect(read.url, Uri.parse('http://192.168.1.6:41234/pair/${invite.id}'));
    expect(read.host, '192.168.1.6');
    expect(PairingInvite.random('192.168.1.6:41234', 'TV').key, isNot(invite.key), reason: 'another each time');

    String code({String version = '2', String address = '192.168.1.6:41234', String? name = 'TV', String? key}) => Uri(
      scheme: 'segue',
      host: 'pair',
      queryParameters: {'v': version, 'a': address, 'n': ?name, 'i': 'y', 'k': key ?? 'A' * 43},
    ).toString();

    expect(PairingInvite.parse(code()), isNotNull);

    for (final other in [
      'https://music.example',
      'hello',
      'segue://other?v=2&a=192.168.1.6:41234&n=TV&i=y&k=${'A' * 43}',
      code(version: '1'),
      code(key: 'short'),
      code(name: null),
      code(name: ' '),
    ]) {
      expect(PairingInvite.parse(other), isNull, reason: other);
    }
  });

  test('a code has the sign-in go only to the local network: one that sends it elsewhere isn\'t a TV\'s', () {
    for (final address in ['192.168.1.6:41234', '10.0.0.2:5000', '172.16.0.9:1', '172.31.255.1:65535']) {
      expect(PairingInvite.isLocal(address), isTrue, reason: address);
    }

    for (final address in [
      '203.0.113.5:41234',
      '8.8.8.8:80',
      '172.32.0.1:1',
      '127.0.0.1:41234',
      '169.254.1.1:41234',
      'music.example:443',
      '192.168.1.6',
      '192.168.1.6:41234/elsewhere',
      'someone@192.168.1.6:41234',
      '192.168.1.6:41234@music.example',
      '[fd00::1]:41234',
    ]) {
      expect(PairingInvite.isLocal(address), isFalse, reason: address);
    }
  });

  test('a sign-in sealed with the code\'s key opens only with it, and only at the invite\'s id', () async {
    final invite = PairingInvite.random('192.168.1.6:1', 'TV');
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

    final another = PairingInvite.random('192.168.1.6:1', 'TV');
    await expectLater(PairingOffer.open(sealed, another), throwsFormatException);
    final elsewhere = PairingInvite(address: invite.address, name: invite.name, id: another.id, key: invite.key);
    await expectLater(PairingOffer.open(sealed, elsewhere), throwsFormatException, reason: 'another id');
    await expectLater(PairingAnswer.open(sealed, invite), throwsFormatException, reason: 'not an answer');
  });

  test('on Subsonic, the TV signs in with the phone\'s credentials, once the server takes them, and says so', () async {
    final signedIn = <Session>[];
    final pairing = await tv(subsonicServer, signedIn);

    final device = await offerSignIn(pairing.invite.value, phone, SubsonicApi(phone.server, subsonicCredentials));
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
      offerSignIn(pairing.invite.value, session, SubsonicApi(phone.server, wrong)),
      throwsA(isA<PairingRefused>().having((e) => e.error, 'error', PairingError.wrongCredentials)),
    );
    expect(signedIn, isEmpty);
  });

  test('a TV that can\'t reach the server says so', () async {
    final pairing = await tv(MockClient((_) => throw const SocketException('no route')), []);

    await expectLater(
      offerSignIn(pairing.invite.value, phone, SubsonicApi(phone.server, subsonicCredentials)),
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
      pairing.invite.value,
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
        pairing.invite.value,
        session,
        JellyfinApi(phone.server, credentials, deviceId: 'phone', deviceName: 'Phone', client: server.client),
      ),
      throwsA(isA<PairingRefused>().having((e) => e.error, 'error', PairingError.quickConnectOff)),
    );
  });

  test('the TV takes only a sign-in sealed for its code, and only at its address', () async {
    final pairing = await tv(subsonicServer, []);
    final invite = pairing.invite.value;
    final client = http.Client();
    addTearDown(client.close);

    var response = await client.post(Uri.parse('http://${invite.address}/pair/guess'), body: 'hello');
    expect(response.statusCode, HttpStatus.notFound);
    response = await client.get(invite.url);
    expect(response.statusCode, HttpStatus.notFound);
    expect(pairing.invite.value, same(invite), reason: 'still good: nothing came at its address');

    final forAnother = await PairingOffer.of(phone).seal(PairingInvite.random(invite.address, 'TV'));
    response = await client.post(invite.url, body: forAnother);
    expect(response.statusCode, HttpStatus.badRequest);
    expect(
      await PairingAnswer.open(response.bodyBytes, invite),
      isA<PairingRefused>().having((e) => e.error, 'error', PairingError.unreadable),
      reason: 'the answer sealed too',
    );
  });

  test(
    'a code is good once: the TV shows another as a sign-in comes, and the one before signs it in nowhere',
    () async {
      final signedIn = <Session>[];
      final pairing = await tv(subsonicServer, signedIn);
      final first = pairing.invite.value;
      var shown = 0;
      pairing.invite.addListener(() => shown++);
      const wrong = SubsonicCredentials(username: 'alice', token: 'old', salt: 's4lt');
      final session = Session(server: phone.server, credentials: wrong, deviceId: 'phone', deviceName: 'Phone');

      await expectLater(
        offerSignIn(first, session, SubsonicApi(phone.server, wrong)),
        throwsA(isA<PairingRefused>().having((e) => e.error, 'error', PairingError.wrongCredentials)),
      );
      final second = pairing.invite.value;
      expect(shown, 1);
      expect((second.address, second.name), (first.address, first.name));
      expect(second.id, isNot(first.id));
      expect(second.key, isNot(first.key));

      await expectLater(
        offerSignIn(first, phone, SubsonicApi(phone.server, subsonicCredentials)),
        throwsA(isA<PairingRefused>().having((e) => e.error, 'error', PairingError.unreadable)),
        reason: 'spent',
      );
      expect(signedIn, isEmpty);

      expect(await offerSignIn(second, phone, SubsonicApi(phone.server, subsonicCredentials)), 'TV');
      expect(signedIn, hasLength(1));
    },
  );

  test('the phone takes only an answer sealed with the code\'s key: no one else answers its Quick Connect code in the '
      'TV\'s place', () async {
    final server = JellyfinServer();
    final invite = PairingInvite.random('192.168.1.6:41234', 'TV');
    const credentials = JellyfinCredentials(username: 'alice', userId: 'u1', token: 'phone-token');
    final session = Session(server: phone.server, credentials: credentials, deviceId: 'phone', deviceName: 'Phone');
    final api = JellyfinApi(phone.server, credentials, deviceId: 'phone', deviceName: 'Phone', client: server.client);
    const someoneElses = QuickConnectCode('123456', 'TV');

    for (final answer in [
      utf8.encode(jsonEncode(someoneElses.toJson())),
      await someoneElses.seal(PairingInvite.random(invite.address, 'TV')),
    ]) {
      await expectLater(
        offerSignIn(invite, session, api, client: MockClient((_) async => http.Response.bytes(answer, 202))),
        throwsA(isA<PairingRefused>().having((e) => e.error, 'error', PairingError.unreadable)),
      );
      expect(server.authorized, isFalse);
    }

    final sealed = await someoneElses.seal(invite);
    expect(
      await offerSignIn(invite, session, api, client: MockClient((_) async => http.Response.bytes(sealed, 202))),
      'TV',
    );
    expect(server.authorized, isTrue, reason: 'the TV\'s, it authorizes');
  });

  test('the TV names the API of the sign-in it is offered', () {
    expect(PairingOffer.of(phone).api, Api.subsonic);
    const credentials = JellyfinCredentials(username: 'alice', userId: 'u1', token: 'phone-token');
    final jellyfin = Session(server: phone.server, credentials: credentials, deviceId: 'phone', deviceName: 'Phone');
    expect(PairingOffer.of(jellyfin).toJson(), {'server': 'https://music.example', 'api': 'jellyfin'});
  });
}
