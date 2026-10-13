import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';

import '../l10n/app_localizations.dart';
import '../mixes.dart';
import '../server/favorites.dart';
import '../server/models.dart';
import '../server/server.dart';

/// The user's music as the system's media browsers find it: Android Auto, in the car. A tree of [MediaItem]s by their
/// ids, at its root ([AudioService.browsableRootId]) four tabs: the home (its mixes, which play at once, and its rows
/// of albums), the playlists (the favorite songs first), the albums and the artists, by name. An album, a playlist and
/// an artist open their songs, or albums, and a song plays its album or playlist from it ([queueOf]). Also what a search
/// finds, typed in the car ([search]) or said to it ([queueForVoice]).
class BrowseTree {
  BrowseTree(
    this._server, {
    required this.strings,
    required this.coverUri,
    this.favorites,
    this.offline = _reachable,
    Random? random,
  }) : _random = random ?? Random();

  final MediaServer _server;

  /// The app's words, in the language it shows.
  final AppLocalizations Function() strings;

  /// Where the car reads the cover whose id it is given, or null for none: it can't read the app's files, nor ought it
  /// to have the media server's address of one, which carries the login.
  final Uri? Function(String? coverId) coverUri;

  /// The user's favorites, whose songs head the playlists; none in tests.
  final Favorites? favorites;

  /// Whether the media server is out of reach: the home then has the downloaded albums alone, as the app's does.
  final bool Function() offline;

  final Random _random;

  /// The home's mixes, the same until the app signs in again, as the ids of their items go by their places.
  SuggestedMixes? _mixes;

  static bool _reachable() => false;

  /// The tabs, at the root.
  static const home = 'home';
  static const playlists = 'playlists';
  static const albums = 'albums';
  static const artists = 'artists';

  /// The favorite songs, first among the playlists.
  static const favoriteSongs = 'favorites';

  /// How the car lays out the tree, and that it searches it, as its root says (androidx.media's MediaConstants): what
  /// opens (albums, playlists, artists) in a grid of their pictures, and the songs in a list.
  static const rootExtras = {
    'android.media.browse.SEARCH_SUPPORTED': true,
    'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 2,
    'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 1,
  };

  /// The key of the title of a group of items in a list, which the car shows over them (androidx.media's
  /// MediaConstants): each item of the group has it, the group's items together.
  static const _groupTitle = 'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';

  /// How many albums each of the home's rows has: a few, for a glance while driving.
  static const _rowSize = 12;

  /// How many items a list has at most: more would go beyond what Android hands from one app to another at once.
  static const _listSize = 500;

  /// The home's rows of albums, in order.
  static const _rows = [AlbumOrder.released, AlbumOrder.mostPlayed, AlbumOrder.latest];

  /// How many of a mix's first songs' artists its item names, before "and more".
  static const _artistsNamed = 3;

  /// What Android tells of what was said (MediaStore's keys), and of what it took it for ([_focus]).
  static const _focusKey = 'android.intent.extra.focus';
  static const _artistKey = 'android.intent.extra.artist';
  static const _albumKey = 'android.intent.extra.album';
  static const _titleKey = 'android.intent.extra.title';
  static const _playlistKey = 'android.intent.extra.playlist';
  static const _genreKey = 'android.intent.extra.genre';

  /// What Android took what was said for: an artist, an album, a song, a playlist, a genre (MediaStore's types).
  static const _artistFocus = 'vnd.android.cursor.item/artist';
  static const _albumFocus = 'vnd.android.cursor.item/album';
  static const _songFocus = 'vnd.android.cursor.item/audio';
  static const _playlistFocus = 'vnd.android.cursor.item/playlist';
  static const _genreFocus = 'vnd.android.cursor.item/genre';

  /// The items under the one whose id is [parent]; none under one that has nothing (a song, an id of another tree).
  Future<List<MediaItem>> children(String parent) async => switch (_parts(parent)) {
    [AudioService.browsableRootId] => _tabs(),
    [home] => await _home(),
    [playlists] => await _playlists(),
    [albums] => [for (final album in await _server.albums(order: AlbumOrder.name, size: _listSize)) _album(album)],
    [artists] => [for (final artist in (await _server.artists()).take(_listSize)) _artist(artist)],
    [favoriteSongs] => _songs([favoriteSongs], await _favoriteSongs()),
    ['album', final id] => await _albumItems(id),
    ['playlist', final id] => _songs(['playlist', id], (await _server.playlist(id)).$2),
    ['artist', final id] => await _artistItems(id),
    _ => const [],
  };

  /// The songs the item whose id is [id] plays, and which of them first: a song of an album, of a playlist or of the
  /// favorite ones, which plays them from it; a mix; an album's or an artist's radio; a song found, alone (autoplay goes
  /// on after it). Null for an item that plays nothing (a tab, an album), or one the tree no longer has.
  Future<(List<Song>, int)?> queueOf(String id) async {
    switch (_parts(id)) {
      case ['radio', 'album', final album]:
        return _radio(AlbumRadio((await _server.album(album)).$1));
      case ['radio', 'artist', final artist]:
        // Asked for by their id alone.
        return _radio(ArtistRadio(Artist(id: artist, name: '')));
      case ['album', final album, final index]:
        return _at((await _server.album(album)).$2, index);
      case ['playlist', final playlist, final index]:
        return _at((await _server.playlist(playlist)).$2, index);
      case [favoriteSongs, final index]:
        return _at(favorites?.songs ?? const [], index);
      case ['mix', final index]:
        return _mix(int.tryParse(index));
      case ['song', final song]:
        return ([await _server.song(song)], 0);
    }

    return null;
  }

  /// What a search typed in the car finds: songs, which play alone, then albums and artists, which open, each under its
  /// title.
  Future<List<MediaItem>> search(String query) async {
    final strings = this.strings();
    final found = await _server.search(query, artists: 5, albums: 10, songs: 30);

    return [
      for (final song in found.songs) _song(_id(['song', song.id]), song, group: strings.songs),
      for (final album in found.albums) _album(album, group: strings.albums),
      for (final artist in found.artists) _artist(artist, group: strings.artists),
    ];
  }

  /// The songs to play for what was said to the car ("Ok Google, toca Aerosmith no Segue"): [query], and what Android
  /// made of it, in [extras]. A playlist or a genre plays when said as one; an album, an artist or a song, when said as
  /// one or when the words name it exactly, and otherwise the song they find first, then the artist, then the album:
  /// an album or a playlist in order, an artist's songs mixed. Null where it finds nothing, and where nothing was said
  /// ("toca música"), which [anything] answers.
  Future<(List<Song>, int)?> queueForVoice(String query, [Map<String, dynamic>? extras]) async {
    String? said(String key) => switch (extras?[key]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };

    final focus = said(_focusKey);
    final (artist, album, title) = (said(_artistKey), said(_albumKey), said(_titleKey));
    final words = query.trim();

    if (focus == _playlistFocus || said(_playlistKey) != null) {
      return _playlistNamed(said(_playlistKey) ?? words);
    }

    if (focus == _genreFocus || said(_genreKey) != null) {
      return _genreNamed(said(_genreKey) ?? words);
    }

    if (focus == _albumFocus || (album != null && title == null)) {
      return _albumNamed(album ?? words, by: artist);
    }

    if (focus == _artistFocus || (artist != null && title == null)) {
      return _artistNamed(artist ?? words);
    }

    if (focus == _songFocus || title != null) {
      return _songNamed(title ?? words, by: artist);
    }

    if (words.isEmpty) {
      return null;
    }

    final found = await _server.search(words, artists: 5, albums: 5, songs: 20);

    if (found.artists.where((artist) => _same(artist.name, words)).firstOrNull case final artist?) {
      return _artistSongs(artist);
    }

    if (found.albums.where((album) => _same(album.name, words)).firstOrNull case final album?) {
      return _albumSongs(album);
    }

    if (found.songs.isNotEmpty) {
      return ([found.songs.firstWhere((song) => _same(song.title, words), orElse: () => found.songs.first)], 0);
    }

    if (found.artists.firstOrNull case final artist?) {
      return _artistSongs(artist);
    }

    return switch (found.albums.firstOrNull) {
      final album? => _albumSongs(album),
      null => null,
    };
  }

  /// Whether nothing to play was said ("toca música"): no words, nor anything Android made of them ([queueForVoice]).
  static bool saysNothing(String query, [Map<String, dynamic>? extras]) =>
      query.trim().isEmpty &&
      [_artistKey, _albumKey, _titleKey, _playlistKey, _genreKey].every(
        (key) => switch (extras?[key]) {
          final String value => value.trim().isEmpty,
          _ => true,
        },
      );

  /// Something to play, for "toca música" with nothing to go on: songs of the library at random.
  Future<(List<Song>, int)?> anything() async {
    final songs = await _server.randomSongs(size: Mix.size);

    return songs.isEmpty ? null : (songs, 0);
  }

  List<MediaItem> _tabs() {
    final strings = this.strings();

    return [
      MediaItem(id: home, title: strings.home, playable: false),
      MediaItem(id: playlists, title: strings.playlists, playable: false),
      MediaItem(id: albums, title: strings.albums, playable: false),
      MediaItem(id: artists, title: strings.artists, playable: false),
    ];
  }

  /// The mixes, then the rows of albums, each album in the first row that has it, as the app's home; out of reach, the
  /// downloaded albums alone.
  Future<List<MediaItem>> _home() async {
    final strings = this.strings();

    if (offline()) {
      final downloaded = await _server.albums(order: AlbumOrder.latest, size: _rowSize);
      return [for (final album in downloaded) _album(album, group: strings.downloadedAlbums)];
    }

    final mixes = _mixes ??= SuggestedMixes(_server, random: _random);
    // Each part says nothing where it fails, as the home's rows do.
    final (suggested, rows) = await (
      mixes.mixes.catchError((Object _) => const <RandomMix>[]),
      Future.wait([
        for (final order in _rows)
          _server.albums(order: order, size: _rowSize).catchError((Object _) => const <Album>[]),
      ]),
    ).wait;
    final first = await Future.wait([
      for (final mix in suggested) mixes.firstSongs(mix).catchError((Object _) => const <Song>[]),
    ]);
    final shown = <String>{};

    return [
      for (final (i, mix) in suggested.indexed)
        MediaItem(
          id: _id(['mix', '$i']),
          title: mixName(strings, mix),
          artist: _artistsOf(strings, first[i]),
          artUri: coverUri(first[i].firstOrNull?.coverArt),
          playable: true,
          extras: {_groupTitle: strings.mixes},
        ),
      for (final (i, order) in _rows.indexed)
        for (final album in rows[i])
          if (shown.add(album.id)) _album(album, group: _rowTitle(strings, order)),
    ];
  }

  /// The favorite songs, where the user has any, then the playlists, by name.
  Future<List<MediaItem>> _playlists() async {
    final (found, favorite) = await (_server.playlists(), _favoriteSongs()).wait;
    found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return [
      if (favorite.isNotEmpty)
        MediaItem(
          id: favoriteSongs,
          title: strings().favoriteSongs,
          artUri: coverUri(favorite.first.coverArt),
          playable: false,
        ),
      for (final playlist in found)
        MediaItem(
          id: _id(['playlist', playlist.id]),
          title: playlist.name,
          artUri: coverUri(playlist.coverArt),
          playable: false,
        ),
    ];
  }

  /// The favorite songs as the server has them now; none where it can't say.
  Future<List<Song>> _favoriteSongs() async {
    final favorites = this.favorites;

    if (favorites == null) {
      return const [];
    }

    await favorites.load().catchError((Object _) {});

    return favorites.songs;
  }

  /// The mix at [index] of the home's: its first songs, which its item shows, then more of its own.
  Future<(List<Song>, int)?> _mix(int? index) async {
    final mixes = _mixes;
    final mix = index == null ? null : (await mixes?.mixes)?.elementAtOrNull(index);

    if (mixes == null || mix == null) {
      return null;
    }

    final first = await mixes.firstSongs(mix).catchError((Object _) => const <Song>[]);
    final songs = await mix.queue(_server, first: first);

    return songs.isEmpty ? null : (songs, 0);
  }

  /// [radio]'s songs, from the first.
  Future<(List<Song>, int)?> _radio(RadioMix radio) async {
    final songs = await radio.queue(_server);

    return songs.isEmpty ? null : (songs, 0);
  }

  /// The playlist named [name], or else the first whose name has it.
  Future<(List<Song>, int)?> _playlistNamed(String name) async {
    final all = await _server.playlists();
    final playlist =
        all.where((playlist) => _same(playlist.name, name)).firstOrNull ??
        all.where((playlist) => playlist.name.toLowerCase().contains(name.toLowerCase())).firstOrNull;

    if (playlist == null) {
      return null;
    }

    final songs = (await _server.playlist(playlist.id)).$2;

    return songs.isEmpty ? null : (songs, 0);
  }

  /// The mix of the genre named [name].
  Future<(List<Song>, int)?> _genreNamed(String name) async {
    final genre = (await _server.genres()).where((genre) => _same(genre.name, name)).firstOrNull;

    if (genre == null) {
      return null;
    }

    final songs = await GenreMix(genre).queue(_server);

    return songs.isEmpty ? null : (songs, 0);
  }

  /// The album [name] finds, [by] that artist where said. (A search asks for one at least of what it needn't: Jellyfin
  /// may take none for all.)
  Future<(List<Song>, int)?> _albumNamed(String name, {String? by}) async {
    final found = (await _server.search(name, artists: 1, albums: 10, songs: 1)).albums;
    final album =
        found.where((album) => by != null && _has(album.artist, by)).firstOrNull ??
        found.where((album) => _same(album.name, name)).firstOrNull ??
        found.firstOrNull;

    return album == null ? null : _albumSongs(album);
  }

  /// The artist [name] finds.
  Future<(List<Song>, int)?> _artistNamed(String name) async {
    final found = (await _server.search(name, artists: 5, albums: 1, songs: 1)).artists;
    final artist = found.where((artist) => _same(artist.name, name)).firstOrNull ?? found.firstOrNull;

    return artist == null ? null : _artistSongs(artist);
  }

  /// The song [title] finds, [by] that artist where said, alone.
  Future<(List<Song>, int)?> _songNamed(String title, {String? by}) async {
    final found = (await _server.search(title, artists: 1, albums: 1, songs: 20)).songs;
    final song =
        found.where((song) => by != null && _has(song.artist, by)).firstOrNull ??
        found.where((song) => _same(song.title, title)).firstOrNull ??
        found.firstOrNull;

    return song == null ? null : ([song], 0);
  }

  Future<(List<Song>, int)?> _albumSongs(Album album) async {
    final songs = (await _server.album(album.id)).$2;

    return songs.isEmpty ? null : (songs, 0);
  }

  /// The songs of [artist]'s albums, mixed: [Mix.size] of them at most.
  Future<(List<Song>, int)?> _artistSongs(Artist artist) async {
    final albums = (await _server.artist(artist.id)).$2;
    final songs = [
      for (final album in await Future.wait([for (final album in albums) _server.album(album.id)])) ...album.$2,
    ]..shuffle(_random);

    return songs.isEmpty ? null : (songs.take(Mix.size).toList(), 0);
  }

  MediaItem _album(Album album, {String? group}) => MediaItem(
    id: _id(['album', album.id]),
    title: album.name,
    artist: album.artist,
    artUri: coverUri(album.coverArt),
    playable: false,
    extras: group == null ? null : {_groupTitle: group},
  );

  MediaItem _artist(Artist artist, {String? group}) => MediaItem(
    id: _id(['artist', artist.id]),
    title: artist.name,
    artUri: coverUri(artist.coverArt),
    playable: false,
    extras: group == null ? null : {_groupTitle: group},
  );

  /// An album's radio, which plays, then its songs: the car makes an item either play or open, never both.
  Future<List<MediaItem>> _albumItems(String id) async {
    final (album, songs) = await _server.album(id);

    return [
      _radioItem(AlbumRadio(album), ['radio', 'album', id], album.coverArt),
      ..._songs(['album', id], songs),
    ];
  }

  /// An artist's radio, which plays, then their albums, which open.
  Future<List<MediaItem>> _artistItems(String id) async {
    final (artist, albums) = await _server.artist(id);

    return [
      _radioItem(ArtistRadio(artist), ['radio', 'artist', id], artist.coverArt),
      for (final album in albums) _album(album),
    ];
  }

  MediaItem _radioItem(RadioMix radio, List<String> parts, String? cover) =>
      MediaItem(id: _id(parts), title: mixName(strings(), radio), artUri: coverUri(cover), playable: true);

  /// [songs] as the items of the list whose id's parts are [list], each by its place in it.
  List<MediaItem> _songs(List<String> list, List<Song> songs) => [
    for (final (i, song) in songs.indexed) _song(_id([...list, '$i']), song),
  ];

  MediaItem _song(String id, Song song, {String? group}) => MediaItem(
    id: id,
    title: song.title,
    artist: song.artist,
    album: song.album,
    duration: song.duration,
    artUri: coverUri(song.coverArt),
    playable: true,
    extras: group == null ? null : {_groupTitle: group},
  );

  /// The artists of a mix's first [songs], each once, in the order they play: the first few, and that there are more.
  static String _artistsOf(AppLocalizations strings, List<Song> songs) {
    final artists = {
      for (final song in songs)
        if (song.artist case final artist? when artist.isNotEmpty) artist,
    };
    final named = artists.take(_artistsNamed).join(', ');

    return artists.length > _artistsNamed ? strings.mixArtists(named) : named;
  }

  /// The title of the home's row of albums in [order], as the app's home names it.
  static String _rowTitle(AppLocalizations strings, AlbumOrder order) => switch (order) {
    AlbumOrder.released => strings.orderReleased,
    AlbumOrder.mostPlayed => strings.mostPlayed,
    AlbumOrder.latest => strings.orderLatest,
    AlbumOrder.name => strings.orderName,
  };

  /// [songs] from the one at [index], where it has one there.
  static (List<Song>, int)? _at(List<Song> songs, String index) {
    final i = int.tryParse(index);

    return i == null || i < 0 || i >= songs.length ? null : (songs, i);
  }

  /// An item's id, of [parts]: what it is, the server's id, its place in a list. Each part goes as it is, but for a
  /// slash, which parts the id.
  static String _id(List<String> parts) => [for (final part in parts) Uri.encodeComponent(part)].join('/');

  /// The parts of the id [id] ([_id]); none for one of another tree.
  static List<String> _parts(String id) {
    try {
      return [for (final part in id.split('/')) Uri.decodeComponent(part)];
    } on ArgumentError {
      return const [];
    }
  }

  /// Whether [a] and [b] are the same name, but for case and the spaces around them.
  static bool _same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Whether [name] (an artist's, several apart by semicolons) has [part] in it, but for case.
  static bool _has(String? name, String part) => name?.toLowerCase().contains(part.toLowerCase()) ?? false;
}
