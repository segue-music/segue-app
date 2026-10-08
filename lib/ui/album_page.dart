import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../l10n/app_localizations.dart';
import '../releases/album_credits.dart';
import '../releases/musicbrainz.dart';
import '../server/models.dart';
import '../server/server.dart';
import '../services.dart';
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
import 'spinner.dart';
import 'themed_icon.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage(this.album, {super.key});

  final Album album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Future<(Album, List<Song>)>? _album;

  /// The cover id of the picture of the album's artist.
  Future<String?>? _artistPicture;

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
    _artistPicture ??= _pictureOfArtist(services.api, widget.album.artistId, album);
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

  /// The cover id of the picture of the album's artist, [artistId] or, when the page opened without it, the one
  /// [album] names: none when it names none, or the server fails, and the picture stays a placeholder.
  static Future<String?> _pictureOfArtist(MediaServer api, String? artistId, Future<(Album, List<Song>)> album) async {
    try {
      final id = artistId ?? (await album).$1.artistId;

      if (id == null) {
        return null;
      }

      final (artist, _) = await api.artist(id);
      return artist.coverArt;
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
                        if (!narrow) const SongListHeader(numbered: true),
                        for (var i = 0; i < songs.length; i++)
                          if (i == songs.length - 1)
                            _LastSong(_song(songs, i), album: album, release: _release!)
                          else
                            _song(songs, i),
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

  /// The top of the page: the album's cover, its type (album, EP, ...), its name and byline, and the button that plays
  /// it. On a wide screen the name is beside the cover, the type above it, the button under them; on a narrow one
  /// ([narrow]) the name is in the page's bar (a [PageBar]), over the cover, which is centered, and the byline under the
  /// cover, from the page's margin as the songs are, with the button at the end of its line, and the type before the
  /// year.
  Widget _header(Album album, List<Song> songs, {required ReleaseType? type, required bool narrow}) {
    final text = Theme.of(context).textTheme;
    final strings = AppLocalizations.of(context);
    final byline = _Byline(
      album,
      songs,
      artistPicture: _artistPicture!,
      type: narrow ? type : null,
      style: text.bodyMedium,
      stacked: narrow,
      credits: _creditsButton(album, songs),
    );
    final play = _playButton(songs, type: type);

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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: byline),
                const SizedBox(width: 16),
                play,
              ],
            ),
          ),
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
                  play,
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

  /// The button that plays the album, of [type], from its first song: just the icon, its name in the tooltip, as the play
  /// button on the albums' covers.
  Widget _playButton(List<Song> songs, {required ReleaseType? type}) => IconButton.filled(
    tooltip: AppLocalizations.of(context).playRelease(releaseSelector(type)),
    onPressed: songs.isEmpty ? null : () => _play(songs, 0),
    icon: const ThemedIcon(HugeIcons.strokeRoundedPlay),
  );

  /// The album's song at [index] in its list, which plays the album from it.
  Widget _song(List<Song> songs, int index) {
    final song = songs[index];
    return CurrentSong(
      song,
      builder: (context, current, playing) => ListTile(
        selected: current,
        leading: SizedBox(
          width: SongListHeader.numberWidth,
          child: playing ? const Equalizer() : SongNumber(index + 1),
        ),
        title: Text(song.title),
        // The artists take no focus: for the keyboard and the remote the song stays one stop, as an album in the grid
        // is.
        subtitle: song.artist == null ? null : ExcludeFocus(child: ArtistLinks.song(song)),
        trailing: SongDuration(song.duration),
        onTap: () => _play(songs, index),
      ),
    );
  }
}

/// Under the album's name: its artist, with their picture, a link to their page; its type, where it isn't above the
/// name; its year; how many songs it has and how long they last; the button that opens its credits. One paragraph,
/// beside the cover; or, [stacked], the artist on a line of their own and the rest under them.
class _Byline extends StatelessWidget {
  const _Byline(
    this.album,
    this.songs, {
    required this.artistPicture,
    required this.credits,
    this.type,
    this.style,
    this.stacked = false,
  });

  final Album album;
  final List<Song> songs;

  /// The cover id of the artist's picture.
  final Future<String?> artistPicture;

  /// The album's type, before its year; null where the page doesn't show it here.
  final ReleaseType? type;

  final TextStyle? style;

  /// Whether the type, the year, the songs and how long they last are under the artist, rather than after them.
  final bool stacked;

  /// The button that opens the album's credits, at the end, beside how long the songs last.
  final Widget credits;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final details = [
      if (type case final type?) releaseTypeName(strings, type),
      if (album.year case final year?) '$year',
      if (songs.isNotEmpty) _songsLength(strings, songs),
    ].join(' · ');
    final artist = album.artist == null
        ? null
        : ArtistLink.album(album, style: style, picture: album.artistId == null ? null : _ArtistPicture(artistPicture));

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?artist,
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
          if (artist != null) ...[
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: artist),
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

/// How many songs there are, and how long they last together, where each says: "9 faixas, 37 min".
String _songsLength(AppLocalizations strings, List<Song> songs) {
  final count = strings.trackCount(songs.length);

  if (songs.any((song) => song.duration == null)) {
    return count;
  }

  final length = songs.fold(Duration.zero, (sum, song) => sum + song.duration!);
  final (hours, minutes) = (length.inHours, length.inMinutes % 60);
  final time = switch ((hours, minutes)) {
    (0, 0) => strings.lengthSeconds(length.inSeconds),
    (0, _) => strings.lengthMinutes(minutes),
    (_, 0) => strings.lengthHours(hours),
    _ => strings.lengthHoursMinutes(hours, minutes),
  };
  return strings.tracksAndLength(count, time);
}

/// The picture of the album's artist, small and round, before their name: a person until it comes, and where the
/// server has none.
class _ArtistPicture extends StatelessWidget {
  const _ArtistPicture(this.coverArt);

  /// Its cover id.
  final Future<String?> coverArt;

  /// How big it is, square.
  static const size = 24.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipOval(
      child: IconTheme.merge(
        data: const IconThemeData(size: 16),
        child: FutureBuilder(
          future: coverArt,
          builder: (context, snapshot) => Cover(snapshot.data, size: 96, icon: HugeIcons.strokeRoundedUser),
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

/// The album's last song, with what is known of its release under it, ending the list: its date, and the labels that
/// put it out. The media server's first, then with what MusicBrainz adds, as it comes. The keyboard and the remote
/// stop at the songs only, so as the focus comes to the last one the list scrolls on to show these too.
class _LastSong extends StatelessWidget {
  const _LastSong(this.song, {required this.album, required this.release});

  final Widget song;
  final Album album;
  final Future<AlbumRelease> release;

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
