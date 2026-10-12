import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/pairing/pairing.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/settings/sign_in_tv_page.dart';

import 'home_view_test.dart' show openSettings, pumpHome, settingsItem;

void main() {
  testWidgets('on a phone, the settings have a way to sign a TV in, by the sign-in, before signing out', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 800));
    await openSettings(tester);
    await tester.scrollUntilVisible(settingsItem('Sair'), 200, scrollable: find.byType(Scrollable).last);
    final item = settingsItem('Entrar numa TV');
    expect(item, findsOneWidget);
    expect(find.descendant(of: item, matching: find.text('Com este login, lendo o código que a TV mostra')), findsOne);
    expect(tester.getRect(item).bottom, lessThanOrEqualTo(tester.getRect(settingsItem('Sair')).top));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a TV signs in that way itself, and a computer has no camera to read the code with: neither has it', (
    tester,
  ) async {
    await pumpHome(tester, const Size(960, 540), television: true);
    await openSettings(tester);
    expect(settingsItem('Entrar numa TV'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpHome(tester, const Size(1280, 800));
    await openSettings(tester);
    expect(settingsItem('Entrar numa TV'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('before sending a TV the sign-in, the phone says which TV, by its name and its address, which the TV '
      'shows under its code', (tester) async {
    final session = Session(
      server: Uri.parse('https://music.example'),
      credentials: const SubsonicCredentials(username: 'alice', token: 't0k3n', salt: 's4lt'),
      deviceId: 'phone',
      deviceName: 'Phone',
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        home: ConfirmSignInTv(PairingInvite.random('192.168.1.6:41234', 'Living room'), session),
      ),
    );
    expect(find.text('Entrar na TV?'), findsOneWidget);
    expect(find.text('Living room (192.168.1.6) vai entrar como alice em music.example.'), findsOneWidget);
  });
}
