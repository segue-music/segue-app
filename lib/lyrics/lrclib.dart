import 'dart:convert';

import 'package:http/http.dart' as http;

import '../server/models.dart';
import '../server/server.dart';

/// LRCLIB (lrclib.net), a free database of lyrics, synced ones mostly: where they come from when the media
/// server has none. It knows songs by their title, artist, album and length.
class Lrclib {
  Lrclib({http.Client? client, Uri? base})
    : _http = client ?? http.Client(),
      _base = base ?? Uri.parse('https://lrclib.net/');

  final http.Client _http;
  final Uri _base;

  /// LRCLIB asks apps to say who they are.
  static const _userAgent = '$clientName $appVersion (https://github.com/segue-music/segue-app)';

  /// How far from the song's length another of the same title can be and still be taken for it: LRCLIB has
  /// some songs twice, from an album and from a single a few seconds longer, with synced lyrics in one only.
  static const _lengthSlack = Duration(seconds: 5);

  /// The lyrics of the song [title] by [artist], synced ones wherever LRCLIB has them: of the song it has
  /// by these, with its [album] and [duration] too when known, or else of another of that title by that
  /// artist that lasts about as long. Plain ones only when none of these has synced ones. An instrumental
  /// is a part with no singing, from its start. Null when LRCLIB has none.
  Future<Lyrics?> find({required String title, required String artist, String? album, Duration? duration}) async {
    final exact = await _get('api/get', {
      'track_name': title,
      'artist_name': artist,
      'album_name': ?album,
      'duration': ?duration?.inSeconds.toString(),
    });
    final song = exact is Map<String, dynamic> ? exact : null;

    if (song != null && _timed(song)) {
      return _lyrics(song);
    }

    final found = await _get('api/search', {'track_name': title, 'artist_name': artist});
    final others = [
      for (final other in found is List ? found : const [])
        if (other is Map<String, dynamic> && _same(other, title, duration)) other,
    ];
    // Synced ones first, from any of them; then the plain ones of the song, or else of another.
    return [...others.where(_timed), ?song, ...others].map(_lyrics).nonNulls.firstOrNull;
  }

  /// Whether [song] has synced lyrics, or is an instrumental, whose silence is timed too.
  static bool _timed(Map<String, dynamic> song) =>
      song['instrumental'] == true || (song['syncedLyrics'] as String? ?? '').trim().isNotEmpty;

  /// Whether [song] is [title] (not a live or an acoustic one, say), lasting about as long as [duration].
  static bool _same(Map<String, dynamic> song, String title, Duration? duration) {
    final name = song['trackName'] as String? ?? '';
    final length = song['duration'] as num?;
    return name.trim().toLowerCase() == title.trim().toLowerCase() &&
        (duration == null ||
            length == null ||
            (Duration(milliseconds: (length * 1000).round()) - duration).abs() <= _lengthSlack);
  }

  /// A song's lyrics: synced where LRCLIB has them so, else plain.
  static Lyrics? _lyrics(Map<String, dynamic> song) {
    if (song['instrumental'] == true) {
      return const Lyrics([LyricLine('', start: Duration.zero)], provider: 'LRCLIB');
    }

    final synced = parseLrc(song['syncedLyrics'] as String? ?? '');
    final lines = synced.isNotEmpty
        ? synced
        : [
            for (final line in const LineSplitter().convert(song['plainLyrics'] as String? ?? ''))
              LyricLine(line.trim()),
          ];
    return lines.isEmpty ? null : Lyrics(lines, provider: 'LRCLIB');
  }

  /// The JSON at [path], or null for a 404: none there.
  Future<Object?> _get(String path, Map<String, String> query) async {
    final response = await _http.get(
      _base.resolve(path).replace(queryParameters: query),
      headers: {'User-Agent': _userAgent},
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw ServerError('LRCLIB: HTTP ${response.statusCode}');
    }

    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  void close() => _http.close();
}

/// The timed lines of lyrics in LRC: "[mm:ss.xx] text", a line with several times coming at each, in the
/// order they start. Its offset tag shifts them all, a positive one sooner. Lines with no time, as the
/// other tags, are left out.
List<LyricLine> parseLrc(String lrc) {
  final time = RegExp(r'^\[(\d+):(\d+(?:\.\d+)?)\]');
  final offset = RegExp(r'^\[offset:\s*([+-]?\d+)\]', caseSensitive: false);
  var shift = Duration.zero;
  final lines = <LyricLine>[];

  for (var line in const LineSplitter().convert(lrc)) {
    line = line.trim();

    if (offset.firstMatch(line) case final match?) {
      shift = Duration(milliseconds: int.parse(match[1]!));
      continue;
    }

    final starts = <Duration>[];

    for (var match = time.firstMatch(line); match != null; match = time.firstMatch(line)) {
      starts.add(Duration(milliseconds: (int.parse(match[1]!) * 60000 + double.parse(match[2]!) * 1000).round()));
      line = line.substring(match.end);
    }

    for (final start in starts) {
      lines.add(LyricLine(line.trim(), start: start));
    }
  }

  lines.sort((a, b) => a.start!.compareTo(b.start!));
  return [for (final line in lines) LyricLine(line.text, start: line.start! - shift)];
}
