import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/ui/album/album_page.dart';
import 'package:segue/ui/app/home_page.dart';
import 'package:segue/ui/player/player_page.dart';
import 'package:segue/ui/player/queue_page.dart';
import 'package:segue/ui/widgets/cover.dart';

import 'home_search_test.dart' show pumpHome;

/// The home on a wide screen, with Dream On playing.
Future<PlayerController> pumpWide(WidgetTester tester) async {
  final (player, _) = await pumpHome(tester, const Size(1200, 700));
  await player.playQueue(const [Song(id: 's1', title: 'Dream On', artist: 'Aerosmith')]);
  await tester.pumpAndSettle();

  return player;
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  // The album is in the home's last row, under its mixes, which may take it past the bottom of the screen.
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
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

  testWidgets(
    'the arrows sit close together, as a browser\'s, also on a touch screen',
    variant: const TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.android}),
    (tester) async {
      await pumpWide(tester);
      expect(tester.getSize(back), const Size.square(32));
      expect(tester.getCenter(forward).dx - tester.getCenter(back).dx, 32, reason: 'the icons 8 apart');
      await tester.pumpWidget(const SizedBox());
    },
  );

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
    expect(
      find.descendant(of: find.byType(AlbumPage), matching: find.byType(AppBar)),
      findsNothing,
      reason: 'an album\'s, nor a bar: its name is by its cover',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'on a phone, a page opens over the section and its name, under the bars at the bottom, which stay; it has '
    'its bar, with the back arrow and its name',
    (tester) async {
      final (player, _) = await pumpHome(tester, const Size(360, 800));
      await player.playQueue(const [Song(id: 's1', title: 'Dream On', artist: 'Aerosmith')]);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, album);
      expect(find.byType(AlbumPage), findsOneWidget);
      expect(find.text('Início').hitTestable(), findsOneWidget, reason: 'the sections\' bar\'s');
      expect(find.byTooltip('Abrir o player').hitTestable(), findsOneWidget);
      expect(
        find.byTooltip('Mostrar menu').hitTestable(),
        findsNothing,
        reason: 'the home\'s top bar is under the page',
      );
      expect(find.byType(BackButton), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: album),
        findsOneWidget,
        reason: 'the album\'s, in it',
      );
      await tapAndSettle(tester, find.byType(BackButton));
      expect(find.byType(AlbumPage), findsNothing);

      // A section, the one shown too, closes it.
      await tapAndSettle(tester, album);
      await tapAndSettle(tester, find.text('Início'));
      expect(find.byType(AlbumPage), findsNothing);
      expect(album, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('on a phone, the app\'s icon lines up with the home\'s rows, their titles and their covers', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 800));
    final logo = tester.getRect(find.descendant(of: find.byType(AppBar), matching: find.byType(Image)));
    expect(logo.left, 16);
    expect(tester.getRect(find.text('Adicionados recentemente')).left, logo.left);
    expect(tester.getRect(find.byType(Cover).first).left, logo.left);
    expect(
      tester.getRect(find.descendant(of: find.byType(AppBar), matching: find.text('Segue Music'))).left,
      72,
      reason: 'the app\'s name where a page\'s title is, after its back arrow',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a page stays open as the window is widened or narrowed: the same page area, by its navigator', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 800));
    await tapAndSettle(tester, album);
    expect(find.byType(BackButton), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 700);
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.byType(BackButton), findsNothing, reason: 'the top bar\'s arrow goes back');
    expect(enabled(tester, back), isTrue);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
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

  testWidgets('Esc goes back too, as the top bar\'s arrow does, wherever the focus is in the home, but while typing', (
    tester,
  ) async {
    await pumpWide(tester);
    await tapAndSettle(tester, album);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(AlbumPage), findsNothing);
    await tapAndSettle(tester, forward);
    expect(find.byType(AlbumPage), findsOneWidget, reason: 'and forward to it again');

    // On the app's icon, in the top bar.
    final icon = Focus.of(tester.element(find.descendant(of: find.byTooltip('Início'), matching: find.byType(Image))));
    icon.requestFocus();
    await tester.pump();
    expect(icon.hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(AlbumPage), findsNothing);

    await tapAndSettle(tester, forward);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(AlbumPage), findsOneWidget, reason: 'out of the search bar only');
    await press(tester, LogicalKeyboardKey.escape);
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
    await tapAndSettle(tester, find.descendant(of: find.byTooltip('Fechar o player'), matching: find.byType(Cover)));
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byTooltip('Abrir o player'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the player bar\'s queue button goes back from the queue rather than opening it again', (tester) async {
    await pumpWide(tester);
    // The pages under the one on top too.
    final queue = find.byType(QueuePage, skipOffstage: false);
    final button = find.byTooltip('Fila');

    await tapAndSettle(tester, button);
    expect(queue, findsOneWidget);
    await tapAndSettle(tester, button);
    expect(queue, findsNothing, reason: 'back to the section');

    await tapAndSettle(tester, forward);
    expect(queue, findsOneWidget, reason: 'open again, going forward');
    await tapAndSettle(tester, button);
    expect(queue, findsNothing, reason: 'going back from it too');

    await tapAndSettle(tester, find.descendant(of: find.byTooltip('Abrir o player'), matching: find.byType(Cover)));
    await tapAndSettle(tester, button);
    expect(queue, findsOneWidget);
    await tapAndSettle(tester, button);
    expect(queue, findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget, reason: 'back to the full-screen player it opened over');
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
