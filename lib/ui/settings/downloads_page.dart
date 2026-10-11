import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../downloads/downloads.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../album/album_page.dart';
import '../app/page_area.dart';
import '../playlist/playlist_page.dart';
import '../song/song_list_header.dart';
import '../widgets/cover.dart';
import '../widgets/download_button.dart';
import '../widgets/themed_icon.dart';

/// The albums and playlists downloaded to the device, the latest first, under how much room they take: each with how
/// far it has got, opening its page, and going off the device from its button.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = ServicesScope.of(context).downloads!;
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
        automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
        centerTitle: true,
        title: Text(strings.downloads),
      ),
      body: ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final all = downloads.all;

          if (all.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(strings.nothingDownloaded, textAlign: TextAlign.center),
              ),
            );
          }

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: DownloadsSize(downloads, style: Theme.of(context).textTheme.bodyMedium),
              ),
              for (final download in all) _DownloadTile(downloads, download),
            ],
          );
        },
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile(this.downloads, this.download);

  final Downloads downloads;
  final Download download;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final (:done, :failed, :total) = downloads.progressOf(download);
    final album = download.album;
    final playlist = download.playlist;
    return ListTile(
      leading: Thumbnail(download.coverArt, icon: playlist == null ? null : HugeIcons.strokeRoundedPlaylist01),
      title: Text(download.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        done == total
            ? songCountAndLength(strings, download.songs)
            : done + failed == total
            ? strings.downloadFailed(failed)
            : downloads.held
            ? strings.downloadWaiting(done, total)
            : strings.downloading(done, total),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: strings.remove,
        icon: const ThemedIcon(HugeIcons.strokeRoundedDelete02),
        onPressed: () => removeDownload(context, downloads, download),
      ),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => album != null ? AlbumPage(album) : PlaylistPage(playlist!))),
    );
  }
}

/// How much room [downloads] take, in words ("1,2 GB no aparelho"), as they change; the last size it knew while it
/// reckons the next.
class DownloadsSize extends StatefulWidget {
  const DownloadsSize(this.downloads, {this.style, super.key});

  final Downloads downloads;
  final TextStyle? style;

  @override
  State<DownloadsSize> createState() => _DownloadsSizeState();
}

class _DownloadsSizeState extends State<DownloadsSize> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    widget.downloads.addListener(_reckon);
    _reckon();
  }

  @override
  void dispose() {
    widget.downloads.removeListener(_reckon);
    super.dispose();
  }

  Future<void> _reckon() async {
    final bytes = await widget.downloads.size();

    if (mounted) {
      setState(() => _bytes = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Text(
      bytes == null ? '' : AppLocalizations.of(context).downloadsSize(formatSize(context, bytes)),
      style: widget.style,
    );
  }
}
