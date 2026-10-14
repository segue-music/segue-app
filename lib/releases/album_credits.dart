import 'dart:math';

import '../server/models.dart';
import 'musicbrainz.dart';

/// Someone credited on an album, as its credits show them: by name, with their ids to find them in the library by (as
/// an artist on the media server, and in MusicBrainz), and what they did ([roles]), what they did on most songs first,
/// a voice before an instrument.
typedef CreditedPerson = ({String name, String? artistId, String? musicBrainzId, List<CreditedRole> roles});

/// Something someone did on an album ([role], with the instrument or the voice of a performer: [part]), and the
/// album's songs they did it on, by their numbers in it, from 1: none where it's all of them.
typedef CreditedRole = ({CreditRole role, String? part, List<int> tracks});

/// A place an album was recorded, mixed or mastered at ([stage]), and when: from the first day it was there to the last
/// (either or both null where MusicBrainz doesn't know them), and the album's songs it was there, by their numbers,
/// from 1: none where it's all of them.
typedef RecordingVenue = ({
  RecordingPlace place,
  RecordingStage stage,
  ReleaseDate? begin,
  ReleaseDate? end,
  List<int> tracks,
});

/// Who is credited on an album, in sections (who performed it, wrote it, produced it, made its cover and booklet), and
/// where it was recorded, mixed and mastered, as its credits' page shows them.
class AlbumCredits {
  const AlbumCredits({this.sections = const {}, this.venues = const [], this.fromMusicBrainz = false});

  /// [songs]' credits: in each section, the media server's, where it says any there, else MusicBrainz's ([musicBrainz],
  /// of the album's release), which come by track, each of [songs] the track whose MusicBrainz id it has (its
  /// recording's or its own), or, where it has none, the one in its place, where the release has as many as the album
  /// has songs. Where it was recorded, mixed and mastered, MusicBrainz's. Each section has those on most songs first,
  /// then those on the earliest, then in the order they come.
  factory AlbumCredits.of(List<Song> songs, {ReleaseCredits? musicBrainz}) {
    final tracks = _tracks(songs, musicBrainz);
    final all = {for (var i = 0; i < songs.length; i++) i};
    final sections = <CreditSection, List<CreditedPerson>>{};
    var fromMusicBrainz = false;

    for (final section in CreditSection.values) {
      // Each credit with the songs it's on, by their indexes.
      final own = [
        for (final (i, song) in songs.indexed)
          for (final credit in song.credits)
            if (credit.role.section == section) (credit, {i}),
      ];
      final found = own.isNotEmpty
          ? own
          : [
              for (final (i, track) in tracks.indexed)
                for (final credit in track?.credits ?? const <Credit>[])
                  if (credit.role.section == section) (credit, {i}),
              for (final credit in musicBrainz?.credits ?? const <Credit>[])
                if (credit.role.section == section) (credit, all),
            ];

      if (found.isNotEmpty) {
        sections[section] = _people(found, songs.length);
        fromMusicBrainz = fromMusicBrainz || own.isEmpty;
      }
    }

    final venues = _venues([
      for (final (i, track) in tracks.indexed)
        for (final session in track?.sessions ?? const <RecordingSession>[]) (session, {i}),
      for (final session in musicBrainz?.sessions ?? const <RecordingSession>[]) (session, all),
    ], songs.length);

    return AlbumCredits(sections: sections, venues: venues, fromMusicBrainz: fromMusicBrainz || venues.isNotEmpty);
  }

  /// Those credited in each section that has any, in the order of [CreditSection].
  final Map<CreditSection, List<CreditedPerson>> sections;

  /// Where it was recorded, then where it was mixed, then where it was mastered, each the place of its first songs
  /// first.
  final List<RecordingVenue> venues;

  /// Whether any of it comes from MusicBrainz.
  final bool fromMusicBrainz;

  /// Whether it has nothing to show.
  bool get isEmpty => sections.isEmpty && venues.isEmpty;
}

/// The track of [musicBrainz]'s release each of [songs] is: the one whose MusicBrainz id, or whose recording's, the song
/// has, or, for a song that has none, the one in its place, where the release has as many tracks as there are songs;
/// null for a song no track is.
List<ReleaseTrack?> _tracks(List<Song> songs, ReleaseCredits? musicBrainz) {
  final tracks = musicBrainz?.tracks ?? const <ReleaseTrack>[];
  final byId = {
    for (final track in tracks) ...{track.recording: track, track.id: track},
  };

  return [
    for (final (i, song) in songs.indexed)
      switch (song.musicBrainzId) {
        final id? => byId[id],
        null when tracks.length == songs.length => tracks[i],
        null => null,
      },
  ];
}

/// [credits], each with the songs it's on, by their indexes among [count], by person: by their MusicBrainz id, else
/// their id on the media server, else their name.
List<CreditedPerson> _people(List<(Credit, Set<int>)> credits, int count) {
  // By person, in the order they come: their first credit, and the songs of each thing they did, by its role and part
  // (whatever its case), with the part as it first came.
  final byPerson = <String, (Credit, Map<(CreditRole, String?), (String?, Set<int>)>)>{};

  for (final (credit, songs) in credits) {
    final (_, roles) = byPerson[credit.musicBrainzId ?? credit.artistId ?? credit.name.toLowerCase()] ??= (credit, {});
    final (_, found) = roles[(credit.role, credit.part?.toLowerCase())] ??= (credit.part, <int>{});

    found.addAll(songs);
  }

  final people = [
    for (final (first, roles) in byPerson.values)
      (
        person: first,
        songs: {for (final (_, songs) in roles.values) ...songs},
        roles: [for (final MapEntry(key: (role, _), value: (part, songs)) in roles.entries) (role, part, songs)],
      ),
  ];
  // Those on most songs first, then those on the earliest, then in the order they came.
  final order = [for (var i = 0; i < people.length; i++) i]
    ..sort((a, b) {
      final (one, other) = (people[a], people[b]);
      final more = other.songs.length.compareTo(one.songs.length);
      final earlier = one.songs.reduce(min).compareTo(other.songs.reduce(min));

      return more != 0 ? more : (earlier != 0 ? earlier : a.compareTo(b));
    });

  return [
    for (final i in order)
      (
        name: people[i].person.name,
        artistId: people[i].person.artistId,
        musicBrainzId: people[i].person.musicBrainzId,
        roles: _ordered(people[i].roles, count),
      ),
  ];
}

/// [roles], each with the songs it's on, by their indexes among [count], in the order of [CreditRole], a voice before an
/// instrument, then those on most songs first, then in the order they came.
List<CreditedRole> _ordered(List<(CreditRole, String?, Set<int>)> roles, int count) {
  bool voice(String? part) => part?.toLowerCase().contains('vocal') ?? false;

  final order = [for (var i = 0; i < roles.length; i++) i]
    ..sort((a, b) {
      final (role, part, songs) = roles[a];
      final (otherRole, otherPart, otherSongs) = roles[b];
      final kind = role.index.compareTo(otherRole.index);
      final voices = (voice(otherPart) ? 1 : 0).compareTo(voice(part) ? 1 : 0);
      final more = otherSongs.length.compareTo(songs.length);

      return kind != 0 ? kind : (voices != 0 ? voices : (more != 0 ? more : a.compareTo(b)));
    });

  return [for (final i in order) (role: roles[i].$1, part: roles[i].$2, tracks: _numbers(roles[i].$3, count))];
}

/// Where [sessions], each with the songs it's on, by their indexes among [count], were, by place and stage: from the
/// earliest day of its sessions to the latest. Where they were recorded first, then where mixed, then mastered, each
/// in the order they come.
List<RecordingVenue> _venues(List<(RecordingSession, Set<int>)> sessions, int count) {
  final places = <(String, RecordingStage), (RecordingSession, List<ReleaseDate>, Set<int>)>{};

  for (final (session, songs) in sessions) {
    final (_, dates, found) = places[(session.place.id, session.stage)] ??= (session, [], {});

    dates.addAll([?session.begin, ?session.end]);
    found.addAll(songs);
  }

  return [
    for (final stage in RecordingStage.values)
      for (final (session, dates, songs) in places.values)
        if (session.stage == stage)
          (
            place: session.place,
            stage: stage,
            begin: dates.isEmpty ? null : dates.reduce((a, b) => _compare(a, b) <= 0 ? a : b),
            end: dates.isEmpty ? null : dates.reduce((a, b) => _compare(a, b) >= 0 ? a : b),
            tracks: _numbers(songs, count),
          ),
  ];
}

/// The numbers of [songs], by their indexes among [count], in order, from 1; none where they are all of them.
List<int> _numbers(Set<int> songs, int count) =>
    songs.length == count ? const [] : ([for (final i in songs) i + 1]..sort());

/// Which of [a] and [b] is earlier, where a date known only to its month or year is at its start.
int _compare(ReleaseDate a, ReleaseDate b) {
  final year = a.year.compareTo(b.year);
  final month = (a.month ?? 0).compareTo(b.month ?? 0);

  return year != 0 ? year : (month != 0 ? month : (a.day ?? 0).compareTo(b.day ?? 0));
}
