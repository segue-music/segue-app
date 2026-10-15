import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../server/server.dart';
import '../../services.dart';
import 'directional_navigation.dart';
import 'errors.dart';
import 'themed_icon.dart';
import 'touch_screen.dart';

final _log = Logger('ShareLink');

/// The icon of sharing a public link: in a menu's item, on a button.
const shareIcon = HugeIcons.strokeRoundedShare08;

/// Makes a public link to the song, album, artist or playlist whose id is [id] ([MediaServer.share]) and hands it on,
/// or says why it can't: on a phone or a tablet through the system's share sheet (a chat, an e-mail), which comes out
/// of [context]'s widget on an iPad; on a computer to the clipboard; on a TV, whose share sheet has nowhere to send it,
/// as a QR code for a phone to open ([LinkDialog]). A link the server made with an address of its own network
/// ([isLocalLink]) opens nowhere else, which the app says first, rather than have it sent to someone it won't open
/// for. Whether the link went: shared, copied or shown.
Future<bool> shareLink(BuildContext context, String id) async {
  // Where the sheet comes out of, on an iPad.
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
  final television = context.television;
  final touch = context.touch;
  final api = ServicesScope.of(context).api;
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);
  final Uri link;

  try {
    link = await api.share(id);
  } on SharingOff {
    messenger.showSnackBar(SnackBar(content: Text(strings.sharingOff)));
    return false;
  } on Object catch (error) {
    _log.warning('link not made', error);
    messenger.showSnackBar(SnackBar(content: Text(strings.couldNotShare(describeFailure(strings, error)))));
    return false;
  }

  if (!context.mounted) {
    return false;
  }

  if (television) {
    await showDialog<void>(context: context, builder: (_) => LinkDialog(link));
    return true;
  }

  if (isLocalLink(link) && !await _confirmLocal(context, link, touch: touch)) {
    return false;
  }

  if (!touch) {
    await Clipboard.setData(ClipboardData(text: '$link'));
    messenger.showSnackBar(SnackBar(content: Text(strings.linkCopied)));
    return true;
  }

  try {
    await SharePlus.instance.share(ShareParams(uri: link, sharePositionOrigin: origin));
    return true;
  } on Object catch (e) {
    _log.warning('link not shared', e);
    messenger.showSnackBar(SnackBar(content: Text(strings.couldNotShare(describeFailure(strings, e)))));
    return false;
  }
}

/// Asks whether to hand on [link], which opens only on the server's network, all the same: on a phone or a tablet
/// ([touch]) to the share sheet, on a computer to the clipboard.
Future<bool> _confirmLocal(BuildContext context, Uri link, {required bool touch}) async {
  final strings = AppLocalizations.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.localLink),
      content: Text(strings.localLinkDetail(link.host)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(strings.cancel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(touch ? strings.share : strings.copyLink),
        ),
      ],
    ),
  );

  return go ?? false;
}

/// Whether [link] opens only on the network of the server that made it, as far as its host tells: a private address
/// (IPv4's 10, 172.16 to 31, 192.168, 100.64 to 127 as Tailscale gives them, 127 and 169.254; IPv6's fc00::/7, fe80::/10
/// and ::1) or a name of a local network (one with no dot, or ending in `.local`, `.lan`, `.home.arpa` or
/// `.internal`). A name the internet knows may still lead to a server it can't reach, which the host doesn't tell.
bool isLocalLink(Uri link) {
  final host = link.host.toLowerCase();
  final address = InternetAddress.tryParse(host);

  if (address == null) {
    return !host.contains('.') || _localSuffixes.any(host.endsWith);
  }

  final bytes = address.rawAddress;

  return switch (address.type) {
    InternetAddressType.IPv4 => switch (bytes) {
      [10, ...] || [127, ...] || [192, 168, ...] || [169, 254, ...] => true,
      [172, final second, ...] when second >= 16 && second < 32 => true,
      [100, final second, ...] when second >= 64 && second < 128 => true,
      _ => false,
    },
    _ => address.isLoopback || address.isLinkLocal || (bytes[0] & 0xfe) == 0xfc,
  };
}

const _localSuffixes = ['.local', '.lan', '.home.arpa', '.internal'];

/// On a TV, a public link as a QR code, for a phone to open, and in words beside it; where it opens only on the
/// server's network ([isLocalLink]), that too. The words beside the code, not under it: a TV's screen is too short for
/// both, one over the other, with the dialog's title and button. It scrolls where they are taller than the screen still
/// (bigger text), the button staying in view.
class LinkDialog extends StatelessWidget {
  const LinkDialog(this.link, {super.key});

  final Uri link;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      scrollable: true,
      title: Text(strings.publicLink),
      content: SizedBox(
        width: 600,
        child: Row(
          children: [
            // Dark on white, as cameras read best, whatever the theme; a white border around it, as QR codes need. Its
            // size given around it too: the dialog measures what it holds first, which QrImageView, laid out as it
            // goes (LayoutBuilder), can't say.
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 200,
                child: QrImageView(
                  data: '$link',
                  size: 200,
                  padding: const EdgeInsets.all(12),
                  backgroundColor: Colors.white,
                  semanticsLabel: strings.publicLink,
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.publicLinkHint),
                  const SizedBox(height: 4),
                  Text('$link', style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  if (isLocalLink(link)) ...[const SizedBox(height: 12), Text(strings.localLinkDetail(link.host))],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: Text(strings.close))],
    );
  }
}

/// A button that shares a public link to the item whose id is [id] ([shareLink]), small, beside an artist's heart.
class ShareButton extends StatelessWidget {
  const ShareButton(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppLocalizations.of(context).share,
    icon: const ThemedIcon(shareIcon),
    visualDensity: VisualDensity.compact,
    onPressed: () => shareLink(context, id),
  );
}
