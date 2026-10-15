import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';
import '../../pairing/pairing.dart';
import '../../server/reachability.dart';
import '../../server/server.dart';
import '../../services.dart';
import '../../session.dart';
import '../widgets/directional_navigation.dart';
import '../widgets/errors.dart';
import '../widgets/spinner.dart';

final _log = Logger('SignInTvPage');

/// Signs a TV in with this device's sign-in: the camera reads the QR code the TV's sign-in shows ([PairingInvite]),
/// and, once the user says so, the TV gets the sign-in ([offerSignIn]). Signed in, it goes, saying so; otherwise it
/// says why, and reads on.
class SignInTvPage extends StatefulWidget {
  const SignInTvPage({super.key});

  /// Whether this device can sign a TV in: a phone's or a tablet's, which has a camera to read the code with; not a
  /// TV, which signs in that way itself.
  static bool available(BuildContext context) =>
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) &&
      !context.television;

  @override
  State<SignInTvPage> createState() => _SignInTvPageState();
}

class _SignInTvPageState extends State<SignInTvPage> {
  final _camera = MobileScannerController(formats: [BarcodeFormat.qrCode]);

  /// A code read, being asked about or sent: the others wait.
  bool _taking = false;
  bool _sending = false;

  /// The codes asked about, by their ids, each once: the camera goes on reading the one before the user. A TV shows
  /// another after each sign-in, which comes while this one is sent, and the camera's own check (`noDuplicates`) would
  /// then take it for one read, and never give it again.
  final _asked = <String>{};

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  Future<void> _read(BarcodeCapture capture) async {
    final invite = capture.barcodes.map((code) => PairingInvite.parse(code.rawValue ?? '')).nonNulls.firstOrNull;

    if (invite == null || _taking || !_asked.add(invite.id)) {
      return;
    }

    _taking = true;
    final services = ServicesScope.of(context);
    final session = services.session;
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final page = ModalRoute.of(context);
    final confirmed = await showDialog<bool>(context: context, builder: (context) => ConfirmSignInTv(invite, session));

    if (confirmed != true || !mounted) {
      _taking = false;
      return;
    }

    setState(() => _sending = true);

    try {
      final device = await offerSignIn(invite, session, services.api);

      messenger.showSnackBar(SnackBar(content: Text(strings.signedInTv(device))));

      // Unless the user went back meanwhile: the page under it stays.
      if (page?.isCurrent ?? false) {
        navigator.pop();
      }
    } on PairingRefused catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(strings.pairingFailed(e.error.name))));
    } on QuickConnectNotAuthorized catch (e) {
      // This device's media server, authorizing the TV's Quick Connect code: refusing, or out of reach.
      _log.warning('Quick Connect code not authorized', e.error);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e.error) {
            final ServerError error => strings.serverRefused(describeFailure(strings, error)),
            final error => strings.couldNotReachServer(session.server.host, '$error'),
          }),
        ),
      );
    } on Object catch (e) {
      _log.warning('sign-in not sent to the TV', e);

      // For the network, the TV's address answered nothing, or not in time: not on this network, or no longer
      // listening.
      messenger.showSnackBar(
        SnackBar(content: Text(strings.pairingFailed(isNetworkFailure(e) ? 'notFound' : 'other'))),
      );
    } finally {
      _taking = false;

      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.signInTv)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _read,
            errorBuilder: (context, _) => Center(
              child: Padding(padding: const EdgeInsets.all(24), child: Text(strings.noCameraAccess)),
            ),
          ),
          // Under the camera's picture, what to point it at; while the sign-in goes to the TV, that it does.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: _sending
                    ? const Spinner(size: 24, color: Colors.white)
                    : Text(
                        strings.signInTvAim,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks, once a TV's code is read, before sending it this [session]'s sign-in: which TV, by its name and its address on
/// the network, which its sign-in shows under the code, as whom and on which server. True, signing it in.
class ConfirmSignInTv extends StatelessWidget {
  const ConfirmSignInTv(this.invite, this.session, {super.key});

  final PairingInvite invite;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(strings.signInTvConfirm),
      content: Text(
        strings.signInTvConfirmDetail(invite.name, invite.host, session.credentials.username, session.server.host),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(strings.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(strings.signIn)),
      ],
    );
  }
}
