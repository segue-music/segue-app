import 'dart:math';

import 'l10n/app_localizations.dart';
import 'server/models.dart';
import 'server/server.dart';

/// A mix: songs of the library at random ([MediaServer.randomSongs]), of a genre or of a decade, a different few each
/// time.
sealed class Mix {
  const Mix();

  /// How many songs a mix plays: hours of them, after which autoplay goes on with songs like the last.
  static const size = 100;

  /// Its songs, [size] at most, at random.
  Future<List<Song>> songs(MediaServer server, {int size = size});

  /// What it plays: [first] (the songs its tile shows), then more of its own, each song once, [size] in all.
  Future<List<Song>> queue(MediaServer server, {List<Song> first = const []}) async {
    final ids = {for (final song in first) song.id};

    return [
      ...first,
      for (final song in await songs(server))
        if (ids.add(song.id)) song,
    ].take(size).toList();
  }
}

/// What [mix] is called: its genre's name, or its decade's ("Anos 80").
String mixName(AppLocalizations strings, Mix mix) => switch (mix) {
  GenreMix(:final genre) => genre.name,
  DecadeMix(:final decade) => strings.decade('$decade'),
};

class GenreMix extends Mix {
  const GenreMix(this.genre);

  final Genre genre;

  @override
  Future<List<Song>> songs(MediaServer server, {int size = Mix.size}) =>
      server.randomSongs(size: size, genre: genre.id);
}

class DecadeMix extends Mix {
  const DecadeMix(this.decade);

  /// The decade's first year: 1980 for the 1980s.
  final int decade;

  @override
  Future<List<Song>> songs(MediaServer server, {int size = Mix.size}) =>
      server.randomSongs(size: size, years: (from: decade, to: decade + 9));
}

/// The mixes the home suggests, and the first songs of each, which its tile shows and it plays first, and the artist of
/// the first, whose picture it shows: asked for once, as the tile first shows, and the same until the home loads again.
class SuggestedMixes {
  // Its failure is the row's, which takes it up as it's built: not one of the zone's, should the home load again, as
  // pulled down, before the row is built anew.
  SuggestedMixes(this._server, {Random? random}) : mixes = _suggested(_server, random ?? Random())..ignore();

  final MediaServer _server;

  /// Of the genres the user plays most, two, then of a decade they play most, and so on; before anything has played,
  /// of the genres with the most albums alone. Picked at random among more of them, one after another, each the likelier
  /// the more the user plays it ([_pickedByRank]): another few, in another order, each time the home loads, the
  /// favorites mostly among them, and first. None where the library has no genres.
  final Future<List<Mix>> mixes;

  final _firstSongs = <Mix, Future<List<Song>>>{};
  final _firstArtists = <Mix, Future<Artist?>>{};

  /// How many songs of a mix its tile has: enough to name a few artists, and that there are more.
  static const firstSize = 12;

  /// How many mixes of genres there are at most, and of decades.
  static const _genres = 6;
  static const _decades = 3;

  /// How many of the genres the user plays most, and of the decades, the mixes are picked among.
  static const _genresToPickFrom = 12;
  static const _decadesToPickFrom = 6;

  /// The first songs of [mix], one of [mixes].
  Future<List<Song>> firstSongs(Mix mix) => _firstSongs[mix] ??= mix.songs(_server, size: firstSize);

  /// The artist of the first song of [mix], as the server has them, with their picture; null where it has no songs, the
  /// song has no artist's id, or the server can't say.
  Future<Artist?> firstArtist(Mix mix) => _firstArtists[mix] ??= _askFirstArtist(mix);

  Future<Artist?> _askFirstArtist(Mix mix) async {
    try {
      final id = (await firstSongs(mix)).firstOrNull?.artistId;
      return id == null ? null : (await _server.artist(id)).$1;
    } on Object {
      return null;
    }
  }

  static Future<List<Mix>> _suggested(MediaServer server, Random random) async {
    // A mix of a decade is a suggestion more, which the genres' go without where the server can't say.
    final decades = server.mostPlayedDecades(size: _decadesToPickFrom).catchError((_) => const <int>[]);
    var genres = await server.mostPlayedGenres(size: _genresToPickFrom);

    if (genres.isEmpty) {
      // Those the server doesn't say how many albums of, last; not those of none, which a server may list for their
      // songs alone, as the genres tab doesn't.
      genres = [
        for (final genre in await server.genres())
          if (genre.albumCount != 0) genre,
      ]..sort((a, b) => (b.albumCount ?? 0).compareTo(a.albumCount ?? 0));
    }

    final genreMixes = [
      for (final genre in _pickedByRank(genres.take(_genresToPickFrom).toList(), _genres, random)) GenreMix(genre),
    ];
    final decadeMixes = [for (final decade in _pickedByRank(await decades, _decades, random)) DecadeMix(decade)];

    return [
      for (var i = 0; i < genreMixes.length || i ~/ 2 < decadeMixes.length; i += 2) ...[
        ...genreMixes.skip(i).take(2),
        if (i ~/ 2 < decadeMixes.length) decadeMixes[i ~/ 2],
      ],
    ];
  }

  /// [count] of [ranked], the first the user's favorite, picked at random one after another, in that order: each the
  /// likelier the higher it ranks, the first twice as likely as the middle one, and the last of 12 one in 78 to come
  /// first.
  static List<T> _pickedByRank<T>(List<T> ranked, int count, Random random) {
    final left = [...ranked];
    final weights = [for (var i = 0; i < ranked.length; i++) ranked.length - i];
    final picked = <T>[];

    while (picked.length < count && left.isNotEmpty) {
      var at = random.nextInt(weights.fold(0, (sum, weight) => sum + weight));
      var i = 0;

      while (at >= weights[i]) {
        at -= weights[i];
        i++;
      }

      picked.add(left.removeAt(i));
      weights.removeAt(i);
    }

    return picked;
  }
}
