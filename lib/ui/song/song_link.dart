import 'dart:async';

import 'package:flutter/material.dart';

import '../../connect/connect.dart';
import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../album/album_page.dart';
import '../app/page_area.dart';
import '../artist/artist_link.dart';
import '../artist/artist_page.dart';
import '../widgets/text_link.dart';

/// The title or the album of the song that plays, a link to the album, or its artists, each a link to
/// their page ([ArtistLinks]): underlined under the mouse, and tinted under the focus as everything
/// else is. A song without an id in this device's API (one the hub couldn't translate) links nowhere.
class SongLink extends StatefulWidget {
  /// The song's title, which opens its album.
  const SongLink.title(this.now, {this.style, this.maxLines = 1, this.textAlign, this.replace = false, super.key})
    : _part = _Part.title;

  /// The name of the song's album, which opens it.
  const SongLink.album(this.now, {this.style, this.maxLines = 1, this.textAlign, this.replace = false, super.key})
    : _part = _Part.album;

  /// The song's artists, each of whom opens their page, in one line.
  const SongLink.artist(this.now, {this.style, this.textAlign, this.replace = false, super.key})
    : _part = _Part.artist,
      maxLines = 1;

  final NowPlaying now;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  /// Whether the page goes in place of the current one (the full-screen player), rather than over it.
  final bool replace;

  final _Part _part;

  @override
  State<SongLink> createState() => _SongLinkState();
}

/// What a [SongLink] shows of the song.
enum _Part { title, album, artist }

class _SongLinkState extends State<SongLink> {
  /// The song, by its id, as the media server gives it, for its artists where [NowPlaying.artists] has none: another
  /// device's, which the hub names without their ids, or one the hub sent here.
  (String, Future<Song>)? _song;

  /// The song of [now] from the media server, asked once for each song; null where its artists are known, or it has no
  /// id to ask by.
  Future<Song>? _songOf(NowPlaying now) {
    final id = now.songId;

    if (widget._part != _Part.artist || now.artists.isNotEmpty || id == null) {
      return null;
    }

    if (_song case (final asked, final song) when asked == id) {
      return song;
    }

    final song = ServicesScope.of(context).api.song(id);
    _song = (id, song);

    return song;
  }

  /// Opens the album or the first artist, or says why it can't. The song comes from the media server: the
  /// hub gives other devices' songs without their album's and artist's ids.
  Future<void> _open(String songId) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppLocalizations.of(context);
    Widget? page;
    Object? error;

    try {
      final song = await ServicesScope.of(context).api.song(songId);
      page = switch ((widget._part, song)) {
        (_Part.artist, Song(artists: [final artist, ...])) => ArtistPage(artist),
        (_Part.title || _Part.album, Song(albumId: final id?)) => AlbumPage(Album(id: id, name: song.album ?? '')),
        _ => null,
      };
    } on Object catch (failure) {
      error = failure;
    }

    // The song stopped showing meanwhile, as when the player closed.
    if (!mounted) {
      return;
    }

    if (page != null) {
      _show(page);
      return;
    }

    final message = switch ((widget._part, error)) {
      (_Part.artist, null) => strings.couldNotOpenArtist,
      (_Part.artist, final error?) => strings.couldNotOpenArtistError('$error'),
      (_, null) => strings.couldNotOpenAlbum,
      (_, final error?) => strings.couldNotOpenAlbumError('$error'),
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens [page] over the current one, or in its place where [SongLink.replace] says so.
  void _show(Widget page) {
    final route = MaterialPageRoute<void>(builder: (_) => page);
    final navigator = PageArea.navigatorOf(context);
    final player = Navigator.of(context);

    if (!widget.replace) {
      unawaited(navigator.push(route));
    } else if (navigator == player) {
      unawaited(navigator.pushReplacement(route));
    } else {
      // On a phone the full-screen player is over the page area, out of it: it closes, and the page opens there.
      player.pop();
      unawaited(navigator.push(route));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final songId = now.songId;
    final strings = AppLocalizations.of(context);

    if (widget._part == _Part.artist) {
      return FutureBuilder(
        future: _songOf(now),
        builder: (context, snapshot) => ArtistLinks(
          now.artist ?? '',
          // The last song's, while the next one's come, are not this one's.
          switch (snapshot.data) {
            Song(:final id, :final artists) when id == songId => artists,
            _ => now.artists,
          },
          onOpen: (artist) => _show(ArtistPage(artist)),
          // Until the media server says who they are, the whole line opens the first, asking it then.
          onTapUnknown: songId == null ? null : () => _open(songId),
          style: widget.style,
          textAlign: widget.textAlign,
        ),
      );
    }

    return TextLink(
      widget._part == _Part.title ? now.title ?? strings.nothingPlaying : now.album ?? '',
      tooltip: strings.openAlbum,
      onTap: songId == null ? null : () => _open(songId),
      style: widget.style,
      maxLines: widget.maxLines,
      textAlign: widget.textAlign,
    );
  }
}
