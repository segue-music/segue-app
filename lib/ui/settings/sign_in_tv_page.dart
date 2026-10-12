import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';
import '../../pairing/pairing.dart';
import '../../services.dart';
import '../widgets/spinner.dart';

/// Signs a TV in with this device's sign-in: the camera reads the QR code the TV's sign-in shows ([PairingInvite]),
/// and, once the user says so, the TV gets the sign-in ([offerSignIn]). Signed in, it goes, saying so; otherwise it
/// says why, and reads on.
class SignInTvPage extends StatefulWidget {
  const SignInTvPage({super.key});

  /// Whether this device can sign a TV in: a phone's or a tablet's, which has a camera to read the code with; not a
  /// TV, which signs in that way itself.
  static bool available(BuildContext context) =>
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) &&
      MediaQuery.navigationModeOf(context) != NavigationMode.directional;

  @override
  State<SignInTvPage> createState() => _SignInTvPageState();
}

class _SignInTvPageState extends State<SignInTvPage> {
  final _camera = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: [BarcodeFormat.qrCode]);

  /// A code read, being asked about or sent: the others wait.
  bool _taking = false;
  bool _sending = false;

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  Future<void> _read(BarcodeCapture capture) async {
    final invite = capture.barcodes.map((code) => PairingInvite.parse(code.rawValue ?? '')).nonNulls.firstOrNull;

    if (invite == null || _taking) {
      return;
    }

    _taking = true;
    final services = ServicesScope.of(context);
    final session = services.session;
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.signInTvConfirm),
        content: Text(strings.signInTvConfirmDetail(session.credentials.username, session.server.host)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(strings.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(strings.signIn)),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      _taking = false;
      return;
    }

    setState(() => _sending = true);

    try {
      final device = await offerSignIn(invite, session, services.api);
      messenger.showSnackBar(SnackBar(content: Text(strings.signedInTv(device))));
      navigator.pop();
    } on PairingRefused catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(strings.pairingFailed(e.error.name))));
    } on Object {
      // The TV's address answered nothing, or not in time: not on this network, or no longer listening.
      messenger.showSnackBar(SnackBar(content: Text(strings.pairingFailed('notFound'))));
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
