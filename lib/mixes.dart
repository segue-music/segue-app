import 'dart:math';

import 'l10n/app_localizations.dart';
import 'pictures/fanart_tv.dart';
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

/// An artist whose picture a mix's tile shows: the media server's ([Artist.coverArt]), or else fanart.tv's ([picture]).
typedef MixPicture = ({Artist artist, Uri? picture});

/// The mixes the home suggests, and the first songs of each, which its tile shows and it plays first, and the first of
/// their artists with a picture, which it shows: asked for once, as the tile first shows, and the same until the home
/// loads again.
class SuggestedMixes {
  // Its failure is the row's, which takes it up as it's built: not one of the zone's, should the home load again, as
  // pulled down, before the row is built anew.
  SuggestedMixes(this._server, {Random? random, this._fanartTv})
    : mixes = _suggested(_server, random ?? Random())..ignore();

  final MediaServer _server;

  /// Where an artist's picture comes from where the server has none; with none, the server's alone.
  final FanartTv? _fanartTv;

  /// Of the genres the user plays most, two, then of a decade they play most, and so on; before anything has played,
  /// of the genres with the most albums alone. Picked at random among more of them, one after another, each the likelier
  /// the more the user plays it ([_pickedByRank]): another few, in another order, each time the home loads, the
  /// favorites mostly among them, and first. None where the library has no genres.
  final Future<List<Mix>> mixes;

  final _firstSongs = <Mix, Future<List<Song>>>{};
  final _pictures = <Mix, Future<MixPicture?>>{};

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

  /// The first artist of [mix]'s first songs, in the order they play, who has a picture, the server's or else
  /// fanart.tv's: one after another, each asked for as the one before has none. Null where none has one (nor their ids,
  /// nor the server, can say).
  Future<MixPicture?> picture(Mix mix) => _pictures[mix] ??= _findPicture(mix);

  Future<MixPicture?> _findPicture(Mix mix) async {
    final List<Song> songs;

    try {
      songs = await firstSongs(mix);
    } on Object {
      return null;
    }

    for (final id in {for (final song in songs) ?song.artistId}) {
      final Artist artist;

      try {
        (artist, _) = await _server.artist(id);
      } on Object {
        continue; // one the server can't say, as the next may be
      }

      if (artist.coverArt != null) {
        return (artist: artist, picture: null);
      }

      // None for one fanart.tv fails at: the next.
      if ((await _fanartTv?.artistPictures(artist))?.firstOrNull case final picture?) {
        return (artist: artist, picture: picture);
      }
    }

    return null;
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
