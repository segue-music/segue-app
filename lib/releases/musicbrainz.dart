import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../server/models.dart';
import '../server/server.dart';

/// When an album came out, the labels that put it out and what kind of release it is, as its page shows them.
typedef AlbumRelease = ({ReleaseDate? date, List<String> labels, ReleaseType? type});

/// What MusicBrainz has of an album: dates, the one to show first first, labels and its type.
typedef _Found = ({List<ReleaseDate> dates, List<String> labels, ReleaseType? type});

/// The years a band (a group, an orchestra, a choir) has been together, or one of its members has been in it, as its
/// biography shows them: the one it began in ([begin]) and, where it has ended ([ended]), the one it ended in ([end]).
/// Null where MusicBrainz doesn't know it, but never both.
typedef BandYears = ({int? begin, int? end, bool ended});

/// One of a band's members, as its biography lists them: their MusicBrainz id and name, whether they are in it now
/// ([current]), and the years they have been in it, a span for each time, the first first (two for one who left and
/// came back); none where MusicBrainz knows none.
typedef BandMember = ({String id, String name, bool current, List<BandYears> years});

/// Where an artist comes from, as their biography shows it: the place a band formed in, or a person was born in, where
/// it's smaller than a country (a city, a state), as MusicBrainz names it, in English mostly ([place]), and the country
/// it's in, by its ISO 3166-1 code, or MusicBrainz's for one that has gone, as SU ([country]). Null where MusicBrainz
/// doesn't know it, but never both.
typedef Origin = ({String? place, String? country});

/// What MusicBrainz knows of a band, as its biography shows it: the years it has been together (none where it knows
/// none) and its members, in the order they came in ([_members]).
typedef Band = ({BandYears? years, List<BandMember> members});

/// Where a recording was made, as MusicBrainz names it, in English mostly: a place (a studio, a hall), or an area (a
/// city, a country), a country with its code ([country]), whose name the app has in its language.
typedef RecordingPlace = ({String id, String name, String? country});

/// A time a recording was made somewhere, as MusicBrainz knows it: where, and when, from [begin] to [end], one day or
/// several (either or both null where it doesn't know).
typedef RecordingSession = ({RecordingPlace place, ReleaseDate? begin, ReleaseDate? end});

/// One of a release's tracks, as its credits take it: its MusicBrainz id, and its recording's, who is credited on it (on
/// its recording, and on the works it performs: who wrote them), and where it was recorded.
typedef ReleaseTrack = ({String id, String recording, List<Credit> credits, List<RecordingSession> sessions});

/// Who MusicBrainz credits on a release, and where it was recorded: on each of its tracks, in order ([tracks]), and on
/// the release itself, which is on all of them ([credits], [sessions]).
typedef ReleaseCredits = ({List<ReleaseTrack> tracks, List<Credit> credits, List<RecordingSession> sessions});

/// MusicBrainz (musicbrainz.org), the open database of music releases: where an album's release date, record labels
/// and type come from when the media server doesn't say them, and its credits where the server has none; where it was
/// recorded, the years a band has been together, its members and where an artist comes from, which it never says.
class MusicBrainz {
  MusicBrainz({
    http.Client? client,
    Uri? base,
    this.spacing = const Duration(seconds: 1),
    this.remembersCountries = false,
  }) : _http = client ?? http.Client(),
       _base = base ?? Uri.parse('https://musicbrainz.org/ws/2/');

  final http.Client _http;
  final Uri _base;

  /// How far apart requests go: MusicBrainz takes about one a second from an app.
  final Duration spacing;

  /// Whether the countries of the places artists come from ([origin]) are kept across launches, in the preferences;
  /// otherwise for the session only, in the requests kept.
  final bool remembersCountries;

  static final _prefs = SharedPreferencesAsync();

  /// The preferences' key of the country of a place, by the place's MusicBrainz id after it.
  static const _countryKey = 'musicBrainzCountry.';

  /// MusicBrainz asks apps to say who they are, and where to reach whoever makes them.
  static const _userAgent = '$clientName/$appVersion ( https://github.com/segue-music/segue-app )';

  /// How long a request may take: the ones after it wait for it.
  static const _timeout = Duration(seconds: 10);

  /// When the next request may go.
  Future<void> _turn = Future.value();

  /// What MusicBrainz has of each album looked up, by the album's id, for the session: an album opened again asks
  /// nothing.
  final _found = <String, Future<_Found>>{};

  /// Each artist looked up, with their relations (null: one MusicBrainz doesn't have), by their MusicBrainz id, for the
  /// session: their biography asks for them as a band ([band]) and for where they come from ([origin]) at once.
  final _artists = <String, Future<Object?>>{};

  /// Each area looked up, with what it's part of, by its MusicBrainz id, for the session.
  final _areas = <String, Future<Object?>>{};

  /// Each release looked up for its credits, with its recordings' relations and their works', by its MusicBrainz id,
  /// for the session.
  final _releaseCredits = <String, Future<Object?>>{};

  /// [album]'s release date, record labels and type: the media server's, with what MusicBrainz adds where it says
  /// nothing, or less. A date where it has none, or one more precise than its own that agrees with it (the same year,
  /// and the same month where it has one); labels and a type where it has none.
  ///
  /// By the album's MusicBrainz id, the date is its release's (its edition's), else its release group's first, the
  /// labels its release's and the type its release group's. Without that id, there are no labels, and the date and the
  /// type are those of the release groups that the album's name and artist match (and its year, where the server has
  /// one), when they match only one date, and one type. The media server's alone when MusicBrainz has nothing more, or
  /// fails.
  Future<AlbumRelease> complete(Album album) async {
    final own = (date: album.releaseDate, labels: album.recordLabels, type: album.releaseType);
    final labelsWanted = album.recordLabels.isEmpty && album.musicBrainzId != null;

    if (album.releaseDate?.day != null && album.releaseType != null && !labelsWanted) {
      return own;
    }

    try {
      final found = await (_found[album.id] ??= _lookUp(album));
      return (
        date: _fuller(own.date, found.dates),
        labels: own.labels.isEmpty ? found.labels : own.labels,
        type: own.type ?? found.type,
      );
    } on Object {
      // To try again the next time.
      _found.remove(album.id);
      return own;
    }
  }

  /// What MusicBrainz has of [album]: by its MusicBrainz id, its release; without one, or for an id MusicBrainz no
  /// longer has, its release group.
  Future<_Found> _lookUp(Album album) async {
    final id = album.musicBrainzId;
    final release = id == null
        ? null
        : await _get('release/${Uri.encodeComponent(id)}', {'inc': 'labels release-groups'});

    if (release is Map<String, dynamic>) {
      final group = release['release-group'] as Map<String, dynamic>?;
      final labels = {
        for (final info in release['label-info'] as List? ?? const [])
          if ((info as Map<String, dynamic>)['label'] case {'name': final String name} when !_special(name)) name,
      };
      return (
        dates: [?_date(release['date']), ?_date(group?['first-release-date'])],
        labels: labels.toList(),
        type: _type(group),
      );
    }

    final artist = album.artist;

    if (artist == null) {
      return (dates: const <ReleaseDate>[], labels: const <String>[], type: null);
    }

    final found = await _get('release-group', {
      'query': 'releasegroup:${_phrase(album.name)} AND artist:${_phrase(artist)}',
      'limit': '25',
    });
    final groups = [
      if (found case {'release-groups': final List<Object?> list})
        for (final group in list) group as Map<String, dynamic>,
    ];
    // Those of its name and artist, and of its year where the server has one.
    final matched = [
      for (final group in groups)
        if (_key(group['title'] as String? ?? '') == _key(album.name) && _byArtist(group, artist))
          if (album.year == null || _date(group['first-release-date'])?.year == album.year) group,
    ];
    // By their text, which one date has in every group.
    final dates = {
      for (final group in matched)
        if (group['first-release-date'] case final String text) text: ?_date(text),
    };
    final types = {for (final group in matched) ?_type(group)};
    return (
      dates: dates.length == 1 ? [dates.values.single] : const <ReleaseDate>[],
      labels: const <String>[],
      type: types.length == 1 ? types.single : null,
    );
  }

  /// Who MusicBrainz credits on [album]'s release, by the album's MusicBrainz id, and where it was recorded: on each of
  /// its tracks, those its recording's relations name (who played, sang, produced, mixed it; where, and when, it was
  /// recorded), and those of the works it performs (who wrote them); on the release, those its own relations name
  /// (who mastered it). None for an album without that id, a release MusicBrainz doesn't have, and when it fails (asked
  /// again the next time).
  Future<ReleaseCredits?> credits(Album album) async {
    final id = album.musicBrainzId;

    if (id == null) {
      return null;
    }

    final Object? found;

    try {
      found = await _lookUpOnce(_releaseCredits, 'release', id, const {
        'inc': 'recordings recording-level-rels work-rels work-level-rels artist-rels place-rels area-rels',
      });
    } on Object {
      return null;
    }

    if (found is! Map<String, dynamic>) {
      return null;
    }

    final relations = _maps(found['relations']);
    return (
      tracks: [
        for (final medium in _maps(found['media']))
          for (final track in _maps(medium['tracks'])) ?_track(track),
      ],
      credits: [for (final relation in relations) ..._credits(relation)],
      sessions: [for (final relation in relations) ?_session(relation)],
    );
  }

  /// What MusicBrainz knows of [artist] as a band, by their MusicBrainz id: the years they have been together, and,
  /// for a group, their members (not an orchestra's or a choir's, which would be a crowd). A person's years in
  /// MusicBrainz are those of their life, not of their music. None for an artist without that id, a person (or one
  /// MusicBrainz doesn't know as a band), a band MusicBrainz knows neither of, and when it fails.
  Future<Band?> band(Artist artist) async {
    final id = artist.musicBrainzId;

    if (id == null) {
      return null;
    }

    final Object? found;

    try {
      found = await _lookUpOnce(_artists, 'artist', id, const {'inc': 'artist-rels'});
    } on Object {
      return null;
    }

    if (found case {'type': final String type} when const {'Group', 'Orchestra', 'Choir'}.contains(type)) {
      final years = switch (found['life-span']) {
        final Map<String, dynamic> span => _years(span),
        _ => null,
      };
      final members = type == 'Group' ? _members(found['relations']) : const <BandMember>[];
      return years == null && members.isEmpty ? null : (years: years, members: members);
    }

    return null;
  }

  /// Where [artist] comes from, by their MusicBrainz id, as it comes: the place a band formed in, or a person was born
  /// in, and the country it's in. MusicBrainz says that country by what the place is part of (a city of a county of a
  /// state), one area, and a request, at a time, which takes a while: meanwhile, the country MusicBrainz gives the
  /// artist, which is the place's mostly, and then, where the place's turns out to be another (one born abroad's), that
  /// one. Where the place's is already known (also from an earlier launch: [remembersCountries]), that one alone. Where it
  /// can't be found, the artist's country stays; where MusicBrainz knows no place, it's the artist's country alone.
  /// Nothing for an artist without that id, one MusicBrainz knows neither of, and when it fails.
  Stream<Origin> origin(Artist artist) async* {
    final id = artist.musicBrainzId;

    if (id == null) {
      return;
    }

    final Object? found;

    try {
      found = await _lookUpOnce(_artists, 'artist', id, const {'inc': 'artist-rels'});
    } on Object {
      return;
    }

    if (found is! Map<String, dynamic>) {
      return;
    }

    final own = switch (found['country'] ?? _countryCode(found['area'])) {
      final String country => country,
      _ => null,
    };

    switch (found['begin-area']) {
      // A country itself, which has no place in it to show.
      case {'iso-3166-1-codes': [final String country, ...]}:
        yield (place: null, country: country);

      // A state, which says its country by its code.
      case {'name': final String place} && final area when _countryCode(area) != null:
        yield (place: place, country: _countryCode(area));

      case {'name': final String place, 'id': final String area}:
        final known = await _rememberedCountry(area);
        yield (place: place, country: known ?? own);

        if (known == null) {
          final String? country;

          try {
            country = await _countryOf(area);
          } on Object {
            return;
          }

          if (country != null && country != own) {
            yield (place: place, country: country);
          }
        }

      case {'name': final String place}:
        yield (place: place, country: own);

      case _ when own != null:
        yield (place: null, country: own);
    }
  }

  /// The country, by its code, that the area whose MusicBrainz id is [id] is part of, the area it's part of looked up
  /// in turn while that doesn't say (a county), [levels] at most; none where MusicBrainz doesn't say. Each found is
  /// remembered ([_rememberedCountry]), the areas' between too.
  Future<String?> _countryOf(String id, {int levels = 4}) async {
    if (await _rememberedCountry(id) case final country?) {
      return country;
    }

    final found = await _lookUpOnce(_areas, 'area', id, const {'inc': 'area-rels'});

    for (final relation in (found as Map<String, dynamic>?)?['relations'] as List? ?? const []) {
      // An area's relation to the one it's part of goes backward.
      if (relation case {'type': 'part of', 'direction': 'backward', 'area': final Map<String, dynamic> whole}) {
        final country = switch ((_countryCode(whole), whole['id'])) {
          (final String country, _) => country,
          (null, final String id) when levels > 1 => await _countryOf(id, levels: levels - 1),
          _ => null,
        };

        if (country != null) {
          await _remember(id, country);
        }

        return country;
      }
    }

    return null;
  }

  /// The country, by its code, that the area whose MusicBrainz id is [id] has been found to be in, here or on an earlier
  /// launch; none where it hasn't, or the preferences fail.
  Future<String?> _rememberedCountry(String id) async {
    if (!remembersCountries) {
      return null;
    }

    try {
      return await _prefs.getString('$_countryKey$id');
    } on Object {
      return null;
    }
  }

  /// Remembers [country] as the one the area whose MusicBrainz id is [id] is in, for the next launches too: an area
  /// stays where it is.
  Future<void> _remember(String id, String country) async {
    if (!remembersCountries) {
      return;
    }

    try {
      await _prefs.setString('$_countryKey$id', country);
    } on Object {
      // It's found again the next time.
    }
  }

  /// What MusicBrainz has at [path] for the id [id], with [query], as [lookedUp] keeps it: asked only the first time,
  /// but again after it fails.
  Future<Object?> _lookUpOnce(
    Map<String, Future<Object?>> lookedUp,
    String path,
    String id,
    Map<String, String> query,
  ) async {
    try {
      return await (lookedUp[id] ??= _get('$path/${Uri.encodeComponent(id)}', query));
    } on Object {
      lookedUp.remove(id);
      rethrow;
    }
  }

  /// The JSON at [path], or null for a 404: none there. One request at a time, [spacing] apart.
  Future<Object?> _get(String path, Map<String, String> query) async {
    final turn = _turn;
    final done = Completer<void>();
    _turn = done.future;
    final url = _base.resolve(path).replace(queryParameters: {...query, 'fmt': 'json'});

    try {
      await turn;
      var response = await _http.get(url, headers: {'User-Agent': _userAgent}).timeout(_timeout);

      // MusicBrainz refuses requests over its rate, which counts every app behind the same address, and when it is
      // too busy: once more, after a pause.
      if (response.statusCode == 503) {
        await Future<void>.delayed(spacing);
        response = await _http.get(url, headers: {'User-Agent': _userAgent}).timeout(_timeout);
      }

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        throw ServerError('MusicBrainz: HTTP ${response.statusCode}');
      }

      return jsonDecode(utf8.decode(response.bodyBytes));
    } finally {
      unawaited(Future<void>.delayed(spacing, done.complete));
    }
  }

  void close() => _http.close();
}

/// The maps in [list], a list of MusicBrainz's JSON; none for none.
List<Map<String, dynamic>> _maps(Object? list) => [
  for (final item in list as List? ?? const [])
    if (item is Map<String, dynamic>) item,
];

/// [track], one of a release's in MusicBrainz, with what its recording's relations, and those of the works it
/// performs, credit on it, and where it was recorded; none for one without its ids.
ReleaseTrack? _track(Map<String, dynamic> track) {
  if (track case {
    'id': final String id,
    'recording': {'id': final String recording} && final Map<String, dynamic> data,
  }) {
    final relations = _maps(data['relations']);
    // The works it performs, more than one in a medley.
    final works = [
      for (final relation in relations)
        if (relation case {'type': 'performance', 'work': final Map<String, dynamic> work}) work,
    ];
    return (
      id: id,
      recording: recording,
      credits: [
        for (final relation in relations) ..._credits(relation),
        for (final work in works)
          for (final relation in _maps(work['relations'])) ..._credits(relation),
      ],
      sessions: [for (final relation in relations) ?_session(relation)],
    );
  }

  return null;
}

/// What the attributes of a relation say of it, rather than of the instrument or the voice it's for.
const _qualifiers = {'additional', 'assistant', 'associate', 'co', 'executive', 'guest', 'solo', 'task'};

/// The credits [relation], one of MusicBrainz's of a recording, a work or a release to an artist, gives: one for each
/// instrument it names, or voice; none for a relation of a kind the credits don't show.
List<Credit> _credits(Map<String, dynamic> relation) {
  if (relation case {
    'type': final String type,
    'direction': 'backward',
    'artist': {'id': final String id, 'name': final String name},
  }) {
    final attributes = [
      for (final attribute in relation['attributes'] as List? ?? const [])
        if (attribute is String) attribute,
    ];
    final parts = attributes.where((attribute) => !_qualifiers.contains(attribute)).toList();
    Credit credit(CreditRole role, {String? part}) => Credit(name, role, part: part, musicBrainzId: id);

    return switch (type) {
      'instrument' => [for (final part in parts) credit(CreditRole.performer, part: part)],
      'vocal' => [
        for (final part in parts.isEmpty ? const ['vocals'] : parts) credit(CreditRole.performer, part: part),
      ],
      'performer' => [credit(CreditRole.performer)],
      'performing orchestra' => [credit(CreditRole.orchestra)],
      'conductor' || 'chorus master' => [credit(CreditRole.conductor)],
      'composer' => [credit(CreditRole.composer)],
      'lyricist' => [credit(CreditRole.lyricist)],
      'writer' => [credit(CreditRole.writer)],
      'librettist' => [credit(CreditRole.librettist)],
      'arranger' || 'instrument arranger' || 'vocal arranger' => [credit(CreditRole.arranger)],
      'orchestrator' => [credit(CreditRole.orchestrator)],
      'producer' => [credit(attributes.contains('executive') ? CreditRole.executiveProducer : CreditRole.producer)],
      'engineer' ||
      'audio' ||
      'sound' ||
      'balance' => [credit(attributes.contains('assistant') ? CreditRole.assistantEngineer : CreditRole.engineer)],
      'recording' => [credit(CreditRole.recordingEngineer)],
      'mix' => [credit(CreditRole.mixer)],
      'mix-DJ' => [credit(CreditRole.djMixer)],
      'mastering' => [credit(CreditRole.masteringEngineer)],
      'editor' => [credit(CreditRole.editor)],
      'programming' => [credit(CreditRole.programmer)],
      'remixer' => [credit(CreditRole.remixer)],
      _ => const [],
    };
  }

  return const [];
}

/// Where, and when, [relation], one of MusicBrainz's of a recording or a release, says it was recorded: at a place,
/// or in an area; none for a relation of another kind.
RecordingSession? _session(Map<String, dynamic> relation) {
  final place = switch (relation) {
    {'type': 'recorded at', 'place': {'id': final String id, 'name': final String name}} => (
      id: id,
      name: name,
      country: null,
    ),
    {'type': 'recorded in', 'area': {'id': final String id, 'name': final String name} && final area} => (
      id: id,
      name: name,
      country: switch (area) {
        {'iso-3166-1-codes': [final String code, ...]} => code,
        _ => null,
      },
    ),
    _ => null,
  };
  return place == null ? null : (place: place, begin: _date(relation['begin']), end: _date(relation['end']));
}

/// The years of a life span of MusicBrainz's, or of a relation's dates; none where it knows neither year.
BandYears? _years(Map<String, dynamic> dates) {
  final begin = _date(dates['begin'])?.year;
  final end = _date(dates['end'])?.year;
  return begin == null && end == null ? null : (begin: begin, end: end, ended: end != null || dates['ended'] == true);
}

/// A band's members, from its [relations]: whoever MusicBrainz says has been a member of it, once, with each time they
/// have been, though it says it once for each instrument. In the order they came in: by the year they first did (those
/// it knows no year of last), of those who came the same year the one who has stayed longest first, then by their
/// names, as MusicBrainz sorts them (by surname).
List<BandMember> _members(Object? relations) {
  final names = <String, String>{};
  final sortNames = <String, String>{};
  final spans = <String, List<BandYears>>{};
  final current = <String>{};

  for (final relation in relations as List? ?? const []) {
    // A band's relation to a member goes backward: the member is a member of the band.
    if (relation case {
      'type': 'member of band',
      'direction': 'backward',
      'artist': {'id': final String id, 'name': final String name},
    }) {
      final dates = relation as Map<String, dynamic>;
      names[id] = name;
      sortNames[id] = (dates['artist'] as Map<String, dynamic>)['sort-name'] as String? ?? name;
      (spans[id] ??= []).addAll([?_years(dates)]);

      if (dates['ended'] != true && dates['end'] == null) {
        current.add(id);
      }
    }
  }

  final members = [
    for (final MapEntry(key: id, value: name) in names.entries)
      (id: id, name: name, current: current.contains(id), years: _merged(spans[id]!)),
  ];
  // The year they first came in, or one past any.
  int arrival(BandMember member) => member.years.map((span) => span.begin).nonNulls.firstOrNull ?? 1 << 30;

  return members..sort((a, b) {
    final earlier = arrival(a).compareTo(arrival(b));
    final longer = _length(b.years).compareTo(_length(a.years));
    return earlier != 0 ? earlier : (longer != 0 ? longer : sortNames[a.id]!.compareTo(sortNames[b.id]!));
  });
}

/// [spans] in order, those that overlap one: a member's are one for each instrument they have played, and a span
/// that hasn't ended takes in any after it.
List<BandYears> _merged(List<BandYears> spans) {
  // Those whose start isn't known first.
  final sorted = [...spans]..sort((a, b) => (a.begin ?? -1).compareTo(b.begin ?? -1));
  final merged = <BandYears>[];

  for (final span in sorted) {
    final last = merged.lastOrNull;
    final overlaps =
        last != null && (!last.ended || (last.end != null && span.begin != null && span.begin! <= last.end!));

    if (!overlaps) {
      merged.add(span);
      continue;
    }

    final ended = last.ended && span.ended;
    merged.last = (
      begin: last.begin ?? span.begin,
      end: switch ((last.end, span.end)) {
        _ when !ended => null,
        (final int one, final int other) => max(one, other),
        (final one, final other) => one ?? other,
      },
      ended: ended,
    );
  }

  return merged;
}

/// How many years [spans] add up to: forever with one that hasn't ended, none for one with a year not known.
int _length(List<BandYears> spans) {
  var years = 0;

  for (final span in spans) {
    switch (span) {
      case (begin: _, end: _, ended: false):
        return 1 << 30;
      case (begin: final int begin, end: final int end, ended: _):
        years += end - begin;
      default:
    }
  }

  return years;
}

/// The country [area], an area of MusicBrainz's, is, or is in, by its codes: a country's own (ISO 3166-1), or the one
/// its subdivision's starts with (ISO 3166-2, "US-MA"); none for one without them, as a city or a county.
String? _countryCode(Object? area) => switch (area) {
  {'iso-3166-1-codes': [final String code, ...]} => code,
  {'iso-3166-2-codes': [final String code, ...]} => code.split('-').first,
  _ => null,
};

/// Whether [name] is one of MusicBrainz's labels that stand for none, as "[no label]".
bool _special(String name) => name.startsWith('[') && name.endsWith(']');

/// [text] as a phrase in a MusicBrainz search, which is Lucene's syntax.
String _phrase(String text) => '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// [text] to compare names by, without case, spaces or punctuation: "Toys In The Attic" is "Toys in the Attic", and
/// "Run-DMC, Aerosmith" "Run‐DMC & Aerosmith". A name of punctuation alone stays as it is.
String _key(String text) {
  final letters = text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  return letters.isEmpty ? text.trim() : letters;
}

/// Whether [group] is by [artist]: all those credited for it, or the first.
bool _byArtist(Map<String, dynamic> group, String artist) {
  final credit = [for (final name in group['artist-credit'] as List? ?? const []) name as Map<String, dynamic>];
  final all = [for (final name in credit) '${name['name'] ?? ''}${name['joinphrase'] ?? ''}'].join();
  return credit.isNotEmpty &&
      (_key(artist) == _key(all) || _key(artist) == _key(credit.first['name'] as String? ?? ''));
}

/// What kind of release [group], a release group of MusicBrainz's, is, by its primary type and its secondary ones.
ReleaseType? _type(Map<String, dynamic>? group) => ReleaseType.named([
  if (group?['primary-type'] case final String type) type,
  for (final type in group?['secondary-types'] as List? ?? const [])
    if (type is String) type,
]);

/// A date of MusicBrainz's, as precise as it is: "1975-04-08", "1975-04" or "1975"; none for an empty one.
ReleaseDate? _date(Object? text) {
  final parts = text is String ? text.split('-').map(int.tryParse).toList() : const <int?>[];
  return switch (parts) {
    [final int year, final int month, final int day] => ReleaseDate(year, month: month, day: day),
    [final int year, final int month] => ReleaseDate(year, month: month),
    [final int year] => ReleaseDate(year),
    _ => null,
  };
}

/// The first of [found] that is more precise than [own] and agrees with it; [own] when none is.
ReleaseDate? _fuller(ReleaseDate? own, List<ReleaseDate> found) {
  for (final date in found) {
    if (own == null) {
      return date;
    }

    if (date.year == own.year && (own.month == null || date.month == own.month) && _precision(date) > _precision(own)) {
      return date;
    }
  }

  return own;
}

/// How precise [date] is: 3 for a day, 2 for a month, 1 for a year.
int _precision(ReleaseDate date) => date.day != null ? 3 : (date.month != null ? 2 : 1);
