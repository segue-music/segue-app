import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'cover.dart';
import 'devices_sheet.dart';
import 'focus_ring.dart';
import 'page_area.dart';
import 'player_controls.dart';
import 'player_page.dart';
import 'queue_page.dart';
import 'song_link.dart';
import 'themed_icon.dart';

export 'player_controls.dart' show formatDuration;

/// What plays, wherever it plays, with the controls and the device picker. The song opens the
/// full-screen player, but for its title and artist on a wide screen, which open its album and
/// artist. On a wide screen it stays under the full-screen player too, whose song closes it.
///
/// Each page has one, but for the pages of a [PageArea], under which the home's stays.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({this.lyrics, super.key});

  /// From how wide the bar has room for shuffle, repeat, the lyrics and the queue.
  static const wideFrom = 600.0;

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

        // The same on every page that has it, and under the full-screen player on a wide screen: from one
        // to the next, it stays put rather than coming and going with them.
        return Hero(
          tag: NowPlayingBar,
          child: Material(
            color: colors.surfaceContainer,
            child: SafeArea(
              top: false,
              child: FocusTraversalGroup(
                policy: _BarTraversalPolicy.instance,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: SeekSlider(now)),
                    Padding(
                      // Less on the left and at the bottom than around the buttons, by the song's room inside: its
                      // cover stays 8 from the edge, and the buttons 6 from the bottom.
                      padding: const EdgeInsets.fromLTRB(4, 0, 8, 2),
                      child: IconButtonTheme(
                        data: IconButtonThemeData(style: buttons),
                        child: Row(
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: lyrics == null ? 'Abrir o player' : 'Fechar o player',
                                child: FocusRing(
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    mouseCursor: WidgetStateMouseCursor.clickable,
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: lyrics == null
                                        ? () => PlayerPage.open(context)
                                        : () => PageArea.navigatorOf(context).maybePop(),
                                    // Room around the cover and the lines, where the tint and the ring show, rounded
                                    // as the cover is.
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Row(
                                        children: [
                                          SizedBox.square(
                                            dimension: cover,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: Cover(now.coverArt, size: 96),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // On a phone the song is all there is to tap for the player: its title and
                                          // artist link only on a wider screen, as the full-screen player's do. They
                                          // take no focus: for the keyboard and the remote the song is one stop, the
                                          // player's, where they link too.
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: wide
                                                  ? [
                                                      ExcludeFocus(child: SongLink.title(now, style: line)),
                                                      ExcludeFocus(child: SongLink.artist(now, style: line)),
                                                    ]
                                                  : [
                                                      Text(
                                                        now.title ?? 'Nada tocando',
                                                        style: line,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      Text(
                                                        now.artist ?? '',
                                                        style: line,
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
                            ),
                            if (wide) ShuffleButton(now),
                            IconButton(
                              tooltip: 'Anterior',
                              icon: const ThemedIcon(HugeIcons.strokeRoundedPrevious),
                              onPressed: () => runCommand(context, connect.previous),
                            ),
                            IconButton(
                              tooltip: now.playing ? 'Pausar' : 'Tocar',
                              icon: ThemedIcon(
                                now.playing ? HugeIcons.strokeRoundedPause : HugeIcons.strokeRoundedPlay,
                              ),
                              onPressed: () => runCommand(context, connect.toggle),
                            ),
                            IconButton(
                              tooltip: 'Próxima',
                              icon: const ThemedIcon(HugeIcons.strokeRoundedNext),
                              onPressed: () => runCommand(context, connect.next),
                            ),
                            if (wide) RepeatButton(now),
                            if (wide)
                              switch (lyrics) {
                                null => IconButton(
                                  tooltip: 'Mostrar a letra',
                                  icon: const ThemedIcon(HugeIcons.strokeRoundedMicVocal),
                                  onPressed: () => PlayerPage.open(context, lyrics: true),
                                ),
                                final shown => ValueListenableBuilder(
                                  valueListenable: shown,
                                  builder: (context, on, _) => IconButton(
                                    tooltip: on ? 'Esconder a letra' : 'Mostrar a letra',
                                    icon: ThemedIcon(
                                      HugeIcons.strokeRoundedMicVocal,
                                      color: on ? colors.primary : null,
                                    ),
                                    onPressed: () => shown.value = !on,
                                  ),
                                ),
                              },
                            if (wide)
                              IconButton(
                                tooltip: 'Fila',
                                icon: const ThemedIcon(HugeIcons.strokeRoundedPlaylist03),
                                onPressed: () => QueuePage.open(context),
                              ),
                            IconButton(
                              tooltip: 'Aparelhos',
                              icon: ThemedIcon(
                                HugeIcons.strokeRoundedMonitorSpeaker,
                                color: now.device == null ? null : colors.primary,
                              ),
                              onPressed: () => showDevicesSheet(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Where it plays, when that's another device, in a strip under the player.
                    if (now.device != null)
                      Container(
                        width: double.infinity,
                        color: colors.primaryContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Row(
                          children: [
                            ThemedIcon(HugeIcons.strokeRoundedSpeaker, size: 16, color: colors.onPrimaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              '${now.playing ? 'Tocando' : 'Pausado'} em ${now.device}',
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

/// Moving around the bar with the arrows (a TV remote's): left and right along its row of buttons,
/// up and down between that row and the slider, up from the slider out of the bar, and nowhere past
/// its ends. Flutter's own directional search looks at the whole screen, where the album grid's rows
/// built past the bottom of the screen lie under the bar, level with its buttons, and could win.
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
