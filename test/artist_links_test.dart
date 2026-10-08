import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/server/models.dart';
import 'package:segue/ui/artist_link.dart';

const runDmc = Artist(id: 'ar2', name: 'Run-DMC');
const aerosmith = Artist(id: 'ar1', name: 'Aerosmith');
const robThomas = Artist(id: 'ar4', name: 'Rob Thomas');

/// The links of [artists], whose song's artist is [text], in [width] pixels, aligned as [textAlign] says; returns the
/// artists the links open, as they open them, and 'unknown' for a tap on [text] where [unknown] is.
Future<List<String>> pumpLinks(
  WidgetTester tester,
  String text,
  List<Artist> artists, {
  double width = 600,
  bool unknown = false,
  TextAlign? textAlign,
}) async {
  final opened = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt')],
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ArtistLinks(
              text,
              artists,
              onOpen: (artist) => opened.add(artist.id),
              onTapUnknown: unknown ? () => opened.add('unknown') : null,
              textAlign: textAlign,
            ),
          ),
        ),
      ),
    ),
  );
  return opened;
}

final links = find.byTooltip('Abrir o artista');

void main() {
  testWidgets('each artist\'s name opens their page, and between them a dot, plain text, as in an album\'s byline', (
    tester,
  ) async {
    final opened = await pumpLinks(tester, 'Run-DMC; Aerosmith', [runDmc, aerosmith]);
    expect(links, findsNWidgets(2));
    expect(find.text(' · '), findsOneWidget);
    await tester.tap(find.text('Aerosmith'));
    await tester.tap(find.text('Run-DMC'));
    await tester.tap(find.text(' · '), warnIfMissed: false);
    expect(opened, ['ar1', 'ar2']);

    // One after the other, as one text: the room between them is that of the dot and its spaces.
    final (first, between, second) = (
      tester.getRect(find.text('Run-DMC')),
      tester.getRect(find.text(' · ')),
      tester.getRect(find.text('Aerosmith')),
    );
    expect((between.left, second.left), (first.right, between.right));
    expect(between.width, first.width * 3 / 'Run-DMC'.length, reason: 'the test font\'s letters are all as wide');
  });

  testWidgets('centered, as in the full-screen player, the dot is still in the middle of its spaces', (tester) async {
    await pumpLinks(tester, '', [runDmc, aerosmith], textAlign: TextAlign.center);
    final letter = tester.getSize(find.text('Run-DMC')).width / 'Run-DMC'.length;
    final dot = tester.renderObject<RenderParagraph>(find.text(' · '));
    // Off its middle, it was half a space further.
    expect(
      dot.getOffsetForCaret(const TextPosition(offset: 1), Rect.zero).dx,
      moreOrLessEquals(letter, epsilon: 1),
      reason: 'after one space',
    );
    expect(tester.getCenter(find.byType(Row)).dx, 300, reason: 'the line is centered, as a whole');
  });

  testWidgets('whatever the media server puts between them, the dot does', (tester) async {
    await pumpLinks(tester, 'Santana feat. Rob Thomas', [const Artist(id: 'ar3', name: 'Santana'), robThomas]);
    expect(find.textContaining('feat.'), findsNothing);
    expect(find.text(' · '), findsOneWidget);
    expect(links, findsNWidgets(2));
  });

  testWidgets('with no artists to link, the song\'s artist, plain, or opening what it says', (tester) async {
    await pumpLinks(tester, 'Run-DMC; Aerosmith', []);
    expect(find.text('Run-DMC; Aerosmith'), findsOneWidget);
    expect(links, findsNothing);

    final opened = await pumpLinks(tester, 'Run-DMC; Aerosmith', [], unknown: true);
    await tester.tap(find.text('Run-DMC; Aerosmith'));
    expect(opened, ['unknown']);
  });

  testWidgets('in too little room, the artist it runs out in ends in an ellipsis, and those after are left out', (
    tester,
  ) async {
    const artists = [runDmc, aerosmith, robThomas];
    await pumpLinks(tester, '', artists);
    final letter = tester.getSize(find.text('Run-DMC')).width / 'Run-DMC'.length;

    // Room for "Run-DMC · Aero".
    final opened = await pumpLinks(tester, '', artists, width: letter * 'Run-DMC · Aero'.length);
    expect(tester.renderObject<RenderParagraph>(find.text('Run-DMC')).didExceedMaxLines, isFalse);
    expect(tester.renderObject<RenderParagraph>(find.text('Aerosmith')).didExceedMaxLines, isTrue);
    expect(find.text('Rob Thomas'), findsNothing);
    expect(links, findsNWidgets(2));
    await tester.tap(find.text('Aerosmith'));
    expect(opened, ['ar1'], reason: 'what shows of them still opens their page');
  });
}
