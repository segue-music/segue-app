import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../releases/album_credits.dart';
import '../releases/musicbrainz.dart';
import '../server/models.dart';
import 'dates.dart';
import 'reading_page.dart';

/// An album's credits, a [ReadingPage]: its cover at the top, its name and its artist under it, then who performed it,
/// wrote it and produced it, one a line, what they did beside them, with the songs they did it on where it isn't all
/// of them, where it was recorded, mixed and mastered, and when, and who made its cover and booklet.
class CreditsPage extends StatelessWidget {
  const CreditsPage(
    this.album, {
    required this.credits,
    this.initialCredits = const AlbumCredits(),
    this.inLibrary,
    this.onOpenArtist,
    super.key,
  });

  final Album album;

  /// Its credits, as they come: the media server's, then with what MusicBrainz adds; [initialCredits] until then.
  final Future<AlbumCredits> credits;

  final AlbumCredits initialCredits;

  /// The library's artists, by their ids on the media server and in MusicBrainz, those credited among whom are links
  /// to their pages ([onOpenArtist]), once they come; none: no links.
  final Future<Map<String, Artist>>? inLibrary;

  /// Opens the page of an artist credited, from the link of their name, as the credits close.
  final void Function(Artist artist)? onOpenArtist;

  /// Fades it in over the current page: over the whole window, also from a page of the home's page area.
  static Future<void> open(
    BuildContext context,
    Album album, {
    required Future<AlbumCredits> credits,
    AlbumCredits initialCredits = const AlbumCredits(),
    Future<Map<String, Artist>>? inLibrary,
    void Function(Artist artist)? onOpenArtist,
  }) => ReadingPage.open(
    context,
    CreditsPage(
      album,
      credits: credits,
      initialCredits: initialCredits,
      inLibrary: inLibrary,
      onOpenArtist: onOpenArtist,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final byline = [?album.artist, if (album.year case final year?) '$year'].join(' · ');
    return ReadingPage(
      picture: album.coverArt,
      icon: HugeIcons.strokeRoundedCd,
      children: [
        Text(album.name, style: text.headlineSmall?.copyWith(color: Colors.white)),
        if (byline.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(byline, style: text.bodyLarge?.copyWith(color: Colors.white70)),
          ),
        FutureBuilder(
          future: credits,
          initialData: initialCredits,
          builder: (context, credits) => FutureBuilder(
            future: inLibrary,
            builder: (context, inLibrary) => _credits(context, credits.requireData, inLibrary.data ?? const {}),
          ),
        ),
      ],
    );
  }

  /// [credits]' sections, under their titles, one a line, where the album was recorded coming after who produced it and
  /// before who made its cover and booklet, then that MusicBrainz said some of it, where it did. Those of [inLibrary]
  /// are links to their pages.
  Widget _credits(BuildContext context, AlbumCredits credits, Map<String, Artist> inLibrary) {
    final strings = AppLocalizations.of(context);
    (String, List<NameLine>) section(CreditSection section) => (
      strings.creditSection(section.name),
      [
        for (final person in credits.sections[section] ?? const <CreditedPerson>[])
          (
            name: person.name,
            artist: inLibrary[person.musicBrainzId] ?? inLibrary[person.artistId],
            detail: _rolesText(strings, person.roles),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NameTable(
          [
            section(CreditSection.performance),
            section(CreditSection.writing),
            section(CreditSection.production),
            (
              strings.recordingVenues,
              [
                for (final venue in credits.venues)
                  (name: _placeName(strings, venue.place), artist: null, detail: _venueText(strings, venue)),
              ],
            ),
            section(CreditSection.artwork),
          ],
          // Names take less of the column than a band's members' do, as what they did takes more than years.
          nameWidth: 0.45,
          onOpenArtist: onOpenArtist,
        ),
        if (credits.fromMusicBrainz)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              strings.creditsFromMusicBrainz,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
            ),
          ),
      ],
    );
  }

  /// What someone did, as it shows beside their name, apart by commas, each with the songs they did it on where it
  /// isn't all of them: "voz, guitarra, piano (faixas 3, 7), produção". What has one name in the app's language (a
  /// guitar and an electric guitar, in Portuguese) shows once, with the songs of either.
  static String _rolesText(AppLocalizations strings, List<CreditedRole> roles) {
    final names = <String, List<int>>{};

    for (final role in roles) {
      final name = switch (role) {
        (role: CreditRole.performer, part: final part?, tracks: _) => _partName(strings, part),
        _ => strings.creditRole(role.role.name),
      };
      final known = names[name];
      names[name] = known == null ? role.tracks : _together(known, role.tracks);
    }

    return [
      for (final MapEntry(key: name, value: tracks) in names.entries)
        tracks.isEmpty ? name : strings.creditOnTracks(name, tracks.length, _numbers(tracks)),
    ].join(', ');
  }

  /// What [place] is called: a place by its name, a country by the app's, where it has one.
  static String _placeName(AppLocalizations strings, RecordingPlace place) => switch (place.country) {
    final code? when strings.countryName(code).isNotEmpty => strings.countryName(code),
    _ => place.name,
  };

  /// What was done to the album at [venue], where it was mixing it or mastering it, and when, with its songs it was
  /// done to, where it isn't all of them: "julho – agosto de 1969 (faixas 1, 2)", "mixagem, março de 1975".
  static String _venueText(AppLocalizations strings, RecordingVenue venue) {
    final done = [
      switch (venue.stage) {
        RecordingStage.recording => '',
        RecordingStage.mixing => strings.creditRole(CreditRole.mixer.name),
        RecordingStage.mastering => strings.creditRole(CreditRole.masteringEngineer.name),
      },
      formatPeriod(strings, venue.begin, venue.end),
    ].where((part) => part.isNotEmpty).join(', ');
    final tracks = venue.tracks;
    return switch ((done, tracks)) {
      (_, []) => done,
      ('', _) => strings.onTracks(tracks.length, _numbers(tracks)),
      _ => strings.creditOnTracks(done, tracks.length, _numbers(tracks)),
    };
  }

  /// The songs of [one] and [other], by their numbers, in order; none (all of them) where either is all of them.
  static List<int> _together(List<int> one, List<int> other) =>
      one.isEmpty || other.isEmpty ? const [] : ({...one, ...other}.toList()..sort());

  /// [tracks], numbers in order, as they show: apart by commas, three or more in a row as a span: "1–3, 5, 7, 8".
  static String _numbers(List<int> tracks) {
    final spans = <(int, int)>[];

    for (final track in tracks) {
      if (spans.lastOrNull case (final first, final last) when track == last + 1) {
        spans.last = (first, track);
      } else {
        spans.add((track, track));
      }
    }

    return [
      for (final (first, last) in spans)
        if (last - first >= 2) '$first–$last' else if (last > first) '$first, $last' else '$first',
    ].join(', ');
  }

  /// [part], an instrument or a voice, in the app's language, where it has a name for it; otherwise as it came, in
  /// English mostly.
  static String _partName(AppLocalizations strings, String part) =>
      strings.creditPart(_parts[part.trim().toLowerCase()] ?? 'other', part);

  /// The instruments and voices the app has names for ([AppLocalizations.creditPart]), by the names MusicBrainz gives
  /// them, and those the media servers read from the files' tags, in lower case.
  static const _parts = {
    'vocals': 'vocals',
    'vocal': 'vocals',
    'voice': 'vocals',
    'lead vocals': 'leadVocals',
    'background vocals': 'backgroundVocals',
    'backing vocals': 'backgroundVocals',
    'choir vocals': 'choirVocals',
    'spoken vocals': 'spokenVocals',
    'guitar': 'guitar',
    'guitars': 'guitar',
    'electric guitar': 'electricGuitar',
    'acoustic guitar': 'acousticGuitar',
    'classical guitar': 'classicalGuitar',
    'spanish guitar': 'classicalGuitar',
    '12 string guitar': 'twelveStringGuitar',
    '12-string guitar': 'twelveStringGuitar',
    'slide guitar': 'slideGuitar',
    'bass': 'bass',
    'bass guitar': 'bass',
    'electric bass guitar': 'bass',
    'electric bass': 'bass',
    'double bass': 'doubleBass',
    'upright bass': 'doubleBass',
    'contrabass': 'doubleBass',
    'drums': 'drums',
    'drums (drum set)': 'drums',
    'drum set': 'drums',
    'drum kit': 'drums',
    'percussion': 'percussion',
    'drum machine': 'drumMachine',
    'piano': 'piano',
    'grand piano': 'piano',
    'electric piano': 'electricPiano',
    'rhodes': 'electricPiano',
    'fender rhodes': 'electricPiano',
    'rhodes piano': 'electricPiano',
    'keyboard': 'keyboards',
    'keyboards': 'keyboards',
    'synthesizer': 'synthesizer',
    'synth': 'synthesizer',
    'bass synthesizer': 'bassSynthesizer',
    'organ': 'organ',
    'hammond organ': 'organ',
    'electric organ': 'organ',
    'pipe organ': 'organ',
    'harpsichord': 'harpsichord',
    'accordion': 'accordion',
    'harmonica': 'harmonica',
    'saxophone': 'saxophone',
    'alto saxophone': 'altoSaxophone',
    'tenor saxophone': 'tenorSaxophone',
    'baritone saxophone': 'baritoneSaxophone',
    'soprano saxophone': 'sopranoSaxophone',
    'trumpet': 'trumpet',
    'trombone': 'trombone',
    'horn': 'frenchHorn',
    'french horn': 'frenchHorn',
    'flute': 'flute',
    'clarinet': 'clarinet',
    'oboe': 'oboe',
    'bassoon': 'bassoon',
    'recorder': 'recorder',
    'violin': 'violin',
    'cello': 'cello',
    'harp': 'harp',
    'strings': 'strings',
    'mandolin': 'mandolin',
    'tambourine': 'tambourine',
    'shaker': 'shaker',
    'triangle': 'triangle',
    'vibraphone': 'vibraphone',
    'xylophone': 'xylophone',
    'timpani': 'timpani',
    'hand clapping': 'handclaps',
    'handclaps': 'handclaps',
    'hand claps': 'handclaps',
    'whistle': 'whistling',
    'whistling': 'whistling',
    'effects': 'effects',
    'sound effects': 'effects',
    'melodica': 'melodica',
  };
}
