import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/downloads/server_with_downloads.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/server/server.dart';
import 'package:segue/ui/widgets/errors.dart';

void main() {
  test('the hub\'s and the players\' errors say so in the user\'s language', () {
    final strings = lookupAppLocalizations(const Locale('pt'));

    expect(describeError(strings, 'badMessage'), 'O hub não entendeu o pedido.');
    expect(describeError(strings, 'offline'), strings.errorOffline);
    expect(describeError(strings, 'something new'), 'something new', reason: 'as it came');
  });

  test('an error the app words itself says so in the user\'s language; the server\'s, in its own words', () {
    final strings = lookupAppLocalizations(const Locale('pt'));

    expect(describeFailure(strings, ServerWithDownloads.unreachable), 'sem conexão com o servidor de música');
    expect(
      describeFailure(strings, const ServerError('refused', isAuth: true, reason: ServerErrorReason.signInRefused)),
      'o servidor não aceita mais este login',
    );
    expect(
      describeFailure(strings, const ServerError('not allowed', reason: ServerErrorReason.notAllowed)),
      'o servidor não deixa este usuário mudar isso',
    );
    expect(describeFailure(strings, const ServerError('Wrong username or password')), 'Wrong username or password');
  });
}
