import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/app/television_screen.dart';
import 'package:segue/ui/home/home_view.dart';
import 'package:segue/ui/home/mix_row.dart';
import 'package:segue/ui/widgets/focus_ring.dart';
import 'package:segue/ui/widgets/tile_row.dart';

import 'directional_navigation_test.dart' show pumpFullHdHome;
import 'mixes_test.dart' show mixTile, pumpHome;

void main() {
  testWidgets('on a TV, the text is a seventh bigger than the system\'s, the remote drives the app, and the screen\'s '
      'edges have their room, as the system\'s padding; elsewhere, all as the system has it', (tester) async {
    late MediaQueryData media;

    Future<void> pump({required bool television}) => tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.1)),
        child: TelevisionScreen(
          enabled: television,
          child: Builder(
            builder: (context) {
              media = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await pump(television: true);
    expect(media.textScaler.scale(10), moreOrLessEquals(10 * 1.1 * 1.15));
    expect(media.navigationMode, NavigationMode.directional);
    expect(media.padding, const EdgeInsets.symmetric(horizontal: 12, vertical: 6));
    expect(media.viewPadding, media.padding);

    await pump(television: false);
    expect(media.textScaler.scale(10), moreOrLessEquals(11));
    expect(media.navigationMode, NavigationMode.traditional);
    expect(media.padding, EdgeInsets.zero);
  });

  testWidgets('on a TV, everything keeps out of the room at the screen\'s edges, the full-screen player too, the top '
      'bar\'s background going on to them, and the rows of tiles running on to the side as they scroll, their last '
      'tile in', (tester) async {
    await pumpFullHdHome(tester);
    const screen = Rect.fromLTRB(12, 6, 960 - 12, 540 - 6);

    for (final tooltip in ['Início', 'Tocando agora', 'Álbuns', 'Artistas', 'Configurações']) {
      final rect = tester.getRect(find.byTooltip(tooltip).first);
      expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight), isTrue, reason: '$tooltip: $rect');
    }

    // The pages, after the rail: the home's list, and its rows, which go on to the side.
    for (final scrollable in tester.widgetList(
      find.descendant(of: find.byType(HomeView), matching: find.byType(Scrollable)),
    )) {
      final rect = tester.getRect(find.byWidget(scrollable));
      expect(rect.left, greaterThanOrEqualTo(12), reason: '$rect');
      expect(rect.right, 960, reason: '$rect');
    }

    final row = find.byType(TileRow).first;
    final strip = find.descendant(of: row, matching: find.byType(Scrollable));
    final scroll = tester.state<ScrollableState>(strip).position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Album 29').first).right, lessThanOrEqualTo(960 - 12), reason: 'the last tile');

    final bar = tester.getRect(find.byType(AppBar));
    expect((bar.left, bar.right, bar.top), (0, 960, 0), reason: 'to the edges');

    // The full-screen player, which has the controls, a TV having no player bar.
    await tester.tap(find.byTooltip('Tocando agora'));
    await tester.pumpAndSettle();

    for (final tooltip in ['Tocar', 'Próxima', 'Repetir a lista', 'Fila', 'Aparelhos']) {
      final rect = tester.getRect(find.byTooltip(tooltip).first);
      expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight), isTrue, reason: '$tooltip: $rect');
    }

    await tester.pumpWidget(const SizedBox());
  });

  for (final television in [true, false]) {
    testWidgets(
      television
          ? 'on a TV, a card grows a little with the focus, its ring whole: the row has room for it'
          : 'elsewhere, a card keeps its size with the focus',
      (tester) async {
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
        await pumpHome(tester, pictured: {}, television: television);
        final tile = mixTile('Rock');
        final before = tester.getRect(tile);
        Focus.of(tester.element(find.descendant(of: tile, matching: find.byType(Padding)).first)).requestFocus();
        await tester.pumpAndSettle();
        final scale = tester.widget<AnimatedScale>(find.ancestor(of: tile, matching: find.byType(AnimatedScale)).first);
        expect(scale.scale, television ? FocusRing.grownScale : 1);

        final grown = tester.getRect(tile);
        final row = tester.getRect(find.descendant(of: find.byType(MixRow), matching: find.byType(Scrollable)).first);
        expect(grown.top, greaterThanOrEqualTo(row.top), reason: 'not cut off at the top');
        expect(grown.bottom, lessThanOrEqualTo(row.bottom), reason: 'nor at the bottom');
        expect(grown.height, moreOrLessEquals(before.height * (television ? FocusRing.grownScale : 1), epsilon: 0.5));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
