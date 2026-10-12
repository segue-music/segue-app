import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../connect/connect.dart';
import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../app/page_area.dart';
import '../playlist/playlist_dialogs.dart';
import '../song/favorite_button.dart';
import '../song/song_link.dart';
import '../song/song_menu.dart';
import '../widgets/cover.dart';
import '../widgets/focus_ring.dart';
import '../widgets/menu_shortcuts.dart';
import '../widgets/themed_icon.dart';
import 'devices_sheet.dart';
import 'player_controls.dart';
import 'player_page.dart';
import 'queue_page.dart';
import 'sleep_timer_button.dart';
import 'volume_control.dart';

export 'player_controls.dart' show formatDuration;

/// What plays, wherever it plays, with the controls and the device picker. The song opens the full-screen player
/// ([_Song]). On a wide screen it stays under the full-screen player too, whose song closes it.
///
/// On a wide screen it goes in three parts, as most players on a computer have them: the song; in the middle, the
/// playback's buttons (play, filled, in theirs), between the heart and the lyrics, over the slider; and at the end, a
/// playlist to add the song to, the queue, the sleep timer, the devices and, on a computer, the volume. On a phone, the
/// slider is over the song and its few buttons, the rest in the full-screen player.
///
/// Each page has one, but for the pages of a [PageArea], under which the home's stays.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({this.lyrics, super.key});

  /// From how wide the bar has room for shuffle, repeat, the lyrics and the queue.
  static const wideFrom = 600.0;

  /// How opaque the bars at the bottom of a phone's screen are, this one and the home's sections': slightly
  /// see-through, the home's section showing through them.
  static const phoneOpacity = 0.98;

  /// How round the corners of the bars at the bottom of a phone's screen are: all four of this one's, the top two of
  /// the home's sections'.
  static const phoneCorner = Radius.circular(8);

  /// Under the full-screen player, whether it shows the lyrics: the bar's lyrics button turns them on and
  /// off there, and its song closes the player. Null under any other page, where the button opens the
  /// player with them, and the song opens it.
  final ValueNotifier<bool>? lyrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // The song's title and artist, a line each, and its cover as tall as the two, which sets the bar's height.
    final line = theme.textTheme.bodyMedium;
    final strings = AppLocalizations.of(context);
    final cover = 2 * _lineHeight(line, MediaQuery.textScalerOf(context));
    // The buttons as tall as the cover too, without the room Material leaves around them on a touch screen.
    final buttons = (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    // Shuffle, repeat, the lyrics and the queue need room; a phone-sized bar has none (they are in the
    // full-screen player).
    final wide = MediaQuery.sizeOf(context).width >= wideFrom;
    final lyrics = this.lyrics;

    if (PageArea.holds(context)) {
      return const SizedBox.shrink();
    }

    return NowPlayingBuilder(
      builder: (context, connect, now) {
        if (now == null) {
          return const SizedBox.shrink();
        }

        final song = _Song(now, cover: cover, style: line, wide: wide, lyrics: lyrics);
        final previous = IconButton(
          tooltip: strings.previous,
          icon: const ThemedIcon(HugeIcons.strokeRoundedPrevious),
          onPressed: () => runCommand(context, connect.previous),
        );
        final playIcon = ThemedIcon(now.playing ? HugeIcons.strokeRoundedPause : HugeIcons.strokeRoundedPlay);
        final next = IconButton(
          tooltip: strings.next,
          icon: const ThemedIcon(HugeIcons.strokeRoundedNext),
          onPressed: () => runCommand(context, connect.next),
        );
        final devices = IconButton(
          tooltip: strings.devices,
          icon: ThemedIcon(HugeIcons.strokeRoundedMonitorSpeaker, color: now.device == null ? null : colors.primary),
          onPressed: () => showDevicesSheet(context),
        );

        void toggle() => runCommand(context, connect.toggle);

        final row = wide
            ? Row(
                children: [
                  // As wide as the end, so that the playback's buttons are in the middle.
                  Expanded(
                    flex: 3,
                    child: Row(children: [Flexible(child: song)]),
                  ),
                  // The playback's buttons over the slider, at most 720 wide: a longer one is hard to take in at a
                  // glance. Around them, what has to do with the song: the heart, and its lyrics; as many on either
                  // side, so that play is over the slider's middle.
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // A bit smaller where they don't fit, on a screen just wide enough for this bar.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  switch (now.songId) {
                                    final id? => FavoriteButton(FavoriteKind.song, id),
                                    // Disabled for a song the hub couldn't give in the app's API, as a playlist to add
                                    // it to is.
                                    null => IconButton(
                                      tooltip: strings.addToFavorites,
                                      icon: const ThemedIcon(HugeIcons.strokeRoundedFavourite),
                                      onPressed: null,
                                    ),
                                  },
                                  ShuffleButton(now),
                                  previous,
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: IconButton.filled(
                                      tooltip: now.playing ? strings.pause : strings.play,
                                      icon: playIcon,
                                      onPressed: toggle,
                                    ),
                                  ),
                                  next,
                                  RepeatButton(now),
                                  switch (lyrics) {
                                    null => IconButton(
                                      tooltip: strings.showLyrics,
                                      icon: const ThemedIcon(HugeIcons.strokeRoundedMicVocal),
                                      onPressed: () => PlayerPage.open(context, lyrics: true),
                                    ),
                                    final shown => ValueListenableBuilder(
                                      valueListenable: shown,
                                      builder: (context, on, _) => IconButton(
                                        tooltip: on ? strings.hideLyrics : strings.showLyrics,
                                        icon: ThemedIcon(
                                          HugeIcons.strokeRoundedMicVocal,
                                          color: on ? colors.primary : null,
                                        ),
                                        onPressed: () => shown.value = !on,
                                      ),
                                    ),
                                  },
                                ],
                              ),
                            ),
                            SeekSlider(now),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Where the music goes, and what goes on beside it.
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AddToPlaylistButton(now),
                        IconButton(
                          tooltip: strings.queue,
                          icon: const ThemedIcon(HugeIcons.strokeRoundedPlaylist03),
                          onPressed: () => QueuePage.toggle(context),
                        ),
                        // The timer pauses this device's player: none while another device plays.
                        if (now.device == null) const SleepTimerButton(),
                        devices,
                        // The volume of the device it plays on, as most players on a computer have it.
                        if (VolumeControl.shown) VolumeControl(now),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: song),
                  previous,
                  IconButton(tooltip: now.playing ? strings.pause : strings.play, icon: playIcon, onPressed: toggle),
                  next,
                  devices,
                ],
              );

        // The same on every page that has it, and under the full-screen player on a wide screen: from one
        // to the next, it stays put rather than coming and going with them.
        return Hero(
          tag: NowPlayingBar,
          child: Material(
            // On a phone, slightly see-through, its corners slightly rounded: on the home, the section shows through it
            // and around them.
            color: wide ? colors.surfaceContainer : colors.surfaceContainer.withValues(alpha: phoneOpacity),
            shape: wide ? null : const RoundedRectangleBorder(borderRadius: BorderRadius.all(phoneCorner)),
            child: SafeArea(
              top: false,
              child: FocusTraversalGroup(
                policy: _BarTraversalPolicy.instance,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // On a phone, the slider over the whole bar; on a wide screen it is under the playback's buttons.
                    if (!wide) Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: SeekSlider(now)),
                    Padding(
                      // Less on the left and at the bottom than around the buttons, by the song's room inside: its
                      // cover stays 8 from the edge, and the buttons 6 from the bottom. On a wide screen, room over the
                      // buttons and under the slider, which would otherwise touch the screen's edge.
                      padding: wide ? const EdgeInsets.fromLTRB(4, 8, 8, 12) : const EdgeInsets.fromLTRB(4, 0, 8, 2),
                      child: IconButtonTheme(
                        data: IconButtonThemeData(style: buttons),
                        child: row,
                      ),
                    ),
                    // Where it plays, when that's another device, in a strip under the player. On a phone, where the
                    // strip would take room from the page, the devices button, tinted, says so.
                    if (wide && now.device != null)
                      Container(
                        width: double.infinity,
                        color: colors.primaryContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Row(
                          children: [
                            ThemedIcon(HugeIcons.strokeRoundedSpeaker, size: 16, color: colors.onPrimaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              now.playing ? strings.playingOn(now.device!) : strings.pausedOn(now.device!),
                              style: TextStyle(color: colors.onPrimaryContainer, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The song in the bar, its cover, title and artist. On a phone the whole of it opens the full-screen player, or closes
/// it, under it; on a wide screen, where its title and artist link, as the full-screen player's do, the cover alone,
/// nothing around the song lighting up for it. Right-clicked, held (on a wide screen, by its cover), or with the menu
/// key or OK held, it opens its menu, as a song in a list does ([songMenuItems]).
class _Song extends StatelessWidget {
  const _Song(this.now, {required this.cover, required this.style, required this.wide, required this.lyrics});

  final NowPlaying now;

  /// How tall its cover is.
  final double cover;

  /// Its title's and its artist's.
  final TextStyle? style;

  final bool wide;

  /// [NowPlayingBar.lyrics]: under the full-screen player, it closes the player.
  final ValueNotifier<bool>? lyrics;

  /// Opens its menu: where a pointer pressed it ([at]), or else over it. A song the hub couldn't give in the app's API
  /// has none.
  Future<void> _openMenu(BuildContext context, {Offset? at}) async {
    final song = now.song;

    if (song == null) {
      return;
    }

    final action = await showMenu<SongAction>(
      context: context,
      position: menuPosition(context, at: at),
      items: songMenuItems(context, favorite: ServicesScope.of(context).favorites.contains(FavoriteKind.song, song.id)),
    );

    if (action != null && context.mounted) {
      runSongAction(context, action, [song]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final tooltip = lyrics == null ? strings.openPlayer : strings.closePlayer;
    final cover = SizedBox.square(
      dimension: this.cover,
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: Cover(now.coverArt, size: 96, gapless: true)),
    );

    void openOrClose() => lyrics == null ? PlayerPage.open(context) : PageArea.navigatorOf(context).maybePop();

    if (wide) {
      return MenuShortcuts(
        onOpen: () => _openMenu(context),
        // Right-clicked anywhere on it. Held, on the cover alone: the links' tooltips would take a long press on them.
        child: GestureDetector(
          onSecondaryTapUp: (details) => _openMenu(context, at: details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The song's one stop for the keyboard and the remote, where the links take no focus.
                Tooltip(
                  message: tooltip,
                  child: FocusRing(
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      borderRadius: BorderRadius.circular(4),
                      onTap: openOrClose,
                      onLongPress: () => _openMenu(context),
                      child: cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeFocus(child: SongLink.title(now, style: style)),
                      ExcludeFocus(child: SongLink.artist(now, style: style)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MenuShortcuts(
      onOpen: () => _openMenu(context),
      child: Tooltip(
        message: tooltip,
        child: FocusRing(
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(8),
            onTap: openOrClose,
            onLongPress: () => _openMenu(context),
            onSecondaryTapUp: (details) => _openMenu(context, at: details.globalPosition),
            // Room around the cover and the lines, where the tint and the ring show, rounded as the cover is.
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  cover,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          now.title ?? strings.nothingPlaying,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Several artists apart by commas, where the media server has semicolons ("Run-DMC;
                        // Aerosmith").
                        Text(
                          (now.artist ?? '').replaceAll(';', ','),
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How tall a line of text in [style] is, at [scaler]'s size.
double _lineHeight(TextStyle? style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: ' ', style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  );

  try {
    return painter.preferredLineHeight;
  } finally {
    painter.dispose();
  }
}

/// Moving around the bar with the arrows (a TV remote's): left and right along its row of buttons, up and down
/// between that row and the slider (over it on a phone, under the playback's buttons on a wide screen), up from its
/// top out of the bar, and nowhere past its other ends. Flutter's own directional search looks at the whole screen,
/// where the album grid's rows built past the bottom of the screen lie under the bar, level with its buttons, and
/// could win.
class _BarTraversalPolicy extends ReadingOrderTraversalPolicy {
  _BarTraversalPolicy._();

  static final instance = _BarTraversalPolicy._();

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final here = currentNode.rect;
    final bar = [
      for (final node in currentNode.nearestScope!.traversalDescendants)
        if (node != currentNode && FocusTraversalGroup.maybeOfNode(node) == this) node,
    ];

    bool level(FocusNode node) => node.rect.top < here.bottom && node.rect.bottom > here.top;

    double away(FocusNode node) => (node.rect.center - here.center).distance;

    FocusNode? closest(Iterable<FocusNode> nodes) =>
        nodes.isEmpty ? null : nodes.reduce((a, b) => away(a) <= away(b) ? a : b);

    final target = closest(switch (direction) {
      TraversalDirection.left => bar.where((node) => level(node) && node.rect.center.dx < here.center.dx),
      TraversalDirection.right => bar.where((node) => level(node) && node.rect.center.dx > here.center.dx),
      TraversalDirection.up => bar.where((node) => node.rect.bottom <= here.top + 1),
      TraversalDirection.down => bar.where((node) => node.rect.top >= here.bottom - 1),
    });

    if (target != null) {
      requestFocusCallback(target);
      return true;
    }

    // From the top of the bar, up goes on as anywhere else; past its other edges, nowhere.
    return direction == TraversalDirection.up && super.inDirection(currentNode, direction);
  }
}
