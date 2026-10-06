import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../segue/client.dart';
import '../segue/protocol.dart';
import '../server/models.dart';
import '../services.dart';
import 'albums_view.dart';
import 'artists_view.dart';
import 'devices_sheet.dart';
import 'genres_view.dart';
import 'home_view.dart';
import 'now_playing_bar.dart';
import 'search_results.dart';

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
  genres('Gêneros', HugeIcons.strokeRoundedDashboardSquare01);

  const _Section(this.label, this.icon);

  final String label;

  /// The same selected or not: Hugeicons' free set has no filled icons. The selected section is on a
  /// tint.
  final IconData icon;
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  Timer? _typing;
  String _query = '';

  /// What the search bar found; null shows the section.
  Future<SearchResults>? _results;

  _Section _section = _Section.home;

  /// The sections opened so far: each loads the first time it is opened.
  final _opened = {_Section.home};

  void _select(_Section section) {
    setState(() {
      _section = section;
      _opened.add(section);
    });

    if (_results != null) {
      _clearSearch();
    }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final results = _results;
    final searchBar = SearchBar(
      controller: _search,
      hintText: 'Buscar álbum, artista ou música',
      leading: const Icon(HugeIcons.strokeRoundedSearch01),
      trailing: [
        ListenableBuilder(
          listenable: _search,
          builder: (context, _) => _search.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(HugeIcons.strokeRoundedCancel01),
                  onPressed: _clearSearch,
                ),
        ),
      ],
      elevation: const WidgetStatePropertyAll(0),
      constraints: const BoxConstraints(maxWidth: 600, minHeight: 44, maxHeight: 44),
      textInputAction: TextInputAction.search,
      onChanged: _typed,
      onSubmitted: _searchFor,
    );
    // Next to the title when there is room for both; on a phone, on a line of its own under it.
    final narrow = MediaQuery.sizeOf(context).width < 600;
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
              _Section.home => const HomeView(),
              _Section.albums => const AlbumsView(),
              _Section.artists => const ArtistsView(),
              _Section.genres => const GenresView(),
            },
          ),
        if (results != null) SearchResultsList(results),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        // The app's icon, which opens the home: on a wide screen, over the side rail.
        leading: IconButton(
          tooltip: _Section.home.label,
          icon: Image.asset('assets/logo.png', width: 32, height: 32),
          onPressed: () => _select(_Section.home),
        ),
        title: narrow
            ? Text(_section.label)
            : Row(
                children: [
                  Text(_section.label),
                  const SizedBox(width: 24),
                  Flexible(child: searchBar),
                ],
              ),
        bottom: narrow
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: searchBar),
              )
            : null,
        actions: [
          _HubStatus(client: services.connect.client),
          IconButton(
            tooltip: 'Aparelhos',
            icon: const Icon(HugeIcons.strokeRoundedComputerPhoneSync),
            onPressed: () => showDevicesSheet(context),
          ),
          IconButton(tooltip: 'Sair', icon: const Icon(HugeIcons.strokeRoundedLogout01), onPressed: widget.onSignOut),
        ],
      ),
      body: narrow
          ? sections
          : Row(
              children: [
                _SideRail(selected: _section, onSelected: _select),
                const VerticalDivider(width: 1),
                Expanded(child: sections),
              ],
            ),
      bottomNavigationBar: narrow
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NowPlayingBar(),
                NavigationBar(
                  selectedIndex: _section.index,
                  onDestinationSelected: (index) => _select(_Section.values[index]),
                  destinations: [
                    for (final section in _Section.values)
                      NavigationDestination(icon: Icon(section.icon), label: section.label),
                  ],
                ),
              ],
            )
          : const NowPlayingBar(),
    );
  }
}

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
                    icon: Icon(section.icon),
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
    // As big as the icon buttons beside it (Material 3's 40 pixels, padded to 48 where the theme pads
    // tap targets), so that the icons in the bar are evenly spaced.
    final size = Theme.of(context).materialTapTargetSize == MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 40.0;

    Widget status(String message, IconData icon) => Tooltip(
      message: message,
      child: SizedBox.square(
        dimension: size,
        child: Center(child: Icon(icon)),
      ),
    );

    if (client == null) {
      return status('Sem hub: só toca neste aparelho', HugeIcons.strokeRoundedUnlink02);
    }

    return ListenableBuilder(
      listenable: client,
      builder: (context, _) => switch (client.status) {
        HubStatus.connected => status('Conectado ao hub', HugeIcons.strokeRoundedCloudSavingDone01),
        HubStatus.connecting => status('Conectando ao hub…', HugeIcons.strokeRoundedCloudLoading),
        HubStatus.offline => status('Hub fora do ar; tentando de novo', HugeIcons.strokeRoundedUnlink02),
        HubStatus.rejected => status(
          client.lastClose?.code == CloseCode.replaced
              ? 'Este aparelho se conectou de novo em outro lugar (outra cópia do app aberta?)'
              : 'O hub recusou este aparelho',
          HugeIcons.strokeRoundedAlertCircle,
        ),
      },
    );
  }
}
