import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import '../equalizer_choice.dart';
import '../language_choice.dart';
import '../download_choice.dart';
import '../quality_choice.dart';
import '../replay_gain_choice.dart';
import '../segue/client.dart';
import '../segue/protocol.dart';
import '../server/models.dart';
import '../server/reachability.dart';
import '../server/server.dart';
import '../services.dart';
import '../theme_choice.dart';
import 'albums_view.dart';
import 'artists_view.dart';
import 'genres_view.dart';
import 'home_view.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'player_page.dart';
import 'playlists_view.dart';
import 'search_results.dart';
import 'settings_page.dart';
import 'shortcuts.dart';
import 'themed_icon.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.onSignOut,
    this.themeChoice,
    this.languageChoice,
    this.qualityChoice,
    this.downloadChoice,
    this.replayGainChoice,
    this.equalizerChoice,
    this.packageInfo,
    super.key,
  });

  final VoidCallback onSignOut;

  /// The theme picked, in the settings: light, dark or the system's; none, no choice of it.
  final ThemeChoice? themeChoice;

  /// The language picked, in the settings; none, no choice of it.
  final LanguageChoice? languageChoice;

  /// The quality the player streams in, picked in the settings; none, no choice of it.
  final QualityChoice? qualityChoice;

  /// How the app downloads, picked in the settings; none, no choice of it.
  final DownloadChoice? downloadChoice;

  /// How the player levels the songs' loudness, picked in the settings; none, no choice of it.
  final ReplayGainChoice? replayGainChoice;

  /// The equalizer the player plays through, set in the settings; none, no equalizer there.
  final EqualizerChoice? equalizerChoice;

  /// The app's version and build number, in the settings; none, no line of them.
  final PackageInfo? packageInfo;

  /// How long typing in the search bar has to stop before the search goes out, so that it isn't one
  /// per key.
  static const searchTypingPause = Duration(milliseconds: 300);

  @override
  State<HomePage> createState() => _HomePageState();
}

/// The library's sections, in the side rail (on a phone, in the bar at the bottom's [_Destination]s). The app's icon, in
/// the top bar, opens the home too, and on a wide screen it alone does. The search is a section on a phone only, where
/// its bar shows with it; on a wide screen the bar is always in the top bar.
enum _Section {
  home(HugeIcons.strokeRoundedHome01),
  albums(HugeIcons.strokeRoundedCd),
  artists(HugeIcons.strokeRoundedUser),
  genres(HugeIcons.strokeRoundedTag01),
  playlists(HugeIcons.strokeRoundedPlaylist01),
  search(HugeIcons.strokeRoundedSearch01);

  const _Section(this.icon);

  /// The same selected or not: Hugeicons' free set has no filled icons. The selected section is on a
  /// tint.
  final HugeIconData icon;

  String label(AppLocalizations strings) => switch (this) {
    home => strings.home,
    albums => strings.albums,
    artists => strings.artists,
    genres => strings.genres,
    playlists => strings.playlists,
    search => strings.search,
  };
}

/// On a phone, the bar at the bottom's destinations, fewer than the sections, which wouldn't fit its width: the home,
/// the search, which shows the genres until something is searched, and the library, whose albums, artists and playlists
/// are tabs at its top.
enum _Destination {
  home(HugeIcons.strokeRoundedHome01),
  search(HugeIcons.strokeRoundedSearch01),
  library(HugeIcons.strokeRoundedLibrary);

  const _Destination(this.icon);

  final HugeIconData icon;

  /// The library's tabs, in their order.
  static const libraryTabs = [_Section.albums, _Section.artists, _Section.playlists];

  /// The sections side by side, in the order a swipe goes through them: the destinations', the library's as its tabs.
  static const sections = [_Section.home, _Section.search, ...libraryTabs];

  /// The destination [section] is in.
  static _Destination of(_Section section) => switch (section) {
    _Section.home => home,
    _Section.search || _Section.genres => search,
    _Section.albums || _Section.artists || _Section.playlists => library,
  };

  String label(AppLocalizations strings) => switch (this) {
    home => strings.home,
    search => strings.search,
    library => strings.library,
  };
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  Timer? _typing;
  String _query = '';
  final _searchFocus = FocusNode(debugLabel: 'Search');

  /// On a TV, whether the search bar takes what is typed: from the remote's center button on it, which opens the
  /// keyboard, until the focus leaves it.
  bool _searchEditable = false;

  /// What the search bar found; null shows the section.
  Future<SearchResults>? _results;

  _Section _section = _Section.home;

  /// The order of the albums tab: by name, or a home row's, whose title opened it.
  AlbumOrder _albumOrder = AlbumOrder.name;

  /// Whether the albums tab shows the downloaded alone, rather than the library's in [_albumOrder].
  bool _albumsDownloaded = false;

  /// The sections opened so far: each loads the first time it is opened. On a phone the pages a swipe goes through
  /// build each as it first comes into sight.
  final _opened = {_Section.home};

  /// On a phone, the library's tabs: the one picked, which the library opens on again.
  late final _libraryTabs = TabController(length: _Destination.libraryTabs.length, vsync: this);

  /// The room on either side of a library tab's name, less than Material's 16, for the three to fit in the top bar,
  /// beside its buttons.
  static const _libraryTabPadding = 12.0;

  /// On a wide screen, the page area's navigator, and the pages opened in it.
  final _pages = GlobalKey<NavigatorState>();
  final _history = PageHistory();
  late final _observers = [_history, TopPageTraversal()];

  /// Whether the media server is in reach, which the sections load by: as it changes, they load anew, from the server
  /// or from what was downloaded.
  Reachability? _reachability;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_searchFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reachability = ServicesScope.of(context).reachability;

    if (reachability != _reachability) {
      _reachability?.removeListener(_reachabilityChanged);
      _reachability = reachability?..addListener(_reachabilityChanged);
    }
  }

  void _reachabilityChanged() => setState(() {});

  /// The settings' page, by which the top bar's button tells it on top, also once it opens again going forward
  /// ([PageHistory] opens a page again with its settings).
  static const _settings = RouteSettings(name: 'settings');

  /// A phone's screen, or a window as narrow: the sections in a bar at the bottom, and pages over all of it.
  bool get _narrow => MediaQuery.sizeOf(context).width < 600;

  /// Opens the settings in the page area, over the section, which a section picked shows again. With them open on top
  /// (on a wide screen, where the top bar stays over them), goes back instead, as the top bar's arrow does, rather than
  /// opening them again over themselves. From here, above the area, its navigator is the home's own.
  void _toggleSettings() {
    if (_history.current?.settings.name == _settings.name) {
      _history.back();
      return;
    }

    _pages.currentState?.push(
      MaterialPageRoute<void>(
        settings: _settings,
        builder: (_) => SettingsPage(
          themeChoice: widget.themeChoice,
          languageChoice: widget.languageChoice,
          qualityChoice: widget.qualityChoice,
          downloadChoice: widget.downloadChoice,
          replayGainChoice: widget.replayGainChoice,
          equalizerChoice: widget.equalizerChoice,
          packageInfo: widget.packageInfo,
          onSignOut: widget.onSignOut,
        ),
      ),
    );
  }

  /// Goes to the search bar, as the key '/' does: on a phone, to the search, a section of its own, where the bar is.
  void _focusSearch() {
    if (_narrow && _section != _Section.search) {
      _select(_Section.search);
    }

    _searchFocus.requestFocus();
  }

  /// Shows [section], closing the pages over it.
  void _select(_Section section) {
    _history.closeAll();

    if (_Destination.libraryTabs.contains(section)) {
      _libraryTabs.index = _Destination.libraryTabs.indexOf(section);
    }

    setState(() {
      _section = section;
      _opened.add(section);
    });

    // On a wide screen the results show over the section, which closes them. On a phone they are a section of their
    // own, which keeps them as the others keep theirs.
    if (_results != null && !_narrow) {
      _clearSearch();
    }
  }

  /// On a phone, shows [destination]: the library on the tab picked last. The search picked again, shown with no page
  /// over it, goes to its bar, ready to type; with a page over it, it shows again, as another destination would.
  void _open(_Destination destination) {
    if (destination == _Destination.search && _Destination.of(_section) == destination && !_history.canGoBack) {
      _searchFocus.requestFocus();
      return;
    }

    _select(switch (destination) {
      _Destination.home => _Section.home,
      _Destination.search => _Section.search,
      _Destination.library => _Destination.libraryTabs[_libraryTabs.index],
    });
  }

  /// On a phone, a swipe at [page] of the sections side by side: the one at the closest page shown, the bar at the
  /// bottom and the library's tabs saying so, and between two of the tabs, the line under them on its way from one to
  /// the other, as over a TabBarView.
  void _swiped(double page) {
    final section = _Destination.sections[page.round()];

    if (section != _section) {
      final tab = _Destination.libraryTabs.indexOf(section);

      if (tab >= 0) {
        _libraryTabs.index = tab;
      }

      setState(() => _section = section);
    }

    final fromFirstTab = page - _Destination.sections.indexOf(_Destination.libraryTabs.first);

    if (fromFirstTab >= 0 && !_libraryTabs.indexIsChanging) {
      _libraryTabs.offset = (fromFirstTab - _libraryTabs.index).clamp(-1.0, 1.0);
    }
  }

  /// The albums tab, in [order].
  void _showAlbums(AlbumOrder order) {
    setState(() {
      _albumOrder = order;
      _albumsDownloaded = false;
    });
    _select(_Section.albums);
  }

  void _typed(String text) {
    _typing?.cancel();
    _typing = Timer(HomePage.searchTypingPause, () => _searchFor(text));
  }

  void _searchFor(String text) {
    _typing?.cancel();
    final query = text.trim();

    if (query == _query) {
      return;
    }

    // The results show where the sections do, under the pages, which close.
    if (query.isNotEmpty) {
      _history.closeAll();
    }

    setState(() {
      _query = query;
      _results = query.isEmpty ? null : ServicesScope.of(context).api.search(query);
    });
  }

  /// On a TV, opens the keyboard on the search bar. Read-only until then, it leaves the keyboard closed as the focus
  /// comes to it, which would otherwise cover the bottom half of the screen and take the D-pad, on the way across the
  /// top bar or up to it from a page. Elsewhere a tap opens it itself.
  void _openKeyboard() {
    if (!_searchEditable) {
      // The field opens the keyboard as it stops being read-only.
      setState(() => _searchEditable = true);
    } else {
      // Typing, with the keyboard closed since: open again.
      _searchFocus.context?.findAncestorStateOfType<EditableTextState>()?.requestKeyboard();
    }
  }

  /// On a TV, the search bar read-only again once the focus leaves it, for the keyboard to stay closed as it comes back.
  void _searchFocusChanged() {
    if (!_searchFocus.hasFocus && _searchEditable) {
      setState(() => _searchEditable = false);
    }
  }

  /// A touch off the search bar closes the keyboard: Flutter leaves the field focused on a touch, on a phone or a
  /// tablet, unfocusing it only for a mouse. With the keyboard open, that is all it does, rather than also doing what it
  /// touched (a genre, a song found, a button), as one closes the keyboard to see what was found: it takes the gesture
  /// from what is under it, as [TapRegion.consumeOutsideTaps] does, but only then.
  void _tappedOutsideSearch(PointerDownEvent event) {
    if (_searchFocus.hasFocus && View.of(context).viewInsets.bottom > 0) {
      GestureBinding.instance.gestureArena.add(event.pointer, _GestureTaker()).resolve(GestureDisposition.accepted);
    }

    _searchFocus.unfocus();
  }

  void _clearSearch() {
    _search.clear();
    _searchFor('');
  }

  @override
  void dispose() {
    _reachability?.removeListener(_reachabilityChanged);
    _typing?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _history.dispose();
    _libraryTabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final strings = AppLocalizations.of(context);
    final results = _results;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = _narrow;
    // On a wide screen the search is the top bar's, not a section: a window narrowed to the search and widened again
    // shows the home. On a phone the genres are the search's, before something is searched.
    final shown = switch (_section) {
      _Section.search when !narrow => _Section.home,
      _Section.genres when narrow => _Section.search,
      final section => section,
    };
    // Shown in another's place, as the window changes width, a section loads too.
    _opened.add(shown);
    final television = MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional;
    // On a phone, as wide as the top bar leaves it; on a wide screen, at most 600 and two fifths of the window, which on
    // a TV's (960 wide) leaves the top bar more than the search.
    final searchWidth = narrow ? width : min(600.0, width * 0.4);
    // Esc, as the clear button, staying in the bar for another search; with nothing typed, out of it, as Esc goes out
    // of anything else (UnfocusShortcut).
    final searchBar = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_search.text.isEmpty) {
            FocusManager.instance.primaryFocus?.unfocus();
          } else {
            _clearSearch();
          }
        },
      },
      // The whole bar counts as the text field, its icon and clear button too: a tap on them leaves the field focused,
      // and the keyboard open.
      child: TextFieldTapRegion(
        child: SearchBar(
          controller: _search,
          focusNode: _searchFocus,
          readOnly: television && !_searchEditable,
          // A tap, or the remote's center button.
          onTap: television ? _openKeyboard : null,
          onTapOutside: _tappedOutsideSearch,
          // On a phone, in the top bar, the search's name, in the room its name would take, rather than what it finds,
          // which wouldn't fit beside the top bar's buttons.
          hintText: narrow ? strings.search : strings.searchHint,
          leading: const ThemedIcon(HugeIcons.strokeRoundedSearch01),
          trailing: [
            ListenableBuilder(
              listenable: _search,
              builder: (context, _) => _search.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: strings.clear,
                      icon: const ThemedIcon(HugeIcons.strokeRoundedCancel01),
                      onPressed: _clearSearch,
                    ),
            ),
          ],
          elevation: const WidgetStatePropertyAll(0),
          constraints: BoxConstraints(maxWidth: searchWidth, minHeight: 44, maxHeight: 44),
          textInputAction: TextInputAction.search,
          onChanged: _typed,
          onSubmitted: _searchFor,
        ),
      ),
    );
    final logo = IconButton(
      tooltip: _Section.home.label(strings),
      icon: Image.asset('assets/logo.png', width: 32, height: 32),
      onPressed: () => _select(_Section.home),
    );
    // The theme, the language, the quality, the volume's normalization, the equalizer and signing out are in the
    // settings, a page of their own, whose button comes after the hub's status, which stays in sight: signing out, which
    // forgets the token, two clicks away rather than one in the corner.
    final actions = [
      _HubStatus(client: services.connect.client, reachability: services.reachability),
      IconButton(
        tooltip: strings.settings,
        icon: const ThemedIcon(HugeIcons.strokeRoundedSettings01),
        onPressed: _toggleSettings,
      ),
    ];

    // A section's view, in the wide screen's stack or the phone's pages: anew as the media server goes out of reach or
    // comes back, so that it shows what was downloaded, or all again.
    final reachable = services.reachability?.value ?? true;
    Widget view(_Section section) => KeyedSubtree(
      key: ValueKey((section, reachable)),
      child: switch (section) {
        _Section.home => HomeView(onShowAll: _showAlbums),
        _Section.albums => AlbumsView(
          order: _albumOrder,
          onOrder: (order) => setState(() {
            _albumOrder = order;
            _albumsDownloaded = false;
          }),
          downloaded: _albumsDownloaded,
          onDownloaded: () => setState(() => _albumsDownloaded = true),
        ),
        _Section.artists => const ArtistsView(),
        _Section.genres => const GenresView(),
        _Section.playlists => const PlaylistsView(),
        // On a phone, the genres until a search finds something, which come back as it is cleared, where they were.
        _Section.search => Stack(
          fit: StackFit.expand,
          children: [
            Visibility(visible: results == null, maintainState: true, child: const GenresView()),
            if (results != null) SearchResultsList(results),
          ],
        ),
      },
    );

    // The page area's navigator, over [first]: the sections, which the pages open over. The same navigator in both
    // layouts, by its key, so that the pages stay open as the window is narrowed or widened.
    Widget pageArea(Widget first) => NavigatorPopHandler(
      // The system's back (Android's, a TV remote's) closes the page on top, rather than the app.
      onPopWithResult: (_) => _pages.currentState?.maybePop(),
      child: Navigator(
        key: _pages,
        observers: _observers,
        // The arrows (a TV remote's) go on from a page's edges to the bars around it, where a navigator's pages would
        // keep them.
        routeDirectionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
        pages: [MaterialPage<void>(key: const ValueKey(_Section), child: first)],
        onDidRemovePage: (_) {},
      ),
    );

    // On a phone the bars at the bottom stay, the player's and the destinations', and pages open over the rest, in the
    // page area, each with its own top bar and back arrow, over the section, which has the app's name in its top bar,
    // the search bar, or the library's tabs, and which a swipe changes for the next. The full-screen player and the
    // queue cover everything.
    if (narrow) {
      final destination = _Destination.of(shown);
      return SearchShortcut(
        onSearch: _focusSearch,
        child: PageArea(
          navigator: _pages,
          history: _history,
          underTopBar: false,
          child: Scaffold(
            // The pages go on behind the bars, showing through the gap between them; their lists end clear of them, by
            // the room MediaQuery says they take.
            extendBody: true,
            body: pageArea(
              Scaffold(
                // On the home, the app's icon and its name; in the search and the library, what there is to use
                // there, in their place: the bar at the bottom says where it is, and opens the home.
                appBar: AppBar(
                  // The app's icon, 16 from the edge, lined up with what the home shows under it: in the middle of a
                  // slot 64 wide, rather than Material's 56, which would leave it at 12.
                  leading: destination == _Destination.home ? logo : null,
                  leadingWidth: 64,
                  titleSpacing: switch (destination) {
                    // The app's name where a page's title is, after its back arrow: 72 from the edge.
                    _Destination.home => 8,
                    // The search bar 16 from the edge, lined up with what the search shows under it.
                    _Destination.search => 16,
                    // The first tab's name 16 from the edge, past the room around it.
                    _Destination.library => 16 - _libraryTabPadding,
                  },
                  title: switch (destination) {
                    _Destination.home => Text(strings.appName),
                    _Destination.search => searchBar,
                    // As wide as their names, from the left, scrolling sideways where they don't fit; with no line under
                    // them across the bar, which has none.
                    _Destination.library => TabBar(
                      controller: _libraryTabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: _libraryTabPadding),
                      dividerHeight: 0,
                      tabs: [for (final section in _Destination.libraryTabs) Tab(text: section.label(strings))],
                      onTap: (index) => _select(_Destination.libraryTabs[index]),
                    ),
                  },
                  actions: actions,
                ),
                // A swipe goes from a section to the next, as the bar at the bottom and the library's tabs line them up.
                body: _SwipedSections(
                  page: _Destination.sections.indexOf(shown),
                  onSwiped: _swiped,
                  children: [
                    // Off the page shown, a section takes no focus, which would scroll its page into sight.
                    for (final section in _Destination.sections)
                      ExcludeFocus(excluding: section != shown, child: view(section)),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Above the sections' bar, which keeps clear of the system's at the bottom of the screen: the player's
                // needn't, and a small gap sets the two apart, alike in color. Nothing playing, there is no player to set
                // apart.
                MediaQuery.removePadding(context: context, removeBottom: true, child: const NowPlayingBar()),
                ListenableBuilder(
                  listenable: services.connect,
                  builder: (context, _) => SizedBox(height: services.connect.nowPlaying == null ? 0 : 2),
                ),
                // Its top corners rounded as the player's, the section showing around them.
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: NowPlayingBar.phoneCorner),
                  child: NavigationBar(
                    // A bit lower than Material's 80, with less room above and below the icons and their names.
                    height: 68,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainer
                        .withValues(alpha: NowPlayingBar.phoneOpacity),
                    selectedIndex: destination.index,
                    onDestinationSelected: (index) => _open(_Destination.values[index]),
                    destinations: [
                      for (final destination in _Destination.values)
                        NavigationDestination(icon: ThemedIcon(destination.icon), label: destination.label(strings)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // On a wide screen the bars stay, the top one, the side rail and the player's, and pages open between them, in the
    // page area. The arrows beside the app's icon go back and forward through them, as do the keyboard's. They sit
    // close together, as a browser's: smaller buttons than the rest, without the room Material leaves around them on a
    // touch screen.
    const arrow = 32.0;
    final arrows = IconButton.styleFrom(
      padding: const EdgeInsets.all(4),
      minimumSize: const Size.square(arrow),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final sections = Stack(
      fit: StackFit.expand,
      children: [
        // Each section stays underneath once opened, also while searching: going back to it, or
        // clearing the search, finds it where it was. Hidden, it takes no focus, which the remote would otherwise move
        // to its albums, under the one shown.
        for (final section in _opened)
          Visibility(
            key: ValueKey(section),
            visible: results == null && section == shown,
            maintainState: true,
            child: view(section),
          ),
        // Over the section.
        if (results != null) SearchResultsList(results),
      ],
    );
    return SearchShortcut(
      onSearch: _focusSearch,
      child: HistoryShortcuts(
        history: _history,
        // The home's own scope, where the focus goes back to (as Esc leaves the search bar): in the app's, outside the
        // home, the keys wouldn't reach the shortcuts.
        child: FocusScope(
          autofocus: true,
          child: PageArea(
            navigator: _pages,
            history: _history,
            underTopBar: true,
            child: Scaffold(
              appBar: AppBar(
                // The app's icon, over the side rail, which opens the home, and the arrows beside it.
                leading: ListenableBuilder(
                  listenable: _history,
                  builder: (context, _) => Row(
                    children: [
                      SizedBox.square(dimension: kToolbarHeight, child: logo),
                      IconButton(
                        tooltip: strings.back,
                        style: arrows,
                        icon: const ThemedIcon(HugeIcons.strokeRoundedArrowLeft02),
                        onPressed: _history.canGoBack ? _history.back : null,
                      ),
                      IconButton(
                        tooltip: strings.forward,
                        style: arrows,
                        icon: const ThemedIcon(HugeIcons.strokeRoundedArrowRight02),
                        onPressed: _history.canGoForward ? _history.forward : null,
                      ),
                    ],
                  ),
                ),
                leadingWidth: kToolbarHeight + 2 * arrow,
                // The search bar is the title, which the app bar centers on the window, moving it aside where the
                // middle has no room for it.
                title: searchBar,
                centerTitle: true,
                actions: actions,
              ),
              body: Row(
                children: [
                  _SideRail(selected: shown, onSelected: _select),
                  const VerticalDivider(width: 1),
                  Expanded(
                    // A Material of its own for the lists' ink, which the page's transition would paint over.
                    child: pageArea(Material(type: MaterialType.transparency, child: sections)),
                  ),
                ],
              ),
              // Under the full-screen player, its lyrics button turns them on and off there, and its song closes it.
              bottomNavigationBar: ListenableBuilder(
                listenable: _history,
                builder: (context, _) => NowPlayingBar(
                  lyrics: switch (_history.current) {
                    final PlayerRoute player => player.lyrics,
                    _ => null,
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On a phone, the sections side by side, [page] the one shown, a swipe going from one to the next. Each stays once
/// built, as on a wide screen they stay underneath: swiping back to it, or picking it in the bar at the bottom, finds it
/// where it was.
class _SwipedSections extends StatefulWidget {
  const _SwipedSections({required this.page, required this.onSwiped, required this.children});

  /// The section shown, which a section picked elsewhere (in the bar at the bottom, a tab) changes at once, as without
  /// swiping.
  final int page;

  /// Where a swipe is, as it goes: the first section's page is 0. Not called as a section is picked elsewhere.
  final ValueChanged<double> onSwiped;

  final List<Widget> children;

  @override
  State<_SwipedSections> createState() => _SwipedSectionsState();
}

class _SwipedSectionsState extends State<_SwipedSections> {
  late final _pages = PageController(initialPage: widget.page);

  /// Whether the page is changing for a section picked elsewhere: in the home's build, where
  /// [_SwipedSections.onSwiped] couldn't change the section, and needn't.
  bool _picking = false;

  @override
  void didUpdateWidget(_SwipedSections oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_pages.hasClients && _pages.page?.round() != widget.page) {
      _picking = true;
      _pages.jumpToPage(widget.page);
      _picking = false;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollUpdateNotification>(
    onNotification: (notification) {
      // The pages' own, not a list's in a section.
      final page = notification.depth == 0 ? (notification.metrics as PageMetrics).page : null;

      if (page != null && !_picking) {
        widget.onSwiped(page);
      }

      return false;
    },
    child: PageView(
      controller: _pages,
      children: [for (final child in widget.children) _KeptAlive(child: child)],
    ),
  );
}

/// Keeps [child] once built, out of sight in a [PageView] as a swipe leaves it.
class _KeptAlive extends StatefulWidget {
  const _KeptAlive({required this.child});

  final Widget child;

  @override
  State<_KeptAlive> createState() => _KeptAliveState();
}

class _KeptAliveState extends State<_KeptAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// What takes a gesture in the arena from the recognizers of what was touched, and does nothing with it.
class _GestureTaker implements GestureArenaMember {
  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {}
}

/// How wide an icon button is: Material 3's 40 pixels, padded to 48 where the theme pads tap targets.
double _buttonSize(BuildContext context) =>
    Theme.of(context).materialTapTargetSize == MaterialTapTargetSize.padded ? kMinInteractiveDimension : 40.0;

/// The side rail: the sections' icons, each named by its tooltip, but the home's, which the app's icon above it
/// opens, and the search's, which is the top bar's. NavigationRail's highlight is 56 px wide, from one edge of so
/// narrow a rail to the other; here it is the icon's button's. The tooltip shows to the right of its icon, level with
/// it: below, where tooltips go, it would cover the icon under it.
class _SideRail extends StatelessWidget {
  const _SideRail({required this.selected, required this.onSelected});

  final _Section selected;
  final ValueChanged<_Section> onSelected;

  /// Where a tooltip's top left corner goes: to the right of its icon, level with it, as far from its center as a
  /// tooltip below would be.
  static Offset _besideIcon(TooltipPositionContext context) =>
      Offset(context.target.dx + context.verticalOffset, context.target.dy - context.tooltipSize.height / 2);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);
    // NavigationRail's colors: the selected section on a tint.
    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.secondaryContainer : null,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.onSecondaryContainer : colors.onSurfaceVariant,
      ),
    );
    return SizedBox(
      width: 56,
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final section in _Section.values)
            if (section != _Section.home && section != _Section.search)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Tooltip(
                  message: section.label(strings),
                  positionDelegate: _besideIcon,
                  child: IconButton(
                    isSelected: section == selected,
                    icon: ThemedIcon(section.icon),
                    style: style,
                    onPressed: () => onSelected(section),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Whether Connect works, the hub's connection, at a glance; and, while the media server is out of reach
/// ([reachability]), that the app shows only what was downloaded.
class _HubStatus extends StatelessWidget {
  const _HubStatus({required this.client, this.reachability});

  final SegueClient? client;
  final Reachability? reachability;

  @override
  Widget build(BuildContext context) {
    final client = this.client;
    final reachability = this.reachability;
    final strings = AppLocalizations.of(context);
    // As big as the icon buttons beside it, so that the icons in the bar are evenly spaced.
    final size = _buttonSize(context);

    Widget status(String message, HugeIconData icon) => Tooltip(
      message: message,
      child: SizedBox.square(
        dimension: size,
        child: Center(child: ThemedIcon(icon)),
      ),
    );

    return ListenableBuilder(
      listenable: Listenable.merge([?client, ?reachability]),
      builder: (context, _) {
        if (reachability != null && !reachability.value) {
          return status(strings.serverUnreachable, HugeIcons.strokeRoundedWifiDisconnected02);
        }

        if (client == null) {
          return status(strings.noHub, HugeIcons.strokeRoundedUnlink02);
        }

        return switch (client.status) {
          HubStatus.connected => status(strings.hubConnected, HugeIcons.strokeRoundedCloudCheck),
          HubStatus.connecting => status(strings.hubConnecting, HugeIcons.strokeRoundedCloudLoading),
          HubStatus.offline => status(strings.hubOffline, HugeIcons.strokeRoundedCloudOff),
          HubStatus.rejected => status(
            client.lastClose?.code == CloseCode.replaced ? strings.hubReplaced : strings.hubRejected,
            HugeIcons.strokeRoundedCloudAlert,
          ),
        };
      },
    );
  }
}
