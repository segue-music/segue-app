import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';

import '../connect/connect.dart';
import 'cover.dart';
import 'devices_sheet.dart';
import 'lyrics_view.dart';
import 'player_controls.dart';
import 'queue_page.dart';
import 'song_link.dart';

/// The full-screen player: what plays, wherever it plays, big, with every control, and its lyrics beside
/// it (on a phone, under it).
class PlayerPage extends StatefulWidget {
  const PlayerPage({this.lyrics = false, super.key});

  /// Whether it opens with the lyrics.
  final bool lyrics;

  /// Slides it up over the current page, with the lyrics if [lyrics].
  static Future<void> open(BuildContext context, {bool lyrics = false}) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => PlayerPage(lyrics: lyrics),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
        child: child,
      ),
    ),
  );

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  /// Whether the lyrics show.
  late bool _lyrics = widget.lyrics;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: NowPlayingBuilder(
          builder: (context, connect, now) {
            final colors = Theme.of(context).colorScheme;
            final device = now?.device;
            return Scaffold(
              appBar: AppBar(
                // The background's color, always: neither the lyrics nor, on a phone, the page tint it as
                // they scroll under it.
                notificationPredicate: (_) => false,
                leading: IconButton(
                  tooltip: 'Fechar',
                  icon: const Icon(HugeIcons.strokeRoundedArrowDown01),
                  onPressed: close,
                ),
                centerTitle: true,
                title: device == null
                    ? null
                    : Text(
                        '${now!.playing ? 'Tocando' : 'Pausado'} em $device',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                actions: [
                  IconButton(
                    tooltip: _lyrics ? 'Esconder a letra' : 'Mostrar a letra',
                    icon: Icon(HugeIcons.strokeRoundedMic01, color: _lyrics ? colors.primary : null),
                    onPressed: () => setState(() => _lyrics = !_lyrics),
                  ),
                  IconButton(
                    tooltip: 'Fila',
                    icon: const Icon(HugeIcons.strokeRoundedPlaylist03),
                    onPressed: () => QueuePage.open(context),
                  ),
                  IconButton(
                    tooltip: 'Aparelhos',
                    icon: Icon(HugeIcons.strokeRoundedComputerPhoneSync, color: device == null ? null : colors.primary),
                    onPressed: () => showDevicesSheet(context),
                  ),
                ],
              ),
              body: now == null ? const Center(child: Text('Nada tocando')) : _Player(now, connect, lyrics: _lyrics),
            );
          },
        ),
      ),
    );
  }
}

class _Player extends StatelessWidget {
  const _Player(this.now, this.connect, {required this.lyrics});

  final NowPlaying now;
  final ConnectController connect;

  /// Whether the lyrics show.
  final bool lyrics;

  /// From how wide the lyrics go beside the player rather than under it.
  static const _lyricsBesideFrom = 720.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, box) {
        final beside = lyrics && box.maxWidth >= _lyricsBesideFrom;
        // The cover as big as it fits (beside the lyrics, in half the screen), leaving room for the rest
        // under it.
        final width = (beside ? box.maxWidth / 2 : box.maxWidth) - 48;
        final side = min(width, box.maxHeight - 260).clamp(96.0, 520.0);
        final player = SizedBox(
          width: max(side, 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SizedBox.square(
                  dimension: side,
                  child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Cover(now.coverArt, size: 800)),
                ),
              ),
              const SizedBox(height: 24),
              SongLink.title(now, style: text.headlineSmall, maxLines: 2, replace: true),
              SongLink.artist(now, style: text.titleMedium?.copyWith(color: muted), replace: true),
              if (now.album != null) SongLink.album(now, style: text.bodyMedium?.copyWith(color: muted), replace: true),
              const SizedBox(height: 12),
              SeekSlider(now, timesBelow: true),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ShuffleButton(now),
                  IconButton(
                    tooltip: 'Anterior',
                    iconSize: 36,
                    icon: const Icon(HugeIcons.strokeRoundedPrevious),
                    onPressed: () => runCommand(context, connect.previous),
                  ),
                  IconButton.filled(
                    tooltip: now.playing ? 'Pausar' : 'Tocar',
                    iconSize: 40,
                    padding: const EdgeInsets.all(14),
                    icon: Icon(now.playing ? HugeIcons.strokeRoundedPause : HugeIcons.strokeRoundedPlay),
                    onPressed: () => runCommand(context, connect.toggle),
                  ),
                  IconButton(
                    tooltip: 'Próxima',
                    iconSize: 36,
                    icon: const Icon(HugeIcons.strokeRoundedNext),
                    onPressed: () => runCommand(context, connect.next),
                  ),
                  RepeatButton(now),
                ],
              ),
              if (lyrics && !beside) ...[const SizedBox(height: 24), SizedBox(height: 400, child: LyricsView(now))],
            ],
          ),
        );

        if (!beside) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Center(child: player),
          );
        }

        // Half the screen each: the player in the middle of its half, the lyrics all of theirs.
        return Row(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: player,
                ),
              ),
            ),
            Expanded(child: LyricsView(now)),
          ],
        );
      },
    );
  }
}
