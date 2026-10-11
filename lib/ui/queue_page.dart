import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connect/connect.dart';
import '../l10n/app_localizations.dart';
import '../segue/protocol.dart';
import '../server/models.dart';
import '../services.dart';
import 'autoplay_switch.dart';
import 'cover.dart';
import 'movable_song.dart';
import 'now_playing_bar.dart';
import 'page_area.dart';
import 'player_controls.dart';
import 'song_list_header.dart';
import 'song_menu.dart';

/// The queue of the device the app controls, in its play order (shuffled, or not): the current
/// track on top, the next ones under it, and what played before above it. A tap on a track plays it
/// there. Where the device takes it, the tracks from the one on top down move by dragging them (on a TV, which has no
/// drag, by the remote, from their menu: [MovableSong]), and any but the current one goes out of the queue by its menu. After the last, this device's queue has the switch of autoplay, which
/// goes on with songs like it.
class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  /// The queue's page, by which [toggle] tells it on top, also once it opens again going forward ([PageHistory] opens
  /// a page again with its settings).
  static const _settings = RouteSettings(name: 'queue');

  /// Opens it over the current page: on a wide screen, in the page area; on a phone, over everything.
  static Future<void> open(BuildContext context) =>
      PageArea.playerNavigatorOf(context)
          .push(MaterialPageRoute<void>(settings: _settings, builder: (_) => const QueuePage()));

  /// Opens it, or, with it open on top of the page area (a wide screen's, where the player bar stays under it), goes
  /// back from it instead, as the top bar's arrow does, rather than opening it again over itself.
  static void toggle(BuildContext context) {
    final history = PageArea.maybeOf(context)?.history;

    if (history != null && history.current?.settings.name == _settings.name) {
      history.back();
      return;
    }

    open(context);
  }

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  /// The track on top: the current one when the page opened. It stays there as the music moves on,
  /// so that the list doesn't move under the finger.
  int? _top;
  final _fromTop = UniqueKey();

  /// A change made here until the queue shows it ([_QueueChange]).
  _QueueChange? _change;

  /// On a TV, the track the remote moves ([MovableSong]), by its key, as the queue may come anew meanwhile, and how many
  /// places it has gone so far, up (below zero) or down.
  ({Key key, int by})? _moving;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _top ??= ServicesScope.of(context).connect.queue.index;
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final (connect, autoplay) = (services.connect, services.autoplay);
    final strings = AppLocalizations.of(context);
    // On a TV the remote starts on the current track. Elsewhere the page itself takes the focus, so
    // that Esc closes it, and no track looks focused.
    final television = MediaQuery.navigationModeOf(context) == NavigationMode.directional;

    void close() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: !television,
        child: ListenableBuilder(
          listenable: connect,
          builder: (context, _) {
            final now = connect.nowPlaying;
            var (:tracks, :index) = connect.queue;
            final change = _change;

            // Until the queue is no longer as it was before the change: then it has it, or another change came.
            if (change != null && listEquals(_ids(tracks), change.before)) {
              (tracks, index) = (change.after, change.index);
            } else {
              _change = null;
            }

            final top = _top!.clamp(0, tracks.length);
            final editable = connect.canEditQueue;
            var keys = _keys(tracks);
            // On a TV, which has no drag, a track from the one on top down moves by the remote: the queue shows it where
            // it has gone so far, and once it's left there, the device moves it.
            final (base, baseIndex) = (tracks, index);
            final moving = television && editable ? _moving : null;
            final from = moving == null ? -1 : keys.indexOf(moving.key);
            int? movingTo;

            if (moving != null && from >= top) {
              final to = (from + moving.by).clamp(top, tracks.length - 1);
              movingTo = to;
              tracks = withMove(tracks, from: from, to: to);
              keys = withMove(keys, from: from, to: to);
              index = indexAfterMove(index, from: from, to: to);
            } else {
              // Gone from the queue meanwhile, or above the one on top now.
              _moving = null;
            }

            final theme = Theme.of(context);
            final touch = switch (theme.platform) {
              TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
              TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
            };

            Widget tile(int i) {
              final track = tracks[i];
              final current = i == index;
              final about = [track.artist, track.album].nonNulls.join(' · ');
              final duration = track.durationMs == null ? null : Duration(milliseconds: track.durationMs!);

              Widget line(Widget? menu) => ListTile(
                autofocus: current && television,
                contentPadding: menu == null ? null : SongTrailing.tilePadding,
                selected: current,
                leading: Thumbnail(track.id, playing: current && (now?.playing ?? false)),
                title: Text(track.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: about.isEmpty ? null : Text(about, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: menu == null ? SongDuration(duration) : SongTrailing(track.id!, duration, menu),
                onTap: now?.canJump ?? false ? () => runCommand(context, () => connect.jump(i)) : null,
              );

              // A track the hub couldn't give in the app's API has no song to do anything else with.
              if (track.id == null) {
                return line(null);
              }

              // On a TV, from the one on top down, where the remote moves it.
              final byRemote = television && editable && i >= top;
              return SongMenu(
                Song.fromQueueItem(track),
                list: SongList.queue,
                onMove: byRemote ? () => setState(() => _moving = (key: keys[i], by: 0)) : null,
                onRemove: editable && !current ? () => _remove(connect, tracks, index, i) : null,
                builder: (context, menu) => byRemote
                    ? MovableSong(
                        moving: i == movingTo,
                        onStep: (step) => setState(
                          () => _moving = (key: keys[i], by: (i + step).clamp(top, tracks.length - 1) - from),
                        ),
                        onDrop: () {
                          setState(() => _moving = null);
                          _move(connect, base, baseIndex, from, i);
                        },
                        onCancel: () => setState(() => _moving = null),
                        child: line(menu),
                      )
                    : line(menu),
              );
            }

            // From the one on top down, the tracks move where the device takes it: on a touch screen once held a
            // moment, since a drag scrolls the list, and with a mouse at once.
            Widget movable(BuildContext context, int i) {
              final key = keys[top + i];
              return touch
                  ? ReorderableDelayedDragStartListener(key: key, index: i, child: tile(top + i))
                  : ReorderableDragStartListener(key: key, index: i, child: tile(top + i));
            }

            // While a track moves, back (the top bar's arrow, say) puts it back rather than leaving.
            return PopScope(
              canPop: movingTo == null,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) {
                  setState(() => _moving = null);
                }
              },
              child: Scaffold(
                appBar: AppBar(
                  // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
                  automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
                  centerTitle: true,
                  title: Text(switch (now?.device) {
                    null => strings.queue,
                    final device => strings.queueOn(device),
                  }),
                ),
                bottomNavigationBar: const NowPlayingBar(),
                body: tracks.isEmpty
                    ? Center(child: Text(strings.queueEmpty))
                    // The header stays over the tracks, which go up from the one on top as much as down from it.
                    : Column(
                        children: [
                          const SongListHeader(menus: true),
                          Expanded(
                            // The list starts at the track on top; the ones before it go up from there.
                            child: CustomScrollView(
                              center: _fromTop,
                              slivers: [
                                SliverList.builder(itemCount: top, itemBuilder: (_, i) => tile(top - 1 - i)),
                                if (editable && !television)
                                  SliverReorderableList(
                                    key: _fromTop,
                                    itemCount: tracks.length - top,
                                    itemBuilder: movable,
                                    onReorderItem: (from, to) => _move(connect, tracks, index, top + from, top + to),
                                    // The track moving, lifted over the others, on the page's color: in the overlay,
                                    // over the page.
                                    proxyDecorator: (child, _, _) => Material(
                                      elevation: 4,
                                      color: theme.colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(8),
                                      child: child,
                                    ),
                                  )
                                else
                                  SliverList.builder(
                                    key: _fromTop,
                                    itemCount: tracks.length - top,
                                    // By their keys, so that a track the remote moves keeps its line, and the focus.
                                    itemBuilder: (_, i) => KeyedSubtree(key: keys[top + i], child: tile(top + i)),
                                    findChildIndexCallback: (key) {
                                      final i = keys.indexOf(key);
                                      return i < top ? null : i - top;
                                    },
                                  ),
                                // Another device's goes on, or not, as that device has it.
                                if (autoplay != null && connect.activeId == null)
                                  SliverToBoxAdapter(
                                    child: Column(children: [const Divider(height: 17), AutoplaySwitch(autoplay)]),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Moves the track at [from] in [tracks], of which the one at [index] is current, to [to], the place it then has.
  void _move(ConnectController connect, List<QueueItem> tracks, int index, int from, int to) {
    if (from == to) {
      return;
    }

    final after = [...tracks]
      ..removeAt(from)
      ..insert(to, tracks[from]);
    _edit(_QueueChange(_ids(tracks), after, after.indexOf(tracks[index])), () => connect.moveInQueue(from, to));
  }

  /// Takes the track at [i] out of [tracks], of which the one at [index] is current.
  void _remove(ConnectController connect, List<QueueItem> tracks, int index, int i) {
    // The track on top stays on top.
    if (i < _top!) {
      _top = _top! - 1;
    }

    _edit(
      _QueueChange(_ids(tracks), [...tracks]..removeAt(i), i < index ? index - 1 : index),
      () => connect.removeFromQueue(i),
    );
  }

  /// Shows [change] until the queue has it, and has the device the app controls make it with [command]; the queue as it
  /// was again, and why, where that fails.
  Future<void> _edit(_QueueChange change, Future<Result> Function() command) async {
    setState(() => _change = change);
    final result = await runCommand(context, command);

    if (!result.ok && mounted && identical(_change, change)) {
      setState(() => _change = null);
    }
  }

  static List<String?> _ids(List<QueueItem> tracks) => [for (final track in tracks) track.id];

  /// A key for each of [tracks], by its id and how many times that id comes before it, which stays with it as the queue
  /// is reported again, its items made anew, and as it moves past others.
  static List<Key> _keys(List<QueueItem> tracks) {
    final seen = <String?, int>{};
    return [for (final track in tracks) ValueKey((track.id, seen[track.id] = (seen[track.id] ?? -1) + 1))];
  }
}

/// A change made to the queue on its page, a move or a removal, until the queue shows it: the device the app controls
/// takes a moment to make it, another device a trip through the hub, and a track dropped somewhere has to show there at
/// once. The tracks as they were, by their ids, and as they are to be, with the current one's place then.
class _QueueChange {
  _QueueChange(this.before, this.after, this.index);

  final List<String?> before;
  final List<QueueItem> after;
  final int index;
}
