import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../releases/musicbrainz.dart';
import '../../server/models.dart';
import '../../server/server.dart';
import '../../services.dart';
import '../album/albums_view.dart';
import '../album/release_types.dart';
import '../app/page_area.dart';
import '../app/page_bar.dart';
import '../genre/genre_page.dart';
import '../player/now_playing_bar.dart';
import '../song/current_song.dart';
import '../song/favorite_button.dart';
import '../song/song_list_header.dart';
import '../song/song_menu.dart';
import '../widgets/cover.dart';
import '../widgets/errors.dart';
import '../widgets/segmented_choice.dart';
import '../widgets/spinner.dart';
import '../widgets/text_link.dart';
import '../widgets/themed_icon.dart';
import '../widgets/tile_row.dart';
import 'artists_view.dart';
import 'biography_page.dart';

/// Albums of an artist's of one kind, and what they're called: their albums, or their singles and EPs.
typedef AlbumSection = ({String title, List<Album> albums});

/// An artist and their albums, newest first, under a few songs of theirs (the ones the user plays most, or the popular
/// ones: [_ArtistSongs]): their albums or their singles and EPs, picked above them where they have both, or else under
/// a title, then the artists like them.
class ArtistPage extends StatefulWidget {
  const ArtistPage(this.artist, {super.key});

  final Artist artist;

  /// [albums], newest first, in sections: the artist's albums (with those the server says no type of), then their
  /// singles and EPs. A section of none isn't there, nor its title or its option, even with the songs above.
  static List<AlbumSection> sections(AppLocalizations strings, List<Album> albums) {
    const short = {ReleaseType.single, ReleaseType.ep};
    final newest = [...albums]..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    final full = [
      for (final album in newest)
        if (!short.contains(album.releaseType)) album,
    ];
    final singles = [
      for (final album in newest)
        if (short.contains(album.releaseType)) album,
    ];

    return [
      if (full.isNotEmpty) (title: strings.albums, albums: full),
      if (singles.isNotEmpty) (title: strings.singlesAndEps, albums: singles),
    ];
  }

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  Future<(Artist, List<Album>)>? _artist;
  Future<List<Song>>? _mostPlayed;

  /// Their biography; none where the server has none, or can't say.
  Future<Biography?>? _biography;

  /// The library's artists like them; none where the server can't say.
  Future<List<Artist>>? _similar;

  /// Which of their sections ([ArtistPage.sections]) shows where they have two: their albums (0) until the user picks
  /// their singles and EPs (1).
  int _section = 0;

  /// How much of the page's color its bar has. On a phone, over the artist's picture: none at the top of the page, and
  /// more as the page scrolls, all of it once their name, over the bottom of the picture ([_name]), reaches the bar, which
  /// then takes it ([_titleOpacity]). On a wide screen, how much of the bar shows, which comes in as the picture goes
  /// ([PageBarSliver.shadeAt]).
  final _shade = ValueNotifier<double>(0);

  /// On a phone, the artist's name over the bottom of their picture.
  final _name = GlobalKey();

  /// On a phone, how much of the artist's name the page's bar shows: none while the page shows it over their picture,
  /// and all of it once that has gone up under the bar, coming in as it goes.
  final _titleOpacity = ValueNotifier<double>(0);

  /// On a phone, the color of the artist's picture under the page's bar, on average, with what it was found for: the
  /// picture, how big it shows, and how far down the bar goes, with the system's above it. What the arrow and the name
  /// stand out from; null until it's known, or where the picture can't be loaded.
  ((Object, Size, double), Color?)? _underBar;

  /// How big the artist's picture is on a wide screen, round, 16 from the top of the page: as big as an album's cover on
  /// its page.
  static const _widePicture = 220.0;

  /// How many pictures of the artist their biography shows at most after the media server's: a few to look at.
  static const _morePictures = 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ServicesScope.of(context).api;
    _artist ??= api.artist(widget.artist.id);
    _mostPlayed ??= api.mostPlayedSongs(widget.artist.id, size: _ArtistSongs.count);
    // A biography the server can't give is one it doesn't have: the page goes on without its button.
    _biography ??= api.biography(widget.artist.id).catchError((Object _) => null);
    // Artists like them the server can't give are none, as with a biography.
    _similar ??= api.similarArtists(widget.artist.id).catchError((Object _) => const <Artist>[]);
  }

  @override
  void dispose() {
    _shade.dispose();
    _titleOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    // On a phone, or a window as narrow (as the home counts it), the picture goes across the top of the page, under its
    // bar, which has the name: beside it, a picture of some size would leave the name no room.
    final narrow = MediaQuery.sizeOf(context).width < 600;

    return FutureBuilder(
      future: _artist,
      builder: (context, snapshot) {
        final data = snapshot.data;

        // Where the server has no picture of them, fanart.tv's: of the artist the page opened with until theirs comes,
        // with the MusicBrainz id a list may not have given.
        return FanartPicture(
          data?.$1 ?? widget.artist,
          builder: (context, otherPicture) => Scaffold(
            // On a phone with the name, the link's until the artist comes, then once the page's own has gone up under
            // it; under a wide screen's top bar, none.
            appBar: PageArea.holdsUnderTopBar(context)
                ? null
                : PageBar(
                    title: narrow ? data?.$1.name ?? widget.artist.name : null,
                    shade: narrow && data != null ? _shade : null,
                    titleOpacity: narrow && data != null ? _titleOpacity : null,
                    under: narrow && data != null
                        ? _colorUnderBar(data.$1.coverArt ?? widget.artist.coverArt, otherPicture)
                        : null,
                  ),
            // On a phone the picture goes on under the bar and the system's, to the top of the screen.
            extendBodyBehindAppBar: narrow && data != null,
            body: switch (data) {
              _ when snapshot.hasError => Center(child: Text(strings.couldNotOpenArtistError('${snapshot.error}'))),
              null => const Center(child: Spinner()),
              (final artist, final albums) => NotificationListener(
                onNotification: _followScroll,
                child: _albums(
                  ArtistPage.sections(strings, albums),
                  subtitle: (album) => yearAndReleaseType(strings, album),
                  // On a wide screen, where the name is by the picture, and stays in sight once that has gone.
                  bar: narrow ? null : PageBarSliver(title: artist.name, shade: _shade),
                  header: _ArtistSongs(
                    artist,
                    mostPlayed: _mostPlayed!,
                    builder: (heading, songs) =>
                        _header(artist, albums, heading, songs, otherPicture: otherPicture, narrow: narrow),
                    icons: narrow,
                    // On a phone, how many albums they have, at the end of the choice's line.
                    trailing: narrow ? _counts(artist, albums, end: true) : null,
                  ),
                  footer: _similarArtists(),
                ),
              ),
            },
            // The albums go on behind the player bar, slightly see-through on a phone; the grid ends with the room
            // MediaQuery says the bar takes. In the page area the home's bars stay under the page instead, with the room
            // they take, which a bar of its own, even one showing nothing, would take away.
            extendBody: true,
            bottomNavigationBar: PageArea.holds(context) ? null : const NowPlayingBar(),
          ),
        );
      },
    );
  }

  /// In how many steps the artist's picture fades into the page at its bottom.
  static const _fadeSteps = 12;

  /// The page's color over the artist's picture, from [from] of it at the top to [to] of it at the bottom: eased at both
  /// ends, in steps the gradient joins, so that neither shows where the picture starts to fade nor where the page goes
  /// on, as one.
  static LinearGradient _fade(Color surface, {double from = 0, double to = 1}) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      for (var step = 0; step <= _fadeSteps; step++)
        surface.withValues(alpha: from + (to - from) * Curves.easeInOut.transform(step / _fadeSteps)),
    ],
    stops: [for (var step = 0; step <= _fadeSteps; step++) step / _fadeSteps],
  );

  /// On a phone, how far above the artist's name their picture starts fading into the page.
  static const _fadeRoom = 72.0;

  /// On a phone, how much of the page's color is over the artist's picture behind their name: enough that the name, in
  /// the page's text color, reads over any picture, a black one in the light theme or a white one in the dark, with no
  /// halo; the picture still shows through.
  static const _underName = 0.6;

  /// How tall the artist's picture is on a phone, under the system's bar: as tall as it's wide, as an artist's picture
  /// mostly is, but half a short window at most.
  double get _pictureHeight {
    final screen = MediaQuery.sizeOf(context);

    return min(screen.width, screen.height / 2);
  }

  /// The color of the artist's [picture] (or, where the server has none, [otherPicture], fanart.tv's) under the page's
  /// bar on a phone, as [_underBar] has it: found out where it hasn't been yet, for that picture and where it shows,
  /// which keeps the last one's meanwhile, as the screen turns.
  Color? _colorUnderBar(String? picture, Uri? otherPicture) {
    final shown = picture ?? otherPicture;

    if (shown == null) {
      return null;
    }

    final top = MediaQuery.paddingOf(context).top;
    final box = Size(MediaQuery.sizeOf(context).width, top + _pictureHeight);
    final key = (shown, box, top + kToolbarHeight);

    if (_underBar case (final known, final color) when known == key) {
      return color;
    }

    final last = _underBar?.$2;
    _underBar = (key, last);
    final average = Cover.averageColor(
      context,
      picture,
      url: otherPicture,
      region: (image) => _topOf(image, box, key.$3),
    );
    unawaited(
      average.then((color) {
        if (mounted && _underBar?.$1 == key) {
          setState(() => _underBar = (key, color));
        }
      }),
    );

    return last;
  }

  /// Where the top [height] of a picture [image] big is, as it fills [box], as a cover does ([BoxFit.cover], centered).
  static Rect _topOf(Size image, Size box, double height) {
    final shown = Alignment.center.inscribe(applyBoxFit(BoxFit.cover, image, box).source, Offset.zero & image);

    return Rect.fromLTWH(shown.left, shown.top, shown.width, shown.height * height / box.height);
  }

  /// Follows the page as it scrolls, and as it's laid out anew (as the window narrows or widens), for its bar's color
  /// ([_shade]) and, on a phone, its title ([_titleOpacity]), letting the notification go on.
  bool _followScroll(Notification notification) {
    final offset = switch (notification) {
      ScrollNotification(depth: 0, :final metrics) ||
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics.pixels,
      _ => null,
    };

    if (offset == null) {
      return false;
    }

    if (MediaQuery.sizeOf(context).width >= 600) {
      _shade.value = PageBarSliver.shadeAt(offset, pictureBottom: 16 + _widePicture);
      return false;
    }

    final name = _name.currentContext?.findRenderObject();

    if (name is RenderBox && name.hasSize) {
      // How far the page scrolls before the name's top reaches the bar's bottom: from where it is at the top of the page,
      // under the system's bar and the page's.
      final reach =
          RenderAbstractViewport.of(name).getOffsetToReveal(name, 0).offset -
          MediaQuery.paddingOf(context).top -
          kToolbarHeight;
      _shade.value = reach <= 0 ? 1 : (offset / reach).clamp(0, 1);
      _titleOpacity.value = ((offset - reach) / name.size.height).clamp(0, 1);
    }

    return false;
  }

  /// The albums of one of [sections] in a grid, as an [AlbumGrid] has them, between [header] and [footer]: of the one
  /// picked in a choice above them, where there are two, as an artist's songs are; of the one alone under its title.
  Widget _albums(
    List<AlbumSection> sections, {
    required String Function(Album album) subtitle,
    required Widget? bar,
    required Widget header,
    required Widget footer,
  }) => AlbumGrid(
    switch (sections) {
      [] => const [],
      [final section] => section.albums,
      _ => sections[_section].albums,
    },
    heading: switch (sections) {
      [] => null,
      [final section] => Text(section.title, style: Theme.of(context).textTheme.titleLarge),
      _ => SegmentedChoice(
        _section,
        options: [for (var i = 0; i < sections.length; i++) i],
        label: (i) => sections[i].title,
        onSelected: (i) => setState(() => _section = i),
      ),
    },
    subtitle: subtitle,
    bar: bar,
    header: header,
    footer: footer,
  );

  /// The top of the page, down to the artist's [songs] and the choice of their lists, or its title ([heading]). On a
  /// wide screen the picture is round, the name beside it, with how many albums they have and their genres, and behind
  /// them the picture again, blurred, across the page. On a narrow one ([narrow]) it goes across the page from the top
  /// of the screen, under the page's bar (a [PageBar]) and the system's; the heading is over its bottom, with how many
  /// albums they have at the end of its line, where it fades to the page's color (darker in the dark theme, lighter in
  /// the light one), their genres over it, and their name over them, in bold, bigger than the bar has it ([_name]). The
  /// picture is the server's or, where it has none, [otherPicture], fanart.tv's ([FanartPicture]).
  Widget _header(
    Artist artist,
    List<Album> albums,
    Widget? heading,
    List<Widget> songs, {
    required Uri? otherPicture,
    required bool narrow,
  }) {
    final text = Theme.of(context).textTheme;
    final picture = artist.coverArt ?? widget.artist.coverArt;
    final count = _counts(artist, albums, end: narrow);
    final genres = _genres(albums);

    if (narrow) {
      // The system's bar, which the picture goes on under, as under the page's.
      final top = MediaQuery.paddingOf(context).top;
      final height = top + _pictureHeight;
      final surface = Theme.of(context).colorScheme.surface;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: height,
                // Asked of the server as many pixels across as a phone's screen has.
                child: LargeCover(picture, url: otherPicture, size: 1200, icon: HugeIcons.strokeRoundedUser),
              ),
              // The heading over the picture's bottom, with how many albums they have at the end of its line; with no
              // heading, that alone at the end. Their genres over it, and their name over them. The picture as it is
              // down to [_fadeRoom] above the name, then more and more of the page's color, [_underName] of it at the
              // name, to all of it at the bottom, under the heading.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: _fadeRoom,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: _fade(surface, to: _underName)),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(gradient: _fade(surface, from: _underName)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              artist.name,
                              key: _name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (genres != null)
                            Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, heading == null ? 4 : 0), child: genres),
                          heading ??
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Align(alignment: AlignmentDirectional.centerEnd, child: count),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ...songs,
        ],
      );
    }

    final surface = Theme.of(context).colorScheme.surface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            // Behind them, the picture blurred into its colors, across the page, under a fifth of the page's color at
            // the top and more of it lower down, all of it at the bottom of the round picture, where the page goes on.
            if (picture != null || otherPicture != null)
              Positioned.fill(
                child: ClipRect(
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(gradient: _fade(surface, from: 0.2)),
                    // As the artists' grid has asked for it, which the blur leaves nothing more to see in.
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Cover(picture, url: otherPicture, icon: HugeIcons.strokeRoundedUser),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  // Asked of the server as an album's cover on its page is.
                  SizedBox.square(
                    dimension: _widePicture,
                    child: ClipOval(
                      child: LargeCover(picture, url: otherPicture, size: 800, icon: HugeIcons.strokeRoundedUser),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(artist.name, style: text.titleLarge),
                        count,
                        ?genres,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ?heading,
        ...songs,
      ],
    );
  }

  /// How many albums they have ([_count]), then, once the server has given their biography, a button that opens it
  /// ([BiographyPage]), and the heart that makes them one of the user's favorites, beside it: at the end of the line,
  /// where the page has it there ([end]).
  Widget _counts(Artist artist, List<Album> albums, {bool end = false}) {
    final strings = AppLocalizations.of(context);
    final count = Text(
      _count(strings, albums),
      style: Theme.of(context).textTheme.bodyMedium,
      textAlign: end ? TextAlign.end : null,
    );
    final favorite = FavoriteButton(FavoriteKind.artist, widget.artist.id, compact: true);

    return FutureBuilder(
      future: _biography,
      builder: (context, snapshot) => switch (snapshot.data) {
        null => Row(
          mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(child: count),
            const SizedBox(width: 4),
            favorite,
          ],
        ),
        final biography => Row(
          mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(child: count),
            const SizedBox(width: 4),
            favorite,
            IconButton(
              tooltip: strings.showBiography,
              icon: const ThemedIcon(HugeIcons.strokeRoundedBookUser),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final services = ServicesScope.of(context);
                final musicBrainz = services.musicBrainz;
                final band = musicBrainz?.band(artist);
                BiographyPage.open(
                  context,
                  biography,
                  name: artist.name,
                  picture: artist.coverArt ?? widget.artist.coverArt,
                  morePictures: services.fanartTv
                      ?.artistPictures(artist)
                      .then((pictures) => pictures.take(_morePictures).toList()),
                  band: band,
                  origin: musicBrainz?.origin(artist),
                  inLibrary: band == null ? null : _membersInLibrary(band),
                  // Over this page, as the biography closes.
                  onOpenArtist: (member) =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(member))),
                );
              },
            ),
          ],
        ),
      },
    );
  }

  /// Pictures of 160 pixels in the row of artists like them, as an album's cover is in a row of albums, with the tiles'
  /// room inside ([ArtistTile.padding]).
  static const _similarTileSize = Size(
    160 + 2 * ArtistTile.padding,
    (160 + 2 * ArtistTile.padding) / ArtistTile.aspectRatio,
  );

  /// The artists like them ([_similar]), in a row of their pictures, each of which opens their page; nothing until they
  /// come, and nothing with none. As far under its last pictures' lines as the albums are from the page's end.
  Widget _similarArtists() => FutureBuilder(
    future: _similar,
    builder: (context, snapshot) {
      final strings = AppLocalizations.of(context);

      return switch (snapshot.data) {
        null || [] => const SizedBox.shrink(),
        final artists => Padding(
          padding: const EdgeInsets.only(bottom: 16 - ArtistTile.padding),
          child: TileRow(
            title: strings.similarArtists,
            tiles: [for (final artist in artists) ArtistTile(artist)],
            tileSize: _similarTileSize,
            previousLabel: strings.previousArtists,
            nextLabel: strings.nextArtists,
          ),
        ),
      };
    },
  );

  /// The library's artists among [band]'s members, by their MusicBrainz ids: all the library's are asked of the server
  /// only once the band has members. None where the server can't say, or doesn't give their ids.
  Future<Map<String, Artist>> _membersInLibrary(Future<Band?> band) async {
    final api = ServicesScope.of(context).api;
    final members = {for (final member in (await band)?.members ?? const <BandMember>[]) member.id};

    if (members.isEmpty) {
      return const {};
    }

    try {
      return {
        for (final artist in await api.artists())
          if (artist.musicBrainzId case final id? when members.contains(id)) id: artist,
      };
    } on Object {
      return const {};
    }
  }

  /// How many genres the artist's page shows at most.
  static const _genreCount = 3;

  /// The genres most of [albums] are in, the one most are in first, [_genreCount] at most, each a link to its page
  /// ([GenrePage]), apart by dots: "Hard rock · Blues rock · Rock". On a material of their own, over the picture
  /// (blurred, on a wide screen; on a phone, where it fades into the page), where the ink of the focus, a hover and a tap
  /// shows on them: on the page's, it was under the picture. None where the server gives their albums none.
  Widget? _genres(List<Album> albums) {
    final genres = <String, Genre>{};
    final counts = <String, int>{};

    for (final album in albums) {
      for (final genre in album.genres) {
        genres.putIfAbsent(genre.id, () => genre);
        counts[genre.id] = (counts[genre.id] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) {
      return null;
    }

    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Material(
      type: MaterialType.transparency,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, id) in rankedByCount(counts).take(_genreCount).indexed) ...[
            if (i > 0) Text(' · ', style: style),
            TextLink(
              genres[id]!.name,
              tooltip: strings.openGenre,
              style: style,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GenrePage(genres[id]!))),
            ),
          ],
        ],
      ),
    );
  }

  /// How many of [albums] are albums, and singles and EPs, as the sections under part them: "8 álbuns · 4 singles e
  /// EPs", "8 álbuns · 1 EP", "2 singles"; "0 álbuns" with none.
  static String _count(AppLocalizations strings, List<Album> albums) {
    final singles = albums.where((album) => album.releaseType == ReleaseType.single).length;
    final eps = albums.where((album) => album.releaseType == ReleaseType.ep).length;
    final full = albums.length - singles - eps;
    final short = switch ((singles, eps)) {
      (0, 0) => null,
      (_, 0) => strings.singleCount(singles),
      (0, _) => strings.epCount(eps),
      _ => strings.singleAndEpCount(singles + eps),
    };

    return [if (full > 0 || short == null) albumCount(strings, full), ?short].join(' · ');
  }
}

/// The lists of an artist's songs their page shows: what each says of itself, as an option to pick or the title of the
/// one alone, and the icon an option can show instead.
enum _SongRanking {
  /// The songs the user plays most.
  mostPlayed,

  /// The songs everyone plays most.
  popular;

  String label(AppLocalizations strings) => switch (this) {
    mostPlayed => strings.mostPlayedSongs,
    popular => strings.popularSongs,
  };

  /// What the user listens to; what's hot.
  HugeIconData get icon => switch (this) {
    mostPlayed => HugeIcons.strokeRoundedHeadphones,
    popular => HugeIcons.strokeRoundedFire,
  };
}

/// The artist's songs the user plays most, or the popular ones (those everyone plays most, as the server learns them),
/// the first few ([count]), numbered, picked over them where both have songs: the user's, until the others are. Each
/// plays the list from it, as an album's songs do. A list with none isn't there, nor its option, and with neither,
/// nothing is. Nothing until the user's have come, so that the popular ones, should they come first, don't give way to
/// them as they come; the popular ones that fail aren't there either, as a server that has none to give.
class _ArtistSongs extends StatefulWidget {
  const _ArtistSongs(this.artist, {required this.mostPlayed, required this.builder, this.icons = false, this.trailing});

  /// The artist as the server gives them, whose name is the one the popular songs are asked by: a link's may be an
  /// album's artists together ("A & B").
  final Artist artist;

  final Future<List<Song>> mostPlayed;

  /// Lays the songs out under what comes over them, given the choice of the lists or the title of the one alone, with
  /// the room around it ([heading]: none with no list), and the list's songs.
  final Widget Function(Widget? heading, List<Widget> songs) builder;

  /// Whether the choice of the lists shows them as icons, their names in tooltips: over the picture, on a phone.
  final bool icons;

  /// What ends the line of the choice of the lists, or of the title of the one alone, across from it: how many albums
  /// the artist has, on a phone.
  final Widget? trailing;

  /// How many there are at most.
  static const count = 5;

  @override
  State<_ArtistSongs> createState() => _ArtistSongsState();
}

class _ArtistSongsState extends State<_ArtistSongs> {
  Future<List<Song>>? _popular;

  /// The list picked; none before the user picks one.
  _SongRanking? _picked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _popular ??= ServicesScope.of(context).api.popularSongs(widget.artist, size: _ArtistSongs.count);
  }

  static Future<void> _play(BuildContext context, List<Song> songs, int index) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppLocalizations.of(context);
    final result = await ServicesScope.of(context).connect.playSongs(songs, index);

    if (!result.ok) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(strings, result.error))));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: widget.mostPlayed,
    builder: (context, mostPlayed) => FutureBuilder(
      future: _popular,
      builder: (context, popular) {
        final text = Theme.of(context).textTheme;
        final strings = AppLocalizations.of(context);

        if (mostPlayed.connectionState != ConnectionState.done) {
          return widget.builder(null, const []);
        }

        final lists = {
          if (mostPlayed.hasError || mostPlayed.requireData.isNotEmpty) _SongRanking.mostPlayed: mostPlayed,
          if (popular.data?.isNotEmpty ?? false) _SongRanking.popular: popular,
        };

        if (lists.isEmpty) {
          return widget.builder(null, const []);
        }

        final shown = lists.containsKey(_picked) ? _picked! : lists.keys.first;
        final snapshot = lists[shown]!;
        final songs = snapshot.data ?? const <Song>[];
        final heading = lists.length > 1
            ? SegmentedChoice<_SongRanking>(
                shown,
                options: [...lists.keys],
                label: (list) => list.label(strings),
                icon: widget.icons ? (list) => list.icon : null,
                onSelected: (list) => setState(() => _picked = list),
              )
            : Text(shown.label(strings), style: text.titleLarge);
        final trailing = widget.trailing;

        return widget.builder(
          Padding(
            padding: EdgeInsets.fromLTRB(16, lists.length > 1 ? 20 : 24, 16, 8),
            // The trailing in the room the heading leaves, centered on it.
            child: trailing == null
                ? heading
                : Row(
                    children: [
                      heading,
                      const SizedBox(width: 16),
                      Expanded(child: trailing),
                    ],
                  ),
          ),
          [
            if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(strings.couldNotListSongs('${snapshot.error}'), style: text.bodyMedium),
              ),
            for (final (i, song) in songs.indexed)
              CurrentSong(
                song,
                builder: (context, current, playing) => SongMenu(
                  song,
                  builder: (context, menu) => ListTile(
                    contentPadding: SongTrailing.tilePadding,
                    selected: current,
                    // Its place among them, then its cover.
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: SongListHeader.numberWidth, child: SongNumber(i + 1)),
                        const SizedBox(width: SongListHeader.numberGap),
                        Thumbnail(song.coverArt, playing: playing),
                      ],
                    ),
                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: song.album == null
                        ? null
                        : Text(song.album!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: SongTrailing(song.id, song.duration, menu),
                    onTap: () => _play(context, songs, i),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
