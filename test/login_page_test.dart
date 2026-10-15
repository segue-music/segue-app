import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/app.dart';
import 'package:segue/jellyfin/api.dart';
import 'package:segue/pairing/pairing.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/app/television_screen.dart';
import 'package:segue/ui/app/login_page.dart';
import 'package:segue/ui/widgets/spinner.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Whether the text field labelled [label] has the focus.
bool focused(WidgetTester tester, String label) => tester
    .widget<EditableText>(
      find.descendant(of: find.widgetWithText(TextFormField, label), matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

Future<void> fillIn(WidgetTester tester, {required String server}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Servidor'), server);
  await tester.enterText(find.widgetWithText(TextFormField, 'Usuário'), 'alice');
  await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'sesame');
  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  FlutterSecureStorage.setMockInitialValues({});
  // The system's name for the device, which a TV shows and sends a phone, comes from a platform channel.
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('segue/device'),
      (call) async => call.method == 'deviceName' ? 'laptop' : null,
    ),
  );

  testWidgets('on a TV, the sign-in shows a QR code, with which a phone signed in signs the TV in: the remote types '
      'nothing', (tester) async {
    Session? signedIn;

    final server = MockClient((request) async {
      final query = request.url.queryParameters;
      final ok = query['u'] == 'alice' && query['t'] == 't0k3n' && query['s'] == 's4lt';
      return http.Response(
        jsonEncode({
          'subsonic-response': {'status': ok ? 'ok' : 'failed'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => TelevisionScreen(enabled: true, child: child!),
        home: LoginPage(
          onSignedIn: (session) => signedIn = session,
          client: server,
          pairingAddress: InternetAddress.loopbackIPv4,
        ),
      ),
    );
    // Listening takes the network's time, which the test's clock doesn't move.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Entre pelo celular'), findsOneWidget);
    expect(find.textContaining('toque em Entrar numa TV'), findsOneWidget);

    final code = tester.getRect(find.byType(QrImageView));

    expect(code.right, lessThan(tester.getRect(find.widgetWithText(TextFormField, 'Servidor')).left), reason: 'before');

    final invite = tester.widget<PhoneSignIn>(find.byType(PhoneSignIn)).invite;

    expect(invite.name, 'laptop');
    expect(find.text('laptop · 127.0.0.1'), findsOneWidget, reason: 'which the phone shows before signing it in');

    const credentials = SubsonicCredentials(username: 'alice', token: 't0k3n', salt: 's4lt');
    final phone = Session(
      server: Uri.parse('https://music.example'),
      credentials: credentials,
      deviceId: 'phone',
      deviceName: 'Phone',
    );

    // Over the network for real: the test's binding answers any request of its own HttpClient with a 400. The TV
    // answers in the test's clock, which moves as it pumps.
    Object? device;

    await tester.runAsync(() async {
      unawaited(
        HttpOverrides.runWithHttpOverrides(
          () => offerSignIn(invite, phone, SubsonicApi(phone.server, credentials, client: server)),
          _RealHttp(),
        ).then((name) => device = name, onError: (Object error) => device = error),
      );
    });

    for (var i = 0; i < 200 && device == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    expect(device, 'laptop', reason: 'the TV\'s name');
    await tester.pump();
    expect(signedIn?.server, phone.server);
    expect(signedIn?.credentials, isA<SubsonicToken>().having((c) => c.token, 'token', 't0k3n'));
    expect((await Session.load())?.server, phone.server, reason: 'kept, as a sign-in with the form is');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('elsewhere the sign-in has no QR code: the keyboard types', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) {}, pairingAddress: InternetAddress.loopbackIPv4),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Entre pelo celular'), findsNothing);
  });

  testWidgets('asks for server, user and password before trying', (tester) async {
    var signedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) => signedIn = true),
      ),
    );
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Obrigatório'), findsNWidgets(3));
    expect(signedIn, isFalse);
  });

  testWidgets('the app\'s logo, not its name, is over the form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) {}),
      ),
    );

    final logo = find.bySemanticsLabel('Segue');

    expect(logo, findsOneWidget);
    expect(tester.getSize(logo), const Size.square(96));
    expect(tester.getRect(logo).bottom, lessThan(tester.getRect(find.widgetWithText(TextFormField, 'Servidor')).top));
    expect(find.text('Segue'), findsNothing);
  });

  testWidgets('the keyboard offers "next" from field to field, and from the password, signing in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) {}),
      ),
    );

    for (final (label, action) in [
      ('Servidor', 'TextInputAction.next'),
      ('Usuário', 'TextInputAction.next'),
      ('Senha', 'TextInputAction.done'),
    ]) {
      await tester.tap(find.widgetWithText(TextFormField, label));
      await tester.pump();
      expect(tester.testTextInput.setClientArgs?['inputAction'], action, reason: label);
    }

    await tester.tap(find.widgetWithText(TextFormField, 'Servidor'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(focused(tester, 'Usuário'), isTrue);
  });

  testWidgets('on a phone, a touch off the fields closes the keyboard, and one on another field keeps it open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) {}),
      ),
    );
    await tester.tap(find.widgetWithText(TextFormField, 'Servidor'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextFormField, 'Usuário'));
    await tester.pump();
    expect(focused(tester, 'Usuário'), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.bySemanticsLabel('Segue'));
    await tester.pump();
    expect(focused(tester, 'Usuário'), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('in the app, the arrows down and up (a TV remote\'s) go from field to field', (tester) async {
    // The system in Portuguese, which the app follows.
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const SegueApp(session: null));
    await tester.tap(find.widgetWithText(TextFormField, 'Servidor'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester, 'Usuário'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester, 'Senha'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focused(tester, 'Usuário'), isTrue);
  });

  testWidgets('while it signs in, the button spins and can\'t be pressed again', (tester) async {
    final answer = Completer<http.Response>();
    final client = MockClient((_) => answer.future);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) {}, client: client),
      ),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Servidor'), 'music.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Usuário'), 'alice');
    await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'sesame');
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.descendant(of: find.byType(FilledButton), matching: find.byType(Spinner)), findsOneWidget);
    expect(find.text('Entrar'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    answer.complete(http.Response('<!doctype html>', 200));
    await tester.pumpAndSettle();
    expect(find.byType(Spinner), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('a Jellyfin server is found by its address alone, and signed in to', (tester) async {
    Session? signedIn;

    final client = MockClient((request) async {
      final body = switch (request.url.path) {
        '/System/Info/Public' => {'Id': 'abc', 'Version': '10.10.7'},
        '/Users/AuthenticateByName' => {
          'User': {'Name': 'alice', 'Id': 'u1'},
          'AccessToken': 't1',
        },
        _ => null,
      };

      return body == null ? http.Response('', 404) : http.Response(jsonEncode(body), 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (session) => signedIn = session, client: client),
      ),
    );
    await fillIn(tester, server: 'music.test');
    expect(signedIn?.server, Uri.parse('https://music.test'));
    expect(signedIn?.credentials, isA<JellyfinCredentials>().having((c) => c.token, 'token', 't1'));
  });

  testWidgets('a server that takes API keys alone refuses the password, and the sign-in asks for a key, which signs in '
      'as the server says whose it is', (tester) async {
    Session? signedIn;

    final client = MockClient((request) async {
      final query = request.url.queryParameters;
      final body = switch (request.url.pathSegments.last) {
        'ping.view' when query['apiKey'] == 'k3y' => {'status': 'ok'},
        'ping.view' => {
          'status': 'failed',
          'error': {'code': 42, 'message': 'Provided authentication mechanism not supported'},
        },
        'getOpenSubsonicExtensions.view' => {
          'status': 'ok',
          'openSubsonicExtensions': [
            {
              'name': 'apiKeyAuthentication',
              'versions': [1],
            },
          ],
        },
        'tokenInfo.view' when query['apiKey'] == 'k3y' => {
          'status': 'ok',
          'tokenInfo': {'username': 'alice'},
        },
        _ => {
          'status': 'failed',
          'error': {'code': 44, 'message': 'Invalid API key'},
        },
      };

      return http.Response(jsonEncode({'subsonic-response': body}), 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (session) => signedIn = session, client: client),
      ),
    );
    await fillIn(tester, server: 'music.test');
    expect(find.text('Esse servidor pede uma chave de API em vez da senha.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Senha'), findsNothing, reason: 'the key\'s field in its place');

    await tester.enterText(find.widgetWithText(TextFormField, 'Chave de API'), 'nope');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('O servidor não conhece essa chave de API.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Chave de API'), 'k3y');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(
      signedIn?.credentials,
      isA<SubsonicApiKey>().having((c) => (c.username, c.apiKey), 'credentials', ('alice', 'k3y')),
    );
  });

  testWidgets('the sign-in goes from the username and password to an API key, and back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) {}),
      ),
    );
    await tester.tap(find.text('Entrar com uma chave de API'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Chave de API'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Usuário'), findsNothing);
    expect(find.text('Crie uma no seu servidor de música.'), findsOneWidget);

    await tester.tap(find.text('Entrar com usuário e senha'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Senha'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Chave de API'), findsNothing);
  });

  testWidgets('an address with no media server says so', (tester) async {
    final client = MockClient((_) async => http.Response('<!doctype html>', 200));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) {}, client: client),
      ),
    );
    await fillIn(tester, server: 'example.test');
    expect(find.text('Não achei um servidor Subsonic nem Jellyfin em example.test.'), findsOneWidget);
  });

  testWidgets('an address that is none, its port not a number, says so, rather than sign in', (tester) async {
    var asked = false;
    final client = MockClient((_) async {
      asked = true;
      return http.Response('', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: LoginPage(onSignedIn: (_) {}, client: client),
      ),
    );
    await fillIn(tester, server: 'music.example:abc');
    expect(find.text('O endereço do servidor não é válido.'), findsOneWidget);
    expect(find.byType(Spinner), findsNothing);
    expect(asked, isFalse);

    await tester.enterText(find.widgetWithText(TextFormField, 'Servidor'), 'music.example');
    await tester.tap(find.text('Avançado'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Endereço do hub (opcional)'), 'hub.example:4533x');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('O endereço do hub não é válido.'), findsOneWidget);
    expect(asked, isFalse);
  });

  test('a server typed without a scheme is https', () {
    expect(normalizeServer(' music.test:4533 ').toString(), 'https://music.test:4533');
    expect(normalizeServer('http://127.0.0.1:8480').toString(), 'http://127.0.0.1:8480');
    expect(normalizeServer('[::1'), isNull);
    expect(normalizeServer('https://'), isNull);
  });
}

/// Network requests as the app makes them, out of a test's binding.
class _RealHttp extends HttpOverrides {}
