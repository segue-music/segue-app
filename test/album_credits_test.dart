import 'package:flutter_test/flutter_test.dart';
import 'package:segue/releases/album_credits.dart';
import 'package:segue/releases/musicbrainz.dart';
import 'package:segue/server/models.dart';

/// A song whose id is [id], and MusicBrainz id [musicBrainzId], with the media server's [credits].
Song song(String id, {String? musicBrainzId, List<Credit> credits = const []}) =>
    Song(id: id, title: id, musicBrainzId: musicBrainzId, credits: credits);

/// A track of a release of MusicBrainz's, whose id is `t[id]`, of the recording `rec[id]`, with its [credits] and
/// [sessions].
ReleaseTrack track(String id, {List<Credit> credits = const [], List<RecordingSession> sessions = const []}) =>
    (id: 't$id', recording: 'rec$id', credits: credits, sessions: sessions);

/// What MusicBrainz credits on a release: its [tracks], and on the release itself, [credits] and [sessions].
ReleaseCredits release(
  List<ReleaseTrack> tracks, {
  List<Credit> credits = const [],
  List<RecordingSession> sessions = const [],
}) => (tracks: tracks, credits: credits, sessions: sessions);

/// A performer, [name], who played or sang [part].
Credit plays(String name, String part) => Credit(name, CreditRole.performer, part: part);

/// Who [credits] has in [section], one a line, with what they did (a performer's part, or a role) and on which songs,
/// none where it's all of them: "Steven Tyler: lead vocals [2, 3], piano".
List<String> people(AlbumCredits credits, CreditSection section) => [
  for (final person in credits.sections[section] ?? const <CreditedPerson>[])
    '${person.name}: ${[for (final role in person.roles) '${role.part ?? role.role.name}${role.tracks.isEmpty ? '' : ' ${role.tracks}'}'].join(', ')}',
];

void main() {
  test('in each section, the media server\'s credits, where it has any; MusicBrainz\'s where it has none', () {
    final songs = [
      song('s1', credits: [const Credit('Steven Tyler', CreditRole.composer)]),
      song('s2'),
    ];
    final musicBrainz = release(
      [
        track('1', credits: [const Credit('Steven Tyler', CreditRole.writer), plays('Joe Perry', 'guitar')]),
        track('2', credits: [plays('Joe Perry', 'guitar')]),
      ],
      credits: [const Credit('George Marino', CreditRole.masteringEngineer)],
    );

    final own = AlbumCredits.of(songs);
    expect(own.sections.keys, [CreditSection.writing]);
    expect(people(own, CreditSection.writing), ['Steven Tyler: composer [1]']);
    expect(own.fromMusicBrainz, isFalse);

    final both = AlbumCredits.of(songs, musicBrainz: musicBrainz);
    expect(both.sections.keys, [CreditSection.performance, CreditSection.writing, CreditSection.production]);
    expect(people(both, CreditSection.writing), people(own, CreditSection.writing), reason: 'the server\'s');
    expect(people(both, CreditSection.performance), ['Joe Perry: guitar']);
    expect(people(both, CreditSection.production), [
      'George Marino: masteringEngineer',
    ], reason: 'the release\'s, on all its songs');
    expect(both.fromMusicBrainz, isTrue);

    expect(AlbumCredits.of([song('s1')]).isEmpty, isTrue);
  });

  test('by person, each thing they did once, whatever its case, with the songs they did it on, by their numbers: none '
      'where it\'s all of them; a voice first, then what they did on most songs; those on most songs first', () {
    final credits = AlbumCredits.of([
      song(
        's1',
        credits: [plays('Brad Whitford', 'bass'), plays('Joe Perry', 'guitar'), plays('Steven Tyler', 'piano')],
      ),
      song(
        's2',
        credits: [
          plays('Joe Perry', 'Guitar'),
          plays('Steven Tyler', 'harmonica'),
          plays('Steven Tyler', 'lead vocals'),
          const Credit('Jack Douglas', CreditRole.producer),
        ],
      ),
      song(
        's3',
        credits: [
          plays('Steven Tyler', 'piano'),
          plays('Steven Tyler', 'lead vocals'),
          plays('Joe Perry', 'guitar'),
          const Credit('Jack Douglas', CreditRole.producer),
          const Credit('Jack Douglas', CreditRole.mixer),
        ],
      ),
      song('s4', credits: [plays('Joe Perry', 'guitar'), plays('Steven Tyler', 'lead vocals')]),
    ]);
    expect(people(credits, CreditSection.performance), [
      'Joe Perry: guitar',
      'Steven Tyler: lead vocals [2, 3, 4], piano [1, 3], harmonica [2]',
      'Brad Whitford: bass [1]',
    ]);
    expect(people(credits, CreditSection.production), ['Jack Douglas: producer [2, 3], mixer [3]']);
  });

  test('those credited are one person by their MusicBrainz id, else their id on the server, else their name', () {
    final credits = AlbumCredits.of([
      song(
        's1',
        credits: [
          const Credit('Steven Tyler', CreditRole.composer, musicBrainzId: 'mb1', artistId: 'ar1'),
          const Credit('Steven Victor Tallarico', CreditRole.lyricist, musicBrainzId: 'mb1'),
          const Credit('Joe Perry', CreditRole.composer, artistId: 'ar2'),
          const Credit('Joseph Perry', CreditRole.lyricist, artistId: 'ar2'),
          const Credit('Tom Hamilton', CreditRole.composer),
          const Credit('tom hamilton', CreditRole.lyricist),
        ],
      ),
    ]);
    final [tyler, perry, hamilton] = credits.sections[CreditSection.writing]!;
    expect((tyler.name, tyler.musicBrainzId, tyler.artistId), ('Steven Tyler', 'mb1', 'ar1'));
    expect((perry.name, perry.artistId), ('Joe Perry', 'ar2'));
    expect(hamilton.name, 'Tom Hamilton');

    for (final person in [tyler, perry, hamilton]) {
      expect([for (final role in person.roles) role.role], [CreditRole.composer, CreditRole.lyricist]);
    }
  });

  test('MusicBrainz\'s tracks are the songs whose MusicBrainz id they have, theirs or their recordings\'; for songs '
      'without one, those in their places, where there are as many', () {
    final musicBrainz = release([
      track('1', credits: [plays('Steven Tyler', 'lead vocals')]),
      track('2', credits: [plays('Joe Perry', 'lead vocals')]),
    ]);
    List<String> singers(List<Song> songs) => [
      for (final person in AlbumCredits.of(songs, musicBrainz: musicBrainz).sections[CreditSection.performance]!)
        '${person.name} ${person.roles.single.tracks}',
    ];

    expect(singers([song('s1', musicBrainzId: 'rec2'), song('s2', musicBrainzId: 't1')]), [
      'Joe Perry [1]',
      'Steven Tyler [2]',
    ]);
    expect(singers([song('s1'), song('s2')]), ['Steven Tyler [1]', 'Joe Perry [2]']);
    expect(singers([song('s1', musicBrainzId: 'rec2'), song('s2'), song('s3')]), ['Joe Perry [1]']);
    expect(
      AlbumCredits.of([song('s1'), song('s2'), song('s3')], musicBrainz: musicBrainz).isEmpty,
      isTrue,
      reason: 'a song by its place only where there are as many tracks as songs',
    );
  });

  test('where it was recorded, by place, in the order of its songs: from the first day there to the last, with the '
      'songs recorded there; then where it was mixed, then mastered, a place where it was recorded too apart', () {
    const plant = (id: 'p1', name: 'The Record Plant', country: null);
    const studio = (id: 'p2', name: 'Electric Lady Studios', country: null);
    const kingdom = (id: 'gb', name: 'United Kingdom', country: 'GB');
    const sterling = (id: 'p3', name: 'Sterling Sound', country: null);
    final credits = AlbumCredits.of(
      [song('s1'), song('s2'), song('s3')],
      musicBrainz: release(
        [
          track(
            '1',
            sessions: [
              (place: plant, stage: RecordingStage.mixing, begin: const ReleaseDate(1975, month: 3), end: null),
              (
                place: studio,
                stage: RecordingStage.recording,
                begin: const ReleaseDate(1975, month: 3, day: 1),
                end: null,
              ),
              (
                place: plant,
                stage: RecordingStage.recording,
                begin: const ReleaseDate(1975, month: 1, day: 20),
                end: const ReleaseDate(1975, month: 1),
              ),
            ],
          ),
          track(
            '2',
            sessions: [
              (
                place: plant,
                stage: RecordingStage.recording,
                begin: const ReleaseDate(1974, month: 12),
                end: const ReleaseDate(1975, month: 2, day: 2),
              ),
            ],
          ),
          track('3'),
        ],
        sessions: [
          (place: sterling, stage: RecordingStage.mastering, begin: null, end: null),
          (place: kingdom, stage: RecordingStage.recording, begin: null, end: null),
        ],
      ),
    );
    expect(
      [
        for (final (:place, :stage, :begin, :end, :tracks) in credits.venues)
          (place.name, stage, (begin?.year, begin?.month, begin?.day), (end?.year, end?.month, end?.day), '$tracks'),
      ],
      [
        ('Electric Lady Studios', RecordingStage.recording, (1975, 3, 1), (1975, 3, 1), '[1]'),
        ('The Record Plant', RecordingStage.recording, (1974, 12, null), (1975, 2, 2), '[1, 2]'),
        ('United Kingdom', RecordingStage.recording, (null, null, null), (null, null, null), '[]'),
        ('The Record Plant', RecordingStage.mixing, (1975, 3, null), (1975, 3, null), '[1]'),
        ('Sterling Sound', RecordingStage.mastering, (null, null, null), (null, null, null), '[]'),
      ],
    );
    expect(credits.sections, isEmpty);
    expect(credits.isEmpty, isFalse);
    expect(credits.fromMusicBrainz, isTrue);
  });
}
