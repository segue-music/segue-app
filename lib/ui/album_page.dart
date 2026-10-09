import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../releases/album_credits.dart';
import '../releases/musicbrainz.dart';
import '../server/models.dart';
import '../server/server.dart';
import '../services.dart';
import 'album_row.dart';
import 'albums_view.dart';
import 'artist_link.dart';
import 'artist_page.dart';
import 'cover.dart';
import 'cover_page.dart';
import 'credits_page.dart';
import 'current_song.dart';
import 'dates.dart';
import 'equalizer.dart';
import 'errors.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'page_bar.dart';
import 'release_types.dart';
import 'song_list_header.dart';
import 'song_menu.dart';
import 'spinner.dart';
import 'themed_icon.dart';
import 'tile_row.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage(this.album, {super.key});

  final Album album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Future<(Album, List<Song>)>? _album;

  /// The album's artist, with their albums, for the row of their others.
  Future<(Artist, List<Album>)?>? _artistAlbums;

  /// The album's artist, for their picture.
  Future<Artist?>? _artist;

  /// The album's release date, record labels and type, with what MusicBrainz adds to the media server's.
  Future<AlbumRelease>? _release;

  /// Who is credited on the album, and where it was recorded: the media server's credits, with what MusicBrainz adds.
  Future<AlbumCredits>? _credits;

  /// How much of the page's color its bar has. On a phone, where the page goes on under it: none at the top of the
  /// page, and more as the cover goes up under the bar, all of it once half the cover has. On a wide screen, how much of
  /// the bar shows, which comes in as the cover goes ([PageBarSliver.shadeAt]).
  final _shade = ValueNotifier<double>(0);

  /// How big the cover is on a wide screen, square, 16 from the top of the page.
  static const _wideCover = 220.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServicesScope.of(context);
    final album = _album ??= services.api.album(widget.album.id);
    final artist = _artistAlbums ??= _artistOf(services.api, widget.album.artistId, album);
    _artist ??= artist.then((found) => found?.$1);
    _release ??= _releaseOf(album, musicBrainz: services.musicBrainz);
    _credits ??= _creditsOf(album, musicBrainz: services.musicBrainz);
  }

  /// [album]'s release date, record labels and type: the media server's, with what [musicBrainz] adds (null:
  /// nothing). None when the server fails to give the album, which the page says.
  static Future<AlbumRelease> _releaseOf(Future<(Album, List<Song>)> album, {MusicBrainz? musicBrainz}) async {
    try {
      final (found, _) = await album;

      if (musicBrainz == null) {
        return (date: found.releaseDate, labels: found.recordLabels, type: found.releaseType);
      }

      return await musicBrainz.complete(found);
    } on Object {
      return (date: null, labels: const <String>[], type: null);
    }
  }

  /// Who is credited on [album], and where it was recorded: the media server's credits, with what [musicBrainz] (null:
  /// nothing) has of the album's release where the server has none. None when the server fails to give the album,
  /// which the page says.
  static Future<AlbumCredits> _creditsOf(Future<(Album, List<Song>)> album, {MusicBrainz? musicBrainz}) async {
    try {
      final (found, songs) = await album;
      return AlbumCredits.of(songs, musicBrainz: await musicBrainz?.credits(found));
    } on Object {
      return const AlbumCredits();
    }
  }

  /// The album's artist, [artistId] or, when the page opened without it, the one [album] names, with their albums: none
  /// when it names none, or the server fails, and their picture stays a placeholder, with no row of their albums.
  static Future<(Artist, List<Album>)?> _artistOf(
    MediaServer api,
    String? artistId,
    Future<(Album, List<Song>)> album,
  ) async {
    try {
      final id = artistId ?? (await album).$1.artistId;

      if (id == null) {
        return null;
      }

      return await api.artist(id);
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _shade.dispose();
    super.dispose();
  }

  /// Follows the page as it scrolls, and as it's laid out anew (as the window narrows or widens), for its bar's color
  /// ([_shade]), letting the notification go on.
  bool _followScroll(Notification notification) {
    final offset = switch (notification) {
      ScrollNotification(depth: 0, :final metrics) ||
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics.pixels,
      _ => null,
    };
    final width = MediaQuery.sizeOf(context).width;

    if (offset == null) {
      return false;
    }

    if (width < 600) {
      // The cover is as wide as the page less its margins, up to 280, under a gap of 8 (_header).
      final cover = min(width - 2 * 16, 280);
      _shade.value = (offset / (8 + cover / 2)).clamp(0, 1);
    } else {
      _shade.value = PageBarSliver.shadeAt(offset, pictureBottom: 16 + _wideCover);
    }

    return false;
  }

  Future<void> _play(List<Song> songs, int index) async {
    final result = await ServicesScope.of(context).connect.playSongs(songs, index);

    if (!result.ok && mounted) {
      final message = describeError(AppLocalizations.of(context), result.error);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // On a phone, or a window as narrow (as the home counts it), the album's name is in the page's bar, over its cover,
    // and the songs have no header naming their columns.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final strings = AppLocalizations.of(context);
    return FutureBuilder(
      future: _album,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          // On a phone with the name, the link's until the album comes; under a wide screen's top bar, none.
          appBar: PageArea.holdsUnderTopBar(context)
              ? null
              : PageBar(
                  title: narrow ? data?.$1.name ?? widget.album.name : null,
                  shade: narrow && data != null ? _shade : null,
                ),
          // On a phone the page goes on under the bar and the system's, to the top of the screen, as it scrolls: the
          // list, with no padding of its own, starts under them, in the room MediaQuery says they take.
          extendBodyBehindAppBar: narrow && data != null,
          body: switch (data) {
            _ when snapshot.hasError => Center(
              child: Text(strings.couldNotOpenRelease(releaseSelector(widget.album.releaseType), '${snapshot.error}')),
            ),
            null => const Center(child: Spinner()),
            (final album, final songs) => NotificationListener(
              onNotification: _followScroll,
              child: CustomScrollView(
                slivers: [
                  // On a wide screen, where the name is by the cover, and stays in sight once that has gone, with the
                  // button that plays the album.
                  if (!narrow)
                    _ReleaseType(
                      album,
                      _release!,
                      builder: (type) => PageBarSliver(
                        title: album.name,
                        shade: _shade,
                        leading: _playButton(songs, type: type),
                      ),
                    ),
                  // Clear of the bars the page goes on under, by the room MediaQuery says they take, as a list is.
                  SliverSafeArea(
                    left: false,
                    right: false,
                    sliver: SliverList.list(
                      children: [
                        _ReleaseType(
                          album,
                          _release!,
                          builder: (type) => _header(album, songs, type: type, narrow: narrow),
                        ),
                        if (!narrow) const SongListHeader(numbered: true, menus: true),
                        for (var i = 0; i < songs.length; i++)
                          if (i == songs.length - 1)
                            _LastSong(
                              _song(songs, i, narrow: narrow),
                              album: album,
                              release: _release!,
                              length: narrow ? songsLength(strings, songs) : null,
                            )
                          else
                            _song(songs, i, narrow: narrow),
                        _moreByArtist(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          },
          // The songs go on behind the player bar, slightly see-through on a phone; the list, with no padding of its
          // own, takes the room MediaQuery says the bar takes at its end. In the page area the home's bars stay under
          // the page instead, with the room they take, which a bar of its own, even one showing nothing, would take
          // away.
          extendBody: true,
          bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
        );
      },
    );
  }

  /// The top of the page: the album's cover, its type (album, EP, ...), its name and byline, and the buttons that play
  /// it and add it (its menu: to the queue, or to a playlist). On a wide screen the name is beside the cover, the type
  /// above it, the buttons under them; on a narrow one ([narrow]) the name is in the page's bar (a [PageBar]), over the
  /// cover, which is centered, and the byline under the cover, from the page's margin as the songs are, with the buttons
  /// at the end of its line, the play button last ([SongListTopLine]), and the type before the year.
  Widget _header(Album album, List<Song> songs, {required ReleaseType? type, required bool narrow}) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final byline = _Byline(
      album,
      songs,
      artist: _artist!,
      type: narrow ? type : null,
      style: text.bodyMedium,
      stacked: narrow,
      credits: _creditsButton(album, songs),
    );
    final play = _playButton(songs, type: type);
    final add = PopupMenuButton<SongAction>(
      tooltip: strings.add,
      enabled: songs.isNotEmpty,
      icon: const ThemedIcon(HugeIcons.strokeRoundedAddCircle),
      onSelected: (action) => runSongAction(context, action, songs),
      itemBuilder: songMenuItems,
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            // As wide as the page, less its margins, up to a phone's widest; asked of the server as the player's is,
            // which a phone's pixels need.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: AspectRatio(aspectRatio: 1, child: CoverButton(album.coverArt, size: 800)),
              ),
            ),
          ),
          SongListTopLine(details: byline, button: add, play: play),
        ],
      );
    }

    // Asked of the server as the phone's, which a screen of more than one pixel per point needs at this size.
    const size = _wideCover;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: size, child: CoverButton(album.coverArt, size: 800)),
          const SizedBox(width: 16),
          // Centered on the cover, which stays at the top where a long name and its byline beside it are taller.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: size),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (type != null) Text(releaseTypeName(strings, type), style: text.labelLarge),
                  Text(album.name, style: text.titleLarge),
                  byline,
                  const SizedBox(height: 12),
                  Row(mainAxisSize: MainAxisSize.min, children: [play, const SizedBox(width: 8), add]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Once the album has any, a button that opens its credits ([CreditsPage]): at once where the media server has some,
  /// else once MusicBrainz's come.
  Widget _creditsButton(Album album, List<Song> songs) => FutureBuilder(
    future: _credits,
    initialData: AlbumCredits.of(songs),
    builder: (context, snapshot) => switch (snapshot.requireData) {
      final credits when credits.isEmpty => const SizedBox.shrink(),
      final credits => IconButton(
        tooltip: AppLocalizations.of(context).showCredits,
        icon: const ThemedIcon(HugeIcons.strokeRoundedBookUser),
        visualDensity: VisualDensity.compact,
        onPressed: () => CreditsPage.open(
          context,
          album,
          credits: _credits!,
          initialCredits: credits,
          inLibrary: _artistsInLibrary(),
          // Over this page, as the credits close.
          onOpenArtist: (artist) =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist))),
        ),
      ),
    },
  );

  /// The library's artists, by their ids on the server and their MusicBrainz ids: those credited on the album link to
  /// their pages. None where the server fails.
  Future<Map<String, Artist>> _artistsInLibrary() async {
    final api = ServicesScope.of(context).api;

    try {
      return {
        for (final artist in await api.artists()) ...{artist.id: artist, ?artist.musicBrainzId: artist},
      };
    } on Object {
      return const {};
    }
  }

  /// The artist's other albums, in the order of their page ([ArtistPage.sections]: their albums, newest first, then their
  /// singles and EPs), in a row under their name ("Mais de Aerosmith"), which opens their page; each with its year and
  /// its type where it isn't an album, as there. Nothing until they come, nor where they have no other, or the server
  /// fails. As far under its covers' lines as the albums are from an artist's page's end.
  Widget _moreByArtist() => FutureBuilder(
    future: _artistAlbums,
    builder: (context, snapshot) {
      final strings = AppLocalizations.of(context);

      if (snapshot.data case (final artist, final albums)) {
        final others = [
          for (final section in ArtistPage.sections(strings, albums))
            for (final album in section.albums)
              if (album.id != widget.album.id) album,
        ];

        if (others.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16 - AlbumTile.padding),
            child: TileRow(
              title: strings.moreByArtist(artist.name),
              onShowAll: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist))),
              tiles: [
                for (final album in others.take(AlbumRow.maxAlbums))
                  AlbumTile(album, subtitle: yearAndReleaseType(strings, album)),
              ],
              tileSize: AlbumRow.tileSize,
              previousLabel: strings.previousAlbums,
              nextLabel: strings.nextAlbums,
            ),
          );
        }
      }

      return const SizedBox.shrink();
    },
  );

  /// The button that plays the album, of [type], from its first song: just the icon, its name in the tooltip, as the play
  /// button on the albums' covers.
  Widget _playButton(List<Song> songs, {required ReleaseType? type}) => IconButton.filled(
    tooltip: AppLocalizations.of(context).playRelease(releaseSelector(type)),
    onPressed: songs.isEmpty ? null : () => _play(songs, 0),
    icon: const ThemedIcon(HugeIcons.strokeRoundedPlay),
  );

  /// The album's song at [index] in its list, which plays the album from it; on a [narrow] screen, its artists plain
  /// text.
  Widget _song(List<Song> songs, int index, {required bool narrow}) {
    final song = songs[index];
    return CurrentSong(
      song,
      builder: (context, current, playing) => SongMenu(
        song,
        builder: (context, menu) => ListTile(
          contentPadding: SongTrailing.tilePadding,
          horizontalTitleGap: SongListHeader.numberGap,
          minLeadingWidth: SongListHeader.numberWidth,
          selected: current,
          leading: SizedBox(
            width: SongListHeader.numberWidth,
            child: playing ? const Equalizer() : SongNumber(index + 1),
          ),
          title: Text(song.title),
          // On a phone, where a finger on the song would often land on them, the artists are plain text: a tap plays the
          // song, and they open from the player. Elsewhere they link, taking no focus: for the keyboard and the remote
          // the song stays one stop, as an album in the grid is.
          subtitle: song.artist == null
              ? null
              : narrow
              ? Text(artistNames(song), maxLines: 1, overflow: TextOverflow.ellipsis)
              : ExcludeFocus(child: ArtistLinks.song(song)),
          trailing: SongTrailing(song.duration, menu),
          onTap: () => _play(songs, index),
        ),
      ),
    );
  }
}

/// Under the album's name: its artist, with their picture, a link to their page; its type, where it isn't above the
/// name; its year; how many songs it has and how long they last; the button that opens its credits. One paragraph,
/// beside the cover; or, [stacked], the artist on a line of their own and the rest under them, but how long the songs
/// last, which a phone's line has no room for: that ends the list ([_LastSong]).
class _Byline extends StatelessWidget {
  const _Byline(
    this.album,
    this.songs, {
    required this.artist,
    required this.credits,
    this.type,
    this.style,
    this.stacked = false,
  });

  final Album album;
  final List<Song> songs;

  /// The artist, for their picture.
  final Future<Artist?> artist;

  /// The album's type, before its year; null where the page doesn't show it here.
  final ReleaseType? type;

  final TextStyle? style;

  /// Whether the type, the year and the songs are under the artist, rather than after them, with how long they last.
  final bool stacked;

  /// The button that opens the album's credits, at the end.
  final Widget credits;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final details = [
      if (type case final type?) releaseTypeName(strings, type),
      if (album.year case final year?) '$year',
      if (songs.isNotEmpty) stacked ? strings.trackCount(songs.length) : songCountAndLength(strings, songs),
    ].join(' · ');
    final link = album.artist == null
        ? null
        : ArtistLink.album(album, style: style, picture: album.artistId == null ? null : _ArtistPicture(artist));

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?link,
          Row(
            children: [
              if (details.isNotEmpty) Flexible(child: Text(details, style: style)),
              const SizedBox(width: 4),
              credits,
            ],
          ),
        ],
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          if (link != null) ...[
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: link),
            if (details.isNotEmpty) const TextSpan(text: ' · '),
          ],
          TextSpan(text: details),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: credits),
          ),
        ],
      ),
      style: style,
    );
  }
}

/// The picture of the album's artist, small and round, before their name ([ArtistPicture]): a person until it comes,
/// and where there's none.
class _ArtistPicture extends StatelessWidget {
  const _ArtistPicture(this.artist);

  /// Whose it is.
  final Future<Artist?> artist;

  /// How big it is, square.
  static const size = 24.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipOval(
      child: IconTheme.merge(
        data: const IconThemeData(size: 16),
        child: FutureBuilder(
          future: artist,
          builder: (context, snapshot) => switch (snapshot.data) {
            final artist? => ArtistPicture(artist, size: 96),
            null => const Cover(null, icon: HugeIcons.strokeRoundedUser),
          },
        ),
      ),
    ),
  );
}

/// What [builder] makes of the album's type (album, EP, ...): the one the media server says, then the one MusicBrainz
/// finds, as it comes.
class _ReleaseType extends StatelessWidget {
  const _ReleaseType(this.album, this.release, {required this.builder});

  final Album album;
  final Future<AlbumRelease> release;
  final Widget Function(ReleaseType? type) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: release,
    initialData: (date: album.releaseDate, labels: album.recordLabels, type: album.releaseType),
    builder: (context, release) => builder(release.requireData.type),
  );
}

/// The album's last song, with what is known of its release under it, ending the list: its date, on a phone how long
/// its songs last ([length]), and the labels that put it out. The media server's first, then with
/// what MusicBrainz adds, as it comes. The keyboard and the remote stop at the songs only, so as the focus comes to the
/// last one the list scrolls on to show these too.
class _LastSong extends StatelessWidget {
  const _LastSong(this.song, {required this.album, required this.release, this.length});

  final Widget song;
  final Album album;
  final Future<AlbumRelease> release;

  /// How long the album's songs last, between its date and its labels; null where that's under its name.
  final String? length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return FutureBuilder(
      future: release,
      initialData: (date: album.releaseDate, labels: album.recordLabels, type: album.releaseType),
      builder: (context, snapshot) {
        final (:date, :labels, type: _) = snapshot.requireData;
        final lines = [
          if (date != null) formatDate(AppLocalizations.of(context), date),
          ?length,
          if (labels.isNotEmpty) labels.join(', '),
        ];
        // The same widgets around the song, with or without the lines under it: rebuilt, it would lose the focus.
        return Focus(
          canRequestFocus: false,
          onFocusChange: (focused) {
            if (focused) {
              Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              song,
              if (lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final line in lines) Text(line, style: style)],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
