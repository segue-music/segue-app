import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:segue/ui/app/page_bar.dart';
import 'package:segue/ui/app/theme.dart';
import 'package:segue/ui/widgets/cover.dart';

/// A page with a [PageBar] titled Aerosmith over [under], with [shade] of the page's color, in the theme of
/// [brightness], opened over another, so that it has the back arrow.
Future<void> pumpBar(
  WidgetTester tester, {
  Color? under,
  double shade = 0,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(MaterialApp(theme: segueTheme(brightness), home: const SizedBox()));
  unawaited(
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: PageBar(title: 'Aerosmith', shade: ValueNotifier(shade), under: under),
              extendBodyBehindAppBar: true,
              body: const SizedBox.expand(),
            ),
          ),
        ),
  );
  await tester.pumpAndSettle();
}

/// The colors the bar's title, its halo and its arrow have, and how bright the system's icons are over it.
(Color?, Color?, Color?, Brightness?) barColors(WidgetTester tester) {
  final title = tester.renderObject<RenderParagraph>(find.text('Aerosmith')).text.style;
  final halo = title?.shadows?.single;
  final arrow = IconTheme.of(tester.element(find.byType(HugeIcon)));
  final system = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    find.descendant(of: find.byType(AppBar), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)),
  );

  return (title?.color, halo?.color, arrow.color, system.value.statusBarIconBrightness);
}

void main() {
  testWidgets('over a dark picture, the arrow, the title and the system\'s icons are light; over a light one, dark', (
    tester,
  ) async {
    final light = segueTheme(Brightness.light).colorScheme;

    await pumpBar(tester, under: Colors.black);
    expect(barColors(tester), (light.surface, light.onSurface, light.surface, Brightness.light));

    await pumpBar(tester, under: Colors.white);
    expect(barColors(tester), (light.onSurface, light.surface, light.onSurface, Brightness.dark));

    // In the dark theme, its page's color is the dark one, its text's the light one.
    final dark = segueTheme(Brightness.dark).colorScheme;

    await pumpBar(tester, under: Colors.white, brightness: Brightness.dark);
    expect(barColors(tester), (dark.surface, dark.onSurface, dark.surface, Brightness.dark));

    await pumpBar(tester, under: Colors.black, brightness: Brightness.dark);
    expect(barColors(tester), (dark.onSurface, dark.surface, dark.onSurface, Brightness.light));
  });

  testWidgets('as the bar fills with the page\'s color, the page\'s own text color comes back', (tester) async {
    final light = segueTheme(Brightness.light).colorScheme;

    await pumpBar(tester, under: Colors.black, shade: 0.3);
    expect(barColors(tester).$1, light.surface, reason: 'the picture still shows, dark');

    await pumpBar(tester, under: Colors.black, shade: 0.9);
    expect(barColors(tester), (light.onSurface, light.surface, light.onSurface, Brightness.dark));
  });

  testWidgets('over a picture, the title and the arrow have no line around them', (tester) async {
    await pumpBar(tester, under: Colors.black);
    expect(find.text('Aerosmith'), findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(find.text('Aerosmith')).text.style?.foreground, isNull);
    expect(tester.widget<HugeIcon>(find.byType(HugeIcon)).strokeWidth, isNull, reason: 'Hugeicons\' own');
  });

  testWidgets('over the page itself, the theme\'s colors', (tester) async {
    final light = segueTheme(Brightness.light).colorScheme;

    await pumpBar(tester);
    expect(barColors(tester).$1, light.onSurface);
  });

  testWidgets('a picture\'s color on average, over the part of it asked for', (tester) async {
    // Ten pixels square: white over its top half, black under it, and its bottom row see-through.
    final recorder = ui.PictureRecorder();

    Canvas(recorder)
      ..drawRect(const Rect.fromLTWH(0, 0, 10, 5), Paint()..color = Colors.white)
      ..drawRect(const Rect.fromLTWH(0, 5, 10, 4), Paint()..color = Colors.black);

    final image = await tester.runAsync(() => recorder.endRecording().toImage(10, 10));

    addTearDown(image!.dispose);

    Future<Color?> over(Rect region) => tester.runAsync<Color?>(() => averageColorOf(image, region));

    expect(await over(const Rect.fromLTWH(0, 0, 10, 5)), Colors.white);
    expect(await over(const Rect.fromLTWH(0, 5, 10, 4)), Colors.black);
    expect(await over(const Rect.fromLTWH(0, 1, 10, 8)), const Color(0xFF7F7F7F), reason: 'half of each');
    expect(await over(const Rect.fromLTWH(0, 7, 10, 3)), const Color(0xAA000000), reason: 'a third see-through');
    expect(await over(const Rect.fromLTWH(0, 9, 10, 1)), const Color(0x00000000));
    expect(await over(const Rect.fromLTWH(20, 0, 5, 5)), isNull, reason: 'none of it there');
  });
}
