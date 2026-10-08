import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

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

/// What MusicBrainz knows of a band, as its biography shows it: the years it has been together (none where it knows
/// none) and its members, in the order they came in ([_members]).
typedef Band = ({BandYears? years, List<BandMember> members});

/// MusicBrainz (musicbrainz.org), the open database of music releases: where an album's release date, record labels
/// and type come from when the media server doesn't say them, and the years a band has been together and its members,
/// which it never says.
class MusicBrainz {
  MusicBrainz({http.Client? client, Uri? base, this.spacing = const Duration(seconds: 1)})
    : _http = client ?? http.Client(),
      _base = base ?? Uri.parse('https://musicbrainz.org/ws/2/');

  final http.Client _http;
  final Uri _base;

  /// How far apart requests go: MusicBrainz takes about one a second from an app.
  final Duration spacing;

  /// MusicBrainz asks apps to say who they are, and where to reach whoever makes them.
  static const _userAgent = '$clientName/$appVersion ( https://github.com/segue-music/segue-app )';

  /// How long a request may take: the ones after it wait for it.
  static const _timeout = Duration(seconds: 10);

  /// When the next request may go.
  Future<void> _turn = Future.value();

  /// What MusicBrainz has of each album looked up, by the album's id, for the session: an album opened again asks
  /// nothing.
  final _found = <String, Future<_Found>>{};

  /// Each band looked up, by its MusicBrainz id, for the session.
  final _bands = <String, Future<Band?>>{};

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

  /// What MusicBrainz knows of [artist] as a band, by their MusicBrainz id: the years they have been together, and,
  /// for a group, their members (not an orchestra's or a choir's, which would be a crowd). A person's years in
  /// MusicBrainz are those of their life, not of their music. None for an artist without that id, a person (or one
  /// MusicBrainz doesn't know as a band), a band MusicBrainz knows neither of, and when it fails.
  Future<Band?> band(Artist artist) async {
    final id = artist.musicBrainzId;

    if (id == null) {
      return null;
    }

    try {
      return await (_bands[id] ??= _band(id));
    } on Object {
      // To try again the next time.
      _bands.remove(id);
      return null;
    }
  }

  /// The band whose MusicBrainz id is [id]: its years, from its life span, and its members, from its relations.
  Future<Band?> _band(String id) async {
    final found = await _get('artist/${Uri.encodeComponent(id)}', const {'inc': 'artist-rels'});

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
