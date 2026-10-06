import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../segue/client.dart';
import '../segue/protocol.dart';
import '../server/models.dart';
import '../server/server.dart';
import '../services.dart';
import 'albums_view.dart';
import 'artists_view.dart';
import 'devices_sheet.dart';
import 'genres_view.dart';
import 'home_view.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'player_page.dart';
import 'search_results.dart';
import 'shortcuts.dart';
import 'themed_icon.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.onSignOut, super.key});

  final VoidCallback onSignOut;

  /// How long typing in the search bar has to stop before the search goes out, so that it isn't one
  /// per key.
  static const searchTypingPause = Duration(milliseconds: 300);

  @override
  State<HomePage> createState() => _HomePageState();
}

/// The library's sections, in the side rail (or, on a phone, the bar at the bottom). The app's icon, in the top
/// bar, opens the home too, and on a wide screen it alone does.
enum _Section {
  home('Início', HugeIcons.strokeRoundedHome01),
  albums('Álbuns', HugeIcons.strokeRoundedCd),
  artists('Artistas', HugeIcons.strokeRoundedUser),
  genres('Gêneros', HugeIcons.strokeRoundedTag01);

  const _Section(this.label, this.icon);

  final String label;

  /// The same selected or not: Hugeicons' free set has no filled icons. The selected section is on a
  /// tint.
  final HugeIconData icon;
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  Timer? _typing;
  String _query = '';

  /// What the search bar found; null shows the section.
  Future<SearchResults>? _results;

  _Section _section = _Section.home;

  /// The order of the albums tab: by name, or a home row's, whose title opened it.
  AlbumOrder _albumOrder = AlbumOrder.name;

  /// The sections opened so far: each loads the first time it is opened.
  final _opened = {_Section.home};

  /// On a wide screen, the page area's navigator, and the pages opened in it.
  final _pages = GlobalKey<NavigatorState>();
  final _history = PageHistory();
  late final _observers = [_history];

  /// Shows [section], closing the pages over it.
  void _select(_Section section) {
    _history.closeAll();
    setState(() {
      _section = section;
      _opened.add(section);
    });

    if (_results != null) {
      _clearSearch();
    }
  }

  /// The albums tab, in [order].
  void _showAlbums(AlbumOrder order) {
    setState(() => _albumOrder = order);
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

  void _clearSearch() {
    _search.clear();
    _searchFor('');
  }

  @override
  void dispose() {
    _typing?.cancel();
    _search.dispose();
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final results = _results;
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
      child: SearchBar(
        controller: _search,
        hintText: 'Buscar álbum, artista ou música',
        leading: const ThemedIcon(HugeIcons.strokeRoundedSearch01),
        trailing: [
          ListenableBuilder(
            listenable: _search,
            builder: (context, _) => _search.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const ThemedIcon(HugeIcons.strokeRoundedCancel01),
                    onPressed: _clearSearch,
                  ),
          ),
        ],
        elevation: const WidgetStatePropertyAll(0),
        constraints: const BoxConstraints(maxWidth: 600, minHeight: 44, maxHeight: 44),
        textInputAction: TextInputAction.search,
        onChanged: _typed,
        onSubmitted: _searchFor,
      ),
    );
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final logo = IconButton(
      tooltip: _Section.home.label,
      icon: Image.asset('assets/logo.png', width: 32, height: 32),
      onPressed: () => _select(_Section.home),
    );
    final actions = [
      _HubStatus(client: services.connect.client),
      IconButton(
        tooltip: 'Aparelhos',
        icon: const ThemedIcon(HugeIcons.strokeRoundedMonitorSpeaker),
        onPressed: () => showDevicesSheet(context),
      ),
      IconButton(tooltip: 'Sair', icon: const ThemedIcon(HugeIcons.strokeRoundedLogout01), onPressed: widget.onSignOut),
    ];
    final sections = Stack(
      fit: StackFit.expand,
      children: [
        // Each section stays underneath once opened, also while searching: going back to it, or
        // clearing the search, finds it where it was.
        for (final section in _opened)
          Offstage(
            key: ValueKey(section),
            offstage: results != null || section != _section,
            child: switch (section) {
              _Section.home => HomeView(onShowAll: _showAlbums),
              _Section.albums => AlbumsView(
                order: _albumOrder,
                onOrder: (order) => setState(() => _albumOrder = order),
              ),
              _Section.artists => const ArtistsView(),
              _Section.genres => const GenresView(),
            },
          ),
        if (results != null) SearchResultsList(results),
      ],
    );

    // On a phone, the section's name on top, with the search bar on a line of its own under it, and the sections at
    // the bottom. Pages open over all of it.
    if (narrow) {
      return Scaffold(
        appBar: AppBar(
          // The app's icon, which opens the home.
          leading: logo,
          title: Text(_section.label),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: searchBar),
          ),
          actions: actions,
        ),
        body: sections,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NowPlayingBar(),
            NavigationBar(
              selectedIndex: _section.index,
              onDestinationSelected: (index) => _select(_Section.values[index]),
              destinations: [
                for (final section in _Section.values)
                  NavigationDestination(icon: ThemedIcon(section.icon), label: section.label),
              ],
            ),
          ],
        ),
      );
    }

    // On a wide screen the bars stay, the top one, the side rail and the player's, and pages open between them, in the
    // page area. The arrows beside the app's icon go back and forward through them, as do the keyboard's.
    final arrow = _buttonSize(context);
    return HistoryShortcuts(
      history: _history,
      // The home's own scope, where the focus goes back to (as Esc leaves the search bar): in the app's, outside the
      // home, the keys wouldn't reach the shortcuts.
      child: FocusScope(
        autofocus: true,
        child: PageArea(
          navigator: _pages,
          history: _history,
          child: Scaffold(
            appBar: AppBar(
              // The app's icon, over the side rail, which opens the home, and the arrows beside it.
              leading: ListenableBuilder(
                listenable: _history,
                builder: (context, _) => Row(
                  children: [
                    SizedBox.square(dimension: kToolbarHeight, child: logo),
                    IconButton(
                      tooltip: 'Voltar',
                      icon: const ThemedIcon(HugeIcons.strokeRoundedArrowLeft02),
                      onPressed: _history.canGoBack ? _history.back : null,
                    ),
                    IconButton(
                      tooltip: 'Avançar',
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
                _SideRail(selected: _section, onSelected: _select),
                const VerticalDivider(width: 1),
                Expanded(
                  // The system's back (Android's, a TV remote's) closes the page on top, rather than the app.
                  child: NavigatorPopHandler(
                    onPopWithResult: (_) => _pages.currentState?.maybePop(),
                    child: Navigator(
                      key: _pages,
                      observers: _observers,
                      pages: [
                        // A Material of its own for the lists' ink, which the page's transition would paint over.
                        MaterialPage<void>(
                          key: const ValueKey(_Section),
                          child: Material(type: MaterialType.transparency, child: sections),
                        ),
                      ],
                      onDidRemovePage: (_) {},
                    ),
                  ),
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
    );
  }
}

/// How wide an icon button is: Material 3's 40 pixels, padded to 48 where the theme pads tap targets.
double _buttonSize(BuildContext context) =>
    Theme.of(context).materialTapTargetSize == MaterialTapTargetSize.padded ? kMinInteractiveDimension : 40.0;

/// The side rail: the sections' icons, each named by its tooltip, but the home's, which the app's icon above it
/// opens. NavigationRail's highlight is 56 px wide, from one edge of so narrow a rail to the other; here it is the
/// icon's button's. The tooltip shows to the right of its icon, level with it: below, where tooltips go, it would
/// cover the icon under it.
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
            if (section != _Section.home)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Tooltip(
                  message: section.label,
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

/// Whether Connect works: the hub's connection, at a glance.
class _HubStatus extends StatelessWidget {
  const _HubStatus({required this.client});

  final SegueClient? client;

  @override
  Widget build(BuildContext context) {
    final client = this.client;
    // As big as the icon buttons beside it, so that the icons in the bar are evenly spaced.
    final size = _buttonSize(context);

    Widget status(String message, HugeIconData icon) => Tooltip(
      message: message,
      child: SizedBox.square(
        dimension: size,
        child: Center(child: ThemedIcon(icon)),
      ),
    );

    if (client == null) {
      return status('Sem hub: só toca neste aparelho', HugeIcons.strokeRoundedUnlink02);
    }

    return ListenableBuilder(
      listenable: client,
      builder: (context, _) => switch (client.status) {
        HubStatus.connected => status('Conectado ao hub', HugeIcons.strokeRoundedCloudCheck),
        HubStatus.connecting => status('Conectando ao hub…', HugeIcons.strokeRoundedCloudLoading),
        HubStatus.offline => status('Hub fora do ar; tentando de novo', HugeIcons.strokeRoundedCloudOff),
        HubStatus.rejected => status(
          client.lastClose?.code == CloseCode.replaced
              ? 'Este aparelho se conectou de novo em outro lugar (outra cópia do app aberta?)'
              : 'O hub recusou este aparelho',
          HugeIcons.strokeRoundedCloudAlert,
        ),
      },
    );
  }
}
