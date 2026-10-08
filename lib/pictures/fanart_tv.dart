import 'dart:convert';

import 'package:http/http.dart' as http;

import '../server/models.dart';
import '../server/server.dart';

/// The app's key for fanart.tv, which it gives each project that asks it for pictures: FANART_TV_KEY, given as the app
/// is built (keys.json, which tool/flutter.sh passes on), out of git; empty in a build without it.
const fanartTvKey = String.fromEnvironment('FANART_TV_KEY');

/// fanart.tv, a site of pictures of artists (and of films and series) that its users send in and like: where more
/// pictures of an artist than the media server's one come from, by the artist's MusicBrainz id.
class FanartTv {
  FanartTv({required this.apiKey, http.Client? client, Uri? base})
    : _http = client ?? http.Client(),
      _base = base ?? Uri.parse('https://webservice.fanart.tv/v3/');

  /// What it asks with: the app's ([fanartTvKey]).
  final String apiKey;

  final http.Client _http;
  final Uri _base;

  /// Who asks: the app, and where to reach whoever makes it.
  static const _userAgent = '$clientName/$appVersion ( https://github.com/segue-music/segue-app )';

  /// How long a request may take.
  static const _timeout = Duration(seconds: 10);

  /// Each artist's pictures, by their MusicBrainz id, for the session: a biography opened again asks nothing.
  final _pictures = <String, Future<List<Uri>>>{};

  /// Pictures of [artist], by their MusicBrainz id: fanart.tv's square ones (its artist thumbs, 1000 pixels a side),
  /// those its users like most first. None for an artist without that id, one fanart.tv has none of, and when it fails
  /// (asked again the next time).
  Future<List<Uri>> artistPictures(Artist artist) async {
    final id = artist.musicBrainzId;

    if (id == null) {
      return const [];
    }

    try {
      return await (_pictures[id] ??= _lookUp(id));
    } on Object {
      _pictures.remove(id);
      return const [];
    }
  }

  /// The artist thumbs fanart.tv has of the artist whose MusicBrainz id is [id], the most liked first.
  Future<List<Uri>> _lookUp(String id) async {
    final response = await _http
        .get(
          _base.resolve('music/${Uri.encodeComponent(id)}').replace(queryParameters: {'api_key': apiKey}),
          headers: {'User-Agent': _userAgent},
        )
        .timeout(_timeout);

    // An artist it has nothing of: an empty object, or a 404.
    if (response.statusCode == 404) {
      return const [];
    }

    if (response.statusCode != 200) {
      throw ServerError('fanart.tv: HTTP ${response.statusCode}');
    }

    final likes = <Uri, int>{
      if (jsonDecode(utf8.decode(response.bodyBytes)) case {'artistthumb': final List<Object?> thumbs})
        for (final thumb in thumbs)
          if (thumb case {'url': final String url} when Uri.tryParse(url) != null)
            _secure(Uri.parse(url)): int.tryParse('${thumb['likes']}') ?? 0,
    };
    return rankedByCount(likes);
  }

  /// [url] over HTTPS: fanart.tv gave its older pictures over HTTP, which Android and iOS refuse.
  static Uri _secure(Uri url) => url.isScheme('http') ? url.replace(scheme: 'https') : url;

  void close() => _http.close();
}
