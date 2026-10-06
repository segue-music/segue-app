import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/ui/album_page.dart';
import 'package:segue/ui/home_page.dart';
import 'package:segue/ui/player_page.dart';

import 'home_search_test.dart' show pumpHome;

/// The home on a wide screen, with Dream On playing.
Future<PlayerController> pumpWide(WidgetTester tester) async {
  final (player, _) = await pumpHome(tester, const Size(1200, 700));
  await player.playQueue(const [Song(id: 's1', title: 'Dream On', artist: 'Aerosmith')]);
  await tester.pumpAndSettle();
  return player;
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

final back = find.byTooltip('Voltar');
final forward = find.byTooltip('Avançar');
final album = find.text('Toys in the Attic');

/// Whether the top bar's button [arrow] can be pressed.
bool enabled(WidgetTester tester, Finder arrow) =>
    tester.widget<IconButton>(find.ancestor(of: arrow, matching: find.byType(IconButton))).onPressed != null;

void main() {
  testWidgets('on a wide screen, a page opens between the bars, which stay: the top one, the side rail, the player', (
    tester,
  ) async {
    await pumpWide(tester);
    await tapAndSettle(tester, album);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byTooltip('Álbuns'), findsOneWidget, reason: 'the side rail');
    expect(find.byTooltip('Próxima'), findsOneWidget, reason: 'one player bar, the home\'s');
    final page = tester.getRect(find.byType(AlbumPage));
    expect(page.left, greaterThan(tester.getRect(find.byTooltip('Álbuns')).right));
    expect(page.top, greaterThanOrEqualTo(tester.getRect(find.byType(SearchBar)).bottom));
    expect(page.bottom, lessThanOrEqualTo(tester.getRect(find.byTooltip('Próxima')).top));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the top bar has no section name, but arrows beside the app\'s icon', (tester) async {
    await pumpWide(tester);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Início')), findsNothing);
    final icon = tester.getRect(find.byTooltip('Início'));
    expect(tester.getRect(back).left, greaterThanOrEqualTo(icon.right));
    expect(tester.getRect(forward).left, greaterThanOrEqualTo(tester.getRect(back).right));
    expect(tester.getRect(back).center.dy, moreOrLessEquals(icon.center.dy, epsilon: 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the arrows go back and forward through the pages opened, as a browser\'s do', (tester) async {
    await pumpWide(tester);
    expect(enabled(tester, back), isFalse);
    expect(enabled(tester, forward), isFalse);

    await tapAndSettle(tester, album);
    expect(enabled(tester, back), isTrue);
    await tapAndSettle(tester, back);
    expect(find.byType(AlbumPage), findsNothing);
    expect(enabled(tester, back), isFalse);
    expect(enabled(tester, forward), isTrue);
    await tapAndSettle(tester, forward);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(enabled(tester, forward), isFalse);

    // Another page, opened after going back, leaves nothing to go forward to.
    await tapAndSettle(tester, back);
    await tapAndSettle(tester, find.byTooltip('Mostrar a letra'));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(enabled(tester, forward), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a page has no back arrow of its own, the top bar\'s going back', (tester) async {
    await pumpWide(tester);
    await tapAndSettle(tester, album);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, where pages open over the whole home, a page has its back arrow', (tester) async {
    await pumpHome(tester, const Size(360, 800));
    await tapAndSettle(tester, album);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tapAndSettle(tester, find.byType(BackButton));
    expect(find.byType(AlbumPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the keyboard\'s arrows left and right go back and forward too, but while typing', (tester) async {
    await pumpWide(tester);
    await tapAndSettle(tester, album);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byType(AlbumPage), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byType(AlbumPage), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byType(AlbumPage), findsOneWidget, reason: 'the caret moved');
    // Out of the search bar, they go back again.
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byType(AlbumPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the full-screen player opens between the bars too, the player bar\'s lyrics and song acting on it', (
    tester,
  ) async {
    await pumpWide(tester);
    await tapAndSettle(tester, find.byTooltip('Mostrar a letra'));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byTooltip('Álbuns'), findsOneWidget);
    expect(find.byTooltip('Fechar o player'), findsOneWidget, reason: 'one player bar, the home\'s');

    await tapAndSettle(tester, find.byTooltip('Esconder a letra'));
    expect(find.byTooltip('Mostrar a letra'), findsOneWidget);
    expect(find.byType(PlayerPage), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('Fechar o player'));
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byTooltip('Abrir o player'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a section of the side rail, or a search, closes the pages', (tester) async {
    await pumpWide(tester);
    await tapAndSettle(tester, album);
    await tapAndSettle(tester, find.byTooltip('Álbuns'));
    expect(find.byType(AlbumPage), findsNothing);
    expect(enabled(tester, back), isFalse);
    expect(enabled(tester, forward), isFalse);

    await tapAndSettle(tester, find.byTooltip('Início'));
    await tapAndSettle(tester, album);
    await tester.enterText(find.byType(TextField), 'dream');
    await tester.pump(HomePage.searchTypingPause);
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsNothing);
    expect(find.text('Dream Police'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the system\'s back (Android\'s, a TV remote\'s) closes the page, rather than the app', (tester) async {
    await pumpWide(tester);
    await tapAndSettle(tester, album);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(enabled(tester, forward), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
