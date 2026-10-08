import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../releases/musicbrainz.dart';
import '../server/models.dart';
import 'arrow_scroll.dart';
import 'cover.dart';
import 'text_link.dart';
import 'themed_icon.dart';

/// An artist's biography, on black as a cover full screen is ([CoverPage]): their picture at the top, square, as wide
/// as the screen but no taller than most of it, and their name, with a band's years beside it, and the biography under
/// it, then a band's members, a column of reading width on a wide screen. Esc, its close button or a tap beside the
/// picture and the text closes it.
class BiographyPage extends StatefulWidget {
  const BiographyPage(
    this.biography, {
    required this.name,
    this.picture,
    this.band,
    this.origin,
    this.inLibrary,
    this.onOpenArtist,
    super.key,
  });

  final Biography biography;

  /// The artist's.
  final String name;

  /// The artist's picture, by its id on the server; none: a placeholder.
  final String? picture;

  /// What MusicBrainz knows of the artist, where they are a band ([MusicBrainz.band]): the years they have been
  /// together, beside their name, and their members, under the biography; none: neither shown.
  final Future<Band?>? band;

  /// Where the artist comes from ([MusicBrainz.origin]), under their name, as it comes; none: not shown.
  final Stream<Origin>? origin;

  /// The library's artists among the band's members, by their MusicBrainz ids, whose names are links to their pages
  /// ([onOpenArtist]); none: no links.
  final Future<Map<String, Artist>>? inLibrary;

  /// Opens a member's page, from the link of their name, as the biography closes.
  final void Function(Artist artist)? onOpenArtist;

  /// Fades it in over the current page: over the whole window, also from a page of the home's page area.
  static Future<void> open(
    BuildContext context,
    Biography biography, {
    required String name,
    String? picture,
    Future<Band?>? band,
    Stream<Origin>? origin,
    Future<Map<String, Artist>>? inLibrary,
    void Function(Artist artist)? onOpenArtist,
  }) => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => BiographyPage(
        biography,
        name: name,
        picture: picture,
        band: band,
        origin: origin,
        inLibrary: inLibrary,
        onOpenArtist: onOpenArtist,
      ),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<BiographyPage> createState() => _BiographyPageState();
}

class _BiographyPageState extends State<BiographyPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    // Most of the screen's height at most, so that the name and the biography start above its bottom.
    final side = min(screen.width, screen.height * 0.6);
    final source = widget.biography.source;

    void close() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      // The system's icons light, over the black above the picture.
      child: AnnotatedRegion(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          // A tap beside the picture and the text closes it (on a wide screen, the black on either side), as a tap
          // anywhere closes a cover's.
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  // Up and down scroll it, also while a member's link has the focus (from Tab: the arrows only scroll).
                  ArrowScroll(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: _keepingTaps(
                                  SizedBox.square(
                                    dimension: side,
                                    // Asked of the server at that size.
                                    child: LargeCover(
                                      widget.picture,
                                      size: (side * MediaQuery.devicePixelRatioOf(context)).ceil(),
                                      icon: HugeIcons.strokeRoundedUser,
                                    ),
                                  ),
                                ),
                              ),
                              _keepingTaps(
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // A band's years after the name, as they come, under it where they don't fit.
                                      FutureBuilder(
                                        future: widget.band,
                                        builder: (context, snapshot) => Text.rich(
                                          TextSpan(
                                            text: widget.name,
                                            children: [
                                              if (snapshot.data?.years case final years?) ...[
                                                const TextSpan(text: ' '),
                                                TextSpan(
                                                  text: _yearsText(strings, years),
                                                  style: text.bodyLarge?.copyWith(color: Colors.white54),
                                                ),
                                              ],
                                            ],
                                          ),
                                          style: text.headlineSmall?.copyWith(color: Colors.white),
                                        ),
                                      ),
                                      // Where they come from, under it, as it comes: the country again where it turns out
                                      // to be another.
                                      StreamBuilder(
                                        stream: widget.origin,
                                        builder: (context, snapshot) => switch (snapshot.data) {
                                          final origin? when _originText(strings, origin).isNotEmpty => Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Row(
                                              children: [
                                                const ThemedIcon(
                                                  HugeIcons.strokeRoundedLocation01,
                                                  size: 18,
                                                  color: Colors.white54,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    _originText(strings, origin),
                                                    style: text.bodyLarge?.copyWith(color: Colors.white70),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          _ => const SizedBox.shrink(),
                                        },
                                      ),
                                      for (final paragraph in widget.biography.paragraphs)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Text(
                                            paragraph,
                                            style: text.bodyLarge?.copyWith(
                                              color: Colors.white.withValues(alpha: 0.87),
                                            ),
                                          ),
                                        ),
                                      if (source != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 24),
                                          child: Text(
                                            strings.biographyProvidedBy(source),
                                            style: text.bodyMedium?.copyWith(color: Colors.white54),
                                          ),
                                        ),
                                      // Once both have come: the members, then which of them are links.
                                      FutureBuilder(
                                        future: widget.band,
                                        builder: (context, band) => FutureBuilder(
                                          future: widget.inLibrary,
                                          builder: (context, inLibrary) => switch ((band.data, inLibrary)) {
                                            (
                                              final band?,
                                              AsyncSnapshot(
                                                connectionState: ConnectionState.none || ConnectionState.done,
                                                :final data,
                                              ),
                                            )
                                                when band.members.isNotEmpty =>
                                              _members(band, data ?? const {}),
                                            _ => const SizedBox.shrink(),
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // On a dark round, to stand out from the picture, and from the text going up under it.
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(
                      tooltip: strings.close,
                      icon: const ThemedIcon(HugeIcons.strokeRoundedCancel01),
                      color: Colors.white,
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: close,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [band]'s members, one a line, their years beside them, under titles: those it has now, then those it had; where it
  /// has broken up, all of them under the first. Those in the library ([inLibrary], by their MusicBrainz ids) are links
  /// to their pages. The years line up, after the longest name or most of the column, where a longer one wraps.
  Widget _members(Band band, Map<String, Artist> inLibrary) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final ended = band.years?.ended ?? false;
    final groups = [
      (
        strings.bandMembers,
        [
          for (final member in band.members)
            if (ended || member.current) member,
        ],
      ),
      if (!ended)
        (
          strings.formerBandMembers,
          [
            for (final member in band.members)
              if (!member.current) member,
          ],
        ),
    ];
    final name = text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.87));
    final years = text.bodyLarge?.copyWith(color: Colors.white54);
    return Table(
      columnWidths: const {0: MinColumnWidth(IntrinsicColumnWidth(), FractionColumnWidth(0.6))},
      defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (final (title, members) in groups)
          if (members.isNotEmpty) ...[
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 4),
                  child: Text(title, style: text.titleMedium?.copyWith(color: Colors.white)),
                ),
                const SizedBox.shrink(),
              ],
            ),
            for (final member in members)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 4, end: 16),
                    child: switch (inLibrary[member.id]) {
                      final artist? => TextLink(
                        member.name,
                        tooltip: strings.openArtist,
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onOpenArtist?.call(artist);
                        },
                        style: name,
                        maxLines: 2,
                      ),
                      null => Text(member.name, style: name),
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_memberYearsText(strings, member.years), style: years),
                  ),
                ],
              ),
          ],
      ],
    );
  }

  /// [origin] as it shows under the name: "Boston, Estados Unidos", "Reino Unido", "Seattle"; empty where it has
  /// neither a place nor a country the app has a name for.
  static String _originText(AppLocalizations strings, Origin origin) {
    final country = switch (origin.country) {
      final code? => strings.countryName(code),
      null => '',
    };
    return switch ((origin.place, country)) {
      (final place?, '') => place,
      (final place?, _) => strings.placeInCountry(place, country),
      (null, _) => country,
    };
  }

  /// [years] as they show beside the name, on one line: "(desde 1991)", "(1966 – 1978)", "(até 1978)", "(1966 – ?)".
  static String _yearsText(AppLocalizations strings, BandYears years) =>
      strings.bandYears(_kind(years), years.begin ?? 0, years.end ?? 0).replaceAll(' ', '\u00a0');

  /// A member's [years] as they show beside their name, each time on one line: "desde 1970", "1970 – 1979, desde
  /// 1984", "1960".
  static String _memberYearsText(AppLocalizations strings, List<BandYears> years) => [
    for (final span in years)
      strings.memberYears(_kind(span), span.begin ?? 0, span.end ?? 0).replaceAll(' ', '\u00a0'),
  ].join(', ');

  /// What kind of span [years] are, as the messages that show them choose by.
  static String _kind(BandYears years) => switch (years) {
    (begin: _, end: _, ended: false) => 'since',
    (begin: null, end: _, ended: true) => 'until',
    (begin: _, end: null, ended: true) => 'endUnknown',
    (begin: final int begin, end: final int end, ended: true) when begin == end => 'same',
    _ => 'other',
  };

  /// [child], whose taps stay in it: only those beside it close the page.
  static Widget _keepingTaps(Widget child) =>
      GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: child);
}
