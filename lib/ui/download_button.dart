import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../downloads/downloads.dart';
import '../l10n/app_localizations.dart';
import '../server/models.dart';
import '../services.dart';
import 'spinner.dart';
import 'themed_icon.dart';

/// The button that downloads an album or a playlist, to play without the media server, and shows how far that has got:
/// as it comes, how many of its songs are on the device; once they all are, that it is downloaded. Pressed then, or as
/// it comes, it asks to take it off the device; where songs failed to come, it tries them again. Nothing where the app
/// downloads nothing ([Services.downloads]).
class DownloadButton extends StatelessWidget {
  const DownloadButton.album(Album this.album, this.songs, {super.key}) : playlist = null;

  const DownloadButton.playlist(Playlist this.playlist, this.songs, {super.key}) : album = null;

  final Album? album;
  final Playlist? playlist;

  /// Its songs, as the server has them now.
  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final downloads = ServicesScope.of(context).downloads;

    if (downloads == null) {
      return const SizedBox.shrink();
    }

    final strings = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final album = this.album;
        final download = album != null ? downloads.ofAlbum(album.id) : downloads.ofPlaylist(playlist!.id);

        if (download == null) {
          return IconButton(
            tooltip: strings.download,
            icon: const ThemedIcon(HugeIcons.strokeRoundedDownload04),
            onPressed: songs.isEmpty
                ? null
                : () => album != null ? downloads.addAlbum(album, songs) : downloads.addPlaylist(playlist!, songs),
          );
        }

        final (:done, :failed, :total) = downloads.progressOf(download);

        if (done == total) {
          return IconButton(
            tooltip: strings.downloaded,
            icon: const ThemedIcon(HugeIcons.strokeRoundedCheckmarkCircle02),
            onPressed: () => removeDownload(context, downloads, download),
          );
        }

        // Every song tried, and some failed.
        if (done + failed == total) {
          return IconButton(
            tooltip: strings.downloadFailed(failed),
            icon: const ThemedIcon(HugeIcons.strokeRoundedAlert02),
            onPressed: downloads.retry,
          );
        }

        return IconButton(
          tooltip: downloads.held ? strings.downloadWaiting(done, total) : strings.downloading(done, total),
          icon: ProgressRing(
            total == 0 ? 0 : done / total,
            size: (IconTheme.of(context).size ?? 24) - 2,
            strokeWidth: 2.5,
          ),
          onPressed: () => removeDownload(context, downloads, download),
        );
      },
    );
  }
}

/// Asks to take [download] off the device, and does it once the user says so.
Future<void> removeDownload(BuildContext context, Downloads downloads, Download download) async {
  final strings = AppLocalizations.of(context);
  final remove = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.removeDownloadQuestion(download.name)),
      content: Text(strings.removeDownloadDetail),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(strings.cancel)),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(strings.remove)),
      ],
    ),
  );

  if (remove ?? false) {
    await downloads.remove(download);
  }
}

/// [bytes] as the room they take, in the app's language: in megabytes ("850 MB"), or past a thousand, in gigabytes
/// with a decimal ("1,2 GB"), as the systems count them, by thousands.
String formatSize(BuildContext context, int bytes) {
  final locale = Localizations.localeOf(context).toLanguageTag();

  if (bytes < 1000 * 1000 * 1000) {
    return '${NumberFormat.decimalPattern(locale).format((bytes / (1000 * 1000)).round())} MB';
  }

  return '${NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 1).format(bytes / (1000 * 1000 * 1000))} GB';
}
