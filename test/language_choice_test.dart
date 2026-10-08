import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/app.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/language_choice.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/login_page.dart';
import 'package:segue/ui/themed_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

/// The home page, over a server with nothing in it, in the language [choice] picks or else the system's, as in the
/// app.
Future<void> pumpHome(WidgetTester tester, LanguageChoice choice) async {
  const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
  final api = SubsonicApi(
    Uri.parse('https://music.test'),
    credentials,
    client: MockClient((_) async => http.Response('', 404)),
  );
  final player = PlayerController(FakeEngine(), api);
  final services = Services(
    Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
    api,
    player,
    ConnectController(player: player),
  );
  await tester.pumpWidget(
    ListenableBuilder(
      listenable: choice,
      builder: (context, _) => MaterialApp(
        locale: choice.value,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: LanguageChoice.resolve,
        builder: (context, child) => ServicesScope(services: services, child: child!),
        home: HomePage(onSignOut: () {}, languageChoice: choice),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The language menu's item that says [name].
Finder item(String name) =>
    find.ancestor(of: find.text(name), matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem));

/// What has the focus: the language menu's button, or by what it says, a text field, the sign-in's advanced settings or
/// its button.
String? focused() {
  final context = FocusManager.instance.primaryFocus?.context;

  if (context?.findAncestorWidgetOfExactType<PopupMenuButton<String>>() != null) {
    return 'language';
  }

  return switch ((
    context?.findAncestorWidgetOfExactType<TextField>(),
    context?.findAncestorWidgetOfExactType<ExpansionTile>(),
    context?.findAncestorWidgetOfExactType<FilledButton>(),
  )) {
    (TextField(:final decoration?), _, _) => decoration.labelText,
    (_, ExpansionTile(title: Text(:final data)), _) => data,
    (_, _, FilledButton(child: Text(:final data))) => data,
    _ => null,
  };
}

/// Whether [name]'s item has the check of the language showing.
bool checked(WidgetTester tester, String name) =>
    find.descendant(of: item(name), matching: find.byType(ThemedIcon)).evaluate().isNotEmpty;

void main() {
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  setUp(() async {
    await SharedPreferencesAsync().clear();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('the language follows the system\'s until a pick, which the next launch, and a sign-out, keep', () async {
    expect((await LanguageChoice.load()).value, isNull);

    await LanguageChoice().pick(const Locale('es'));
    await Session.clear();
    expect((await LanguageChoice.load()).value, const Locale('es'));

    await LanguageChoice().pick(null);
    expect((await LanguageChoice.load()).value, isNull, reason: 'the system\'s again');
  });

  test('a language saved that the app doesn\'t have is the system\'s', () async {
    await SharedPreferencesAsync().setString('language', 'fr');
    expect((await LanguageChoice.load()).value, isNull);
  });

  test('of the system\'s languages, the app shows the first it has, and English when it has none', () {
    Locale shown(List<Locale> system) => LanguageChoice.resolve(system, AppLocalizations.supportedLocales);

    expect(shown(const [Locale('pt', 'BR')]), const Locale('pt'));
    expect(shown(const [Locale('es', 'MX')]), const Locale('es'));
    expect(shown(const [Locale('en', 'GB')]), const Locale('en'));
    expect(shown(const [Locale('fr', 'FR'), Locale('es', 'ES')]), const Locale('es'));
    expect(shown(const [Locale('fr', 'FR'), Locale('de', 'DE')]), const Locale('en'));
    expect(shown(const []), const Locale('en'));
  });

  testWidgets(
    'the app shows the system\'s language, or the one picked as soon as it is picked; Material\'s words too',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('es', 'ES')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final choice = LanguageChoice();
      addTearDown(choice.dispose);
      String materialBack() => MaterialLocalizations.of(tester.element(find.byType(LoginPage))).backButtonTooltip;

      await tester.pumpWidget(SegueApp(session: null, languageChoice: choice));
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(materialBack(), 'Atrás');

      choice.value = const Locale('pt');
      await tester.pumpAndSettle();
      expect(find.text('Entrar'), findsOneWidget);
      expect(materialBack(), 'Voltar');

      tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
      choice.value = null;
      await tester.pumpAndSettle();
      expect(
        find.text('Sign in'),
        findsOneWidget,
        reason: 'English, where the app has none of the system\'s languages',
      );
      expect(materialBack(), 'Back');
    },
  );

  testWidgets('the top bar\'s menu picks the language: the system\'s, or one the app has, by its own name', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final choice = LanguageChoice();
    addTearDown(choice.dispose);
    await pumpHome(tester, choice);
    expect(find.byTooltip('Álbuns'), findsOneWidget, reason: 'the system\'s');

    await tester.tap(find.byTooltip('Idioma'));
    await tester.pumpAndSettle();
    final names = ['Idioma do sistema', 'English', 'Español', 'Português'];
    final tops = [for (final name in names) tester.getTopLeft(item(name)).dy];
    expect([...tops]..sort(), tops, reason: 'in this order, top to bottom');
    expect([for (final name in names) checked(tester, name)], [true, false, false, false]);

    await tester.tap(item('English'));
    await tester.pumpAndSettle();
    expect(choice.value, const Locale('en'));
    expect(find.byTooltip('Albums'), findsOneWidget);

    await tester.tap(find.byTooltip('Language'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final name in ['System language', 'English', 'Español', 'Português']) checked(tester, name),
      ],
      [false, true, false, false],
    );

    await tester.tap(item('System language'));
    await tester.pumpAndSettle();
    expect(choice.value, isNull);
    expect(find.byTooltip('Álbuns'), findsOneWidget);
  });

  testWidgets('on a phone, the settings pick the language, the system\'s again too', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final choice = LanguageChoice();
    addTearDown(choice.dispose);
    await pumpHome(tester, choice);
    expect(find.byTooltip('Idioma'), findsNothing, reason: 'no language menu of its own');
    Finder option(String name) => find.widgetWithText(ListTile, name);
    bool picked(String name) =>
        find.descendant(of: option(name), matching: find.byType(ThemedIcon)).evaluate().isNotEmpty;

    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    await tester.tap(option('English'));
    await tester.pumpAndSettle();
    expect(choice.value, const Locale('en'));
    expect(find.text('Settings'), findsOneWidget, reason: 'the page, in English at once');
    expect(find.text('Albums'), findsOneWidget, reason: 'the sections\' bar, in English');
    expect(
      [
        for (final name in ['System language', 'English', 'Español', 'Português']) picked(name),
      ],
      [false, true, false, false],
    );

    await tester.tap(option('System language'));
    await tester.pumpAndSettle();
    expect(choice.value, isNull);
    expect(find.text('Álbuns'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);
  });

  testWidgets('the sign-in has the menu too, in its corner, which shows the page in the language picked', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final choice = LanguageChoice();
    addTearDown(choice.dispose);
    await tester.pumpWidget(SegueApp(session: null, languageChoice: choice));
    final corner = tester.getRect(find.byTooltip('Idioma'));
    expect(corner.right, greaterThan(tester.view.physicalSize.width / tester.view.devicePixelRatio - 64));
    expect(corner.top, lessThan(64));

    await tester.tap(find.byTooltip('Idioma'));
    await tester.pumpAndSettle();
    await tester.tap(item('Español'));
    await tester.pumpAndSettle();
    expect(choice.value, const Locale('es'));
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Contraseña'), findsOneWidget);
  });

  testWidgets('on the sign-in, Tab goes through the form before the menu, and up from the first field goes to it', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final choice = LanguageChoice();
    addTearDown(choice.dispose);
    await tester.pumpWidget(SegueApp(session: null, languageChoice: choice));
    final order = <String?>[];

    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(focused());
    }

    expect(order, ['Servidor', 'Usuário', 'Senha', 'Avançado', 'Entrar', 'language']);

    await tester.tap(find.widgetWithText(TextFormField, 'Servidor'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focused(), 'language');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(), 'Servidor');
  });
}
