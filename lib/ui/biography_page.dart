import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../pictures/fanart_tv.dart';
import '../releases/musicbrainz.dart';
import '../server/models.dart';
import 'reading_page.dart';
import 'themed_icon.dart';

/// An artist's biography, a [ReadingPage]: their pictures at the top, in a gallery, and their name, with a band's years
/// beside it, and the biography under it, then a band's members.
class BiographyPage extends StatelessWidget {
  const BiographyPage(
    this.biography, {
    required this.name,
    this.picture,
    this.morePictures,
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

  /// More pictures of the artist, after [picture], by their URLs, as they come ([FanartTv.artistPictures]); none:
  /// [picture] alone.
  final Future<List<Uri>>? morePictures;

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
    Future<List<Uri>>? morePictures,
    Future<Band?>? band,
    Stream<Origin>? origin,
    Future<Map<String, Artist>>? inLibrary,
    void Function(Artist artist)? onOpenArtist,
  }) => ReadingPage.open(
    context,
    BiographyPage(
      biography,
      name: name,
      picture: picture,
      morePictures: morePictures,
      band: band,
      origin: origin,
      inLibrary: inLibrary,
      onOpenArtist: onOpenArtist,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final source = biography.source;
    return ReadingPage.gallery(
      picture: picture,
      morePictures: morePictures,
      icon: HugeIcons.strokeRoundedUser,
      children: [
        // A band's years after the name, as they come, under it where they don't fit.
        FutureBuilder(
          future: band,
          builder: (context, snapshot) => Text.rich(
            TextSpan(
              text: name,
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
        // Where they come from, under it, as it comes: the country again where it turns out to be another.
        StreamBuilder(
          stream: origin,
          builder: (context, snapshot) => switch (snapshot.data) {
            final origin? when _originText(strings, origin).isNotEmpty => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const ThemedIcon(HugeIcons.strokeRoundedLocation01, size: 18, color: Colors.white54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_originText(strings, origin), style: text.bodyLarge?.copyWith(color: Colors.white70)),
                  ),
                ],
              ),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
        for (final paragraph in biography.paragraphs)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(paragraph, style: text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.87))),
          ),
        if (source != null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(strings.biographyProvidedBy(source), style: text.bodyMedium?.copyWith(color: Colors.white54)),
          ),
        // Once both have come: the members, then which of them are links.
        FutureBuilder(
          future: band,
          builder: (context, band) => FutureBuilder(
            future: inLibrary,
            builder: (context, inLibrary) => switch ((band.data, inLibrary)) {
              (final band?, AsyncSnapshot(connectionState: ConnectionState.none || ConnectionState.done, :final data))
                  when band.members.isNotEmpty =>
                _members(strings, band, data ?? const {}),
              _ => const SizedBox.shrink(),
            },
          ),
        ),
      ],
    );
  }

  /// [band]'s members, one a line, their years beside them, under titles: those it has now, then those it had; where it
  /// has broken up, all of them under the first. Those in the library ([inLibrary], by their MusicBrainz ids) are links
  /// to their pages.
  Widget _members(AppLocalizations strings, Band band, Map<String, Artist> inLibrary) {
    final ended = band.years?.ended ?? false;
    NameLine line(BandMember member) =>
        (name: member.name, artist: inLibrary[member.id], detail: _memberYearsText(strings, member.years));

    return NameTable([
      (
        strings.bandMembers,
        [
          for (final member in band.members)
            if (ended || member.current) line(member),
        ],
      ),
      if (!ended)
        (
          strings.formerBandMembers,
          [
            for (final member in band.members)
              if (!member.current) line(member),
          ],
        ),
    ], onOpenArtist: onOpenArtist);
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
}
