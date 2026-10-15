import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connect/connect.dart';
import '../../l10n/app_localizations.dart';
import '../../segue/protocol.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../../settings.dart';
import '../app/page_area.dart';
import '../app/phone_bars.dart';
import '../song/movable_song.dart';
import '../song/song_list_header.dart';
import '../song/song_menu.dart';
import '../widgets/cover.dart';
import '../widgets/directional_navigation.dart';
import '../widgets/touch_screen.dart';
import 'autoplay_switch.dart';
import 'now_playing_bar.dart';
import 'player_controls.dart';

/// The queue of the device the app controls, in its play order (shuffled, or not): the current
/// track on top, the next ones under it, and what played before above it. A tap on a track plays it
/// there. Where the device takes it, the tracks from the one on top down move by dragging them (on a TV, which has no
/// drag, by the remote, from their menu: [MovableSongs]), and any but the current one goes out of the queue by its menu. After the last, this device's queue has the switch of autoplay, which
/// goes on with songs like it.
class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  /// The queue's page, by which [toggle] tells it on top, also once it opens again going forward ([PageHistory] opens
  /// a page again with its settings).
  static const _settings = RouteSettings(name: 'queue');

  /// Opens it over the current page: on a wide screen, in the page area; on a phone, over everything, the area around it
  /// all the same ([PageArea.around]), with the home's sections. In the area, it has the area as it is, which changes as
  /// the window is narrowed or widened.
  static Future<void> open(BuildContext context) {
    final area = PageArea.maybeOf(context);

    return PageArea.playerNavigatorOf(context).push(
      MaterialPageRoute<void>(
        settings: _settings,
        builder: (_) => area == null || area.holdsPlayer ? const QueuePage() : area.around(const QueuePage()),
      ),
    );
  }

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _top ??= ServicesScope.of(context).connect.queue.index;
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final connect = services.connect;
    final autoplay = SettingsScope.maybeOf(context)?.autoplay;
    final strings = AppLocalizations.of(context);
    // On a TV the remote starts on the current track. Elsewhere the page itself takes the focus, so
    // that Esc closes it, and no track looks focused.
    final television = context.television;

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

            Widget tile(int i, [RemoteMove? byRemote]) {
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

              return SongMenu(
                Song.fromQueueItem(track),
                list: SongList.queue,
                onMove: byRemote?.start,
                onRemove: editable && !current ? () => _remove(connect, tracks, index, i) : null,
                builder: (context, menu) => byRemote?.movable(line(menu)) ?? line(menu),
              );
            }

            return Scaffold(
              appBar: AppBar(
                // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
                automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
                centerTitle: true,
                title: Text(switch (now?.device) {
                  null => strings.queue,
                  final device => strings.queueOn(device),
                }),
              ),
              // In a phone's layout, over everything, the home's bars, the sections' too, as the home has them: a section
              // picked closes the queue, and the player under it. In the page area (a window narrowed with it open), the
              // home's own stay under it.
              bottomNavigationBar: switch (PageArea.maybeOf(context)?.sections) {
                final sections? when context.phoneLayout && !PageArea.holds(context) => PhoneBars(sections: sections),
                _ => const NowPlayingBar(),
              },
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
                              // From the one on top down, the tracks move where the device takes it.
                              MovableSongs(
                                key: _fromTop,
                                keys: _keys(tracks).sublist(top),
                                onMove: editable
                                    ? (from, to) => _move(connect, tracks, index, top + from, top + to)
                                    : null,
                                itemBuilder: (_, i, byRemote) => tile(top + i, byRemote),
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
    final top = _top!;

    // The track on top stays on top, the queue as it was too, where the device fails to take it out.
    if (i < top) {
      _top = top - 1;
    }

    _edit(
      _QueueChange(_ids(tracks), [...tracks]..removeAt(i), i < index ? index - 1 : index),
      () => connect.removeFromQueue(i),
      undo: () => _top = top,
    );
  }

  /// Shows [change] until the queue has it, and has the device the app controls make it with [command]; the queue as it
  /// was again, and why, where that fails, and what [undo] does undone.
  Future<void> _edit(_QueueChange change, Future<Result> Function() command, {VoidCallback? undo}) async {
    setState(() => _change = change);

    final result = await runCommand(context, command);

    if (!result.ok && mounted && identical(_change, change)) {
      setState(() {
        _change = null;
        undo?.call();
      });
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
