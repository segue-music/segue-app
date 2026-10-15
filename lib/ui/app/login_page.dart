import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../pairing/pairing.dart';
import '../../server/server.dart';
import '../../server/sign_in.dart';
import '../../session.dart';
import '../../settings.dart';
import '../settings/language_button.dart';
import '../widgets/directional_navigation.dart';
import '../widgets/spinner.dart';

/// Server, user and password: the media server's own account, nothing else to create. Whether the
/// server speaks Subsonic or Jellyfin, the app finds out. On a TV, beside them, a QR code that a phone signed in reads,
/// sending the TV its sign-in ([PairingServer]): the remote types nothing.
class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.onSignedIn,
    @visibleForTesting this.client,
    @visibleForTesting this.pairingAddress,
    super.key,
  });

  final void Function(Session session) onSignedIn;

  /// What talks to the media server, for tests.
  final http.Client? client;

  /// Where the TV listens for a phone's sign-in, for tests (the loopback); otherwise its address on the local network.
  final InternetAddress? pairingAddress;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

/// The sides' padding of the button that switches between the password and an API key, Material's for a text button.
const _linkPadding = 12.0;

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _apiKey = TextEditingController();
  final _hub = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Whether the user signs in with an API key they made on the server (OpenSubsonic's apiKeyAuthentication), rather
  /// than their name and password.
  bool _withApiKey = false;

  /// On a TV, where it listens for a phone's sign-in, and whether it is signing in with one, or why it couldn't.
  PairingServer? _pairing;
  bool _pairingStarted = false;
  bool _signingInWithPhone = false;
  PairingError? _phoneError;

  /// How many phones' sign-ins have come: a Quick Connect ending after another sign-in came is that one's no longer.
  int _offers = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_pairingStarted && context.television) {
      _pairingStarted = true;
      unawaited(_startPairing());
    }
  }

  Future<void> _startPairing() async {
    final pairing = await PairingServer.start(
      _takeOffer,
      name: await Session.thisDeviceName(),
      address: widget.pairingAddress,
    );

    if (!mounted) {
      await pairing?.close();
      return;
    }

    setState(() => _pairing = pairing);
  }

  /// A phone's sign-in: the TV signs in with it, and goes on as with the form's.
  Future<PairingAnswer> _takeOffer(PairingOffer offer) async {
    final taken = ++_offers;

    setState(() {
      _signingInWithPhone = true;
      _phoneError = null;
    });

    final answer = await takeOffer(
      offer,
      deviceId: await Session.thisDeviceId(),
      deviceName: await Session.thisDeviceName(),
      client: widget.client,
      signedIn: (session) async {
        // Signed in with the form meanwhile, while a Quick Connect waited.
        if (!mounted) {
          return;
        }

        await session.save();

        if (mounted) {
          widget.onSignedIn(session);
        }
      },
      failed: (error) {
        if (taken == _offers) {
          _phoneSignInFailed(error);
        }
      },
    );

    if (answer case PairingRefused(:final error)) {
      _phoneSignInFailed(error);
    }

    return answer;
  }

  /// The phone's sign-in came to nothing: the code shows again, and why.
  void _phoneSignInFailed(PairingError error) {
    if (mounted) {
      setState(() {
        _signingInWithPhone = false;
        _phoneError = error;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [_server, _username, _password, _apiKey, _hub]) {
      controller.dispose();
    }

    // Not at once: the answer to the phone that signed it in may still be on its way.
    unawaited(_pairing?.close());
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final strings = AppLocalizations.of(context);
    final server = normalizeServer(_server.text);

    MediaServer? api;

    try {
      final deviceId = await Session.thisDeviceId();
      final deviceName = await Session.thisDeviceName();
      api = _withApiKey
          ? await signInWithApiKey(server, _apiKey.text.trim(), client: widget.client)
          : await signIn(
              server,
              _username.text.trim(),
              _password.text,
              deviceId: deviceId,
              deviceName: deviceName,
              client: widget.client,
            );
      final hub = _hub.text.trim();
      final session = Session(
        server: server,
        credentials: api.credentials,
        deviceId: deviceId,
        deviceName: deviceName,
        hub: hub.isEmpty ? null : normalizeServer(hub),
      );

      try {
        await session.save();
      } on Exception catch (e) {
        setState(() => _error = strings.couldNotSaveSignIn('$e'));
        return;
      }

      widget.onSignedIn(session);
    } on NotAMediaServer {
      setState(() => _error = strings.notAMediaServer(server.host));
    } on NoApiKeys {
      setState(() => _error = strings.serverTakesNoApiKeys);
    } on ServerError catch (e) {
      setState(() {
        // A server that takes a key alone (LMS) refuses the password so: the key's field, rather than the password's.
        if (!_withApiKey && e.wantsApiKey) {
          _withApiKey = true;
          _error = strings.serverWantsApiKey;
        } else if (e.isAuth) {
          _error = _withApiKey ? strings.wrongApiKey : strings.wrongCredentials;
        } else {
          _error = strings.serverRefused('$e');
        }
      });
    } on Exception catch (e) {
      setState(() => _error = strings.couldNotReachServer(server.host, '$e'));
    } finally {
      api?.close();

      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String? _required(String? value) => (value ?? '').trim().isEmpty ? AppLocalizations.of(context).required : null;

  /// A touch off the fields closes the keyboard: Flutter leaves a field focused on a touch, on a phone or a tablet,
  /// unfocusing it only for a mouse. One on another field moves to it, the keyboard staying open.
  void _closeKeyboard(PointerDownEvent event) => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final language = SettingsScope.maybeOf(context)?.language;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Image.asset('assets/logo_large.png', width: 96, height: 96, semanticLabel: 'Segue')),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _server,
                  decoration: InputDecoration(labelText: strings.server, hintText: strings.serverHint),
                  keyboardType: TextInputType.url,
                  // The keyboard's button goes on to the next field (a TV's keyboard has no other way).
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  onTapOutside: _closeKeyboard,
                ),
                if (_withApiKey)
                  TextFormField(
                    controller: _apiKey,
                    decoration: InputDecoration(labelText: strings.apiKey, helperText: strings.apiKeyHelp),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: _required,
                    onTapOutside: _closeKeyboard,
                    onFieldSubmitted: (_) => _submit(),
                  )
                else ...[
                  TextFormField(
                    controller: _username,
                    decoration: InputDecoration(labelText: strings.username),
                    textInputAction: TextInputAction.next,
                    validator: _required,
                    onTapOutside: _closeKeyboard,
                  ),
                  TextFormField(
                    controller: _password,
                    decoration: InputDecoration(labelText: strings.password),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: _required,
                    onTapOutside: _closeKeyboard,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
                // Its words in line with the fields' and "Advanced"'s, its padding out past their edge, where its
                // highlight and focus ring keep room around them.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Transform.translate(
                    offset: Offset(Directionality.of(context) == TextDirection.rtl ? _linkPadding : -_linkPadding, 0),
                    child: TextButton(
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: _linkPadding)),
                      onPressed: () => setState(() {
                        _withApiKey = !_withApiKey;
                        _error = null;
                      }),
                      child: Text(_withApiKey ? strings.signInWithPassword : strings.signInWithApiKey),
                    ),
                  ),
                ),
                ExpansionTile(
                  title: Text(strings.advanced),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    TextFormField(
                      controller: _hub,
                      decoration: InputDecoration(labelText: strings.hubAddress, helperText: strings.hubAddressHelp),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onTapOutside: _closeKeyboard,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const Spinner(size: 20, strokeWidth: 2.5) : Text(strings.signIn),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final pairing = _pairing;
    // On a TV, the phone's way in before the form, which the remote would type in: half the screen each, out of its
    // edges, the code in the middle of its half and the form in the middle of the other.
    final body = pairing == null
        ? form
        : SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    // As the form does, it scrolls where its words, in a language or a size, need more room.
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ValueListenableBuilder(
                        valueListenable: pairing.invite,
                        builder: (context, invite, _) =>
                            PhoneSignIn(invite, signingIn: _signingInWithPhone, error: _phoneError),
                      ),
                    ),
                  ),
                ),
                Expanded(child: form),
              ],
            ),
          );

    // With no settings (SettingsScope), no language to pick.
    if (language == null) {
      return Scaffold(body: body);
    }

    // The language menu in the top right corner, out of the form's way. For the keyboard's Tab it comes after the form,
    // rather than first, as the top of the page; the arrows (a TV remote's) go up to it from the first field.
    return Scaffold(
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Stack(
          children: [
            FocusTraversalOrder(order: const NumericFocusOrder(0), child: body),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FocusTraversalOrder(order: const NumericFocusOrder(1), child: LanguageButton(language)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// On a TV's sign-in, the QR code that a phone signed in reads to sign the TV in ([invite]), with the TV's name and
/// address, which the phone shows before signing it in, and what to do with it; as the phone's sign-in comes, that the
/// TV is signing in with it, or why it couldn't.
class PhoneSignIn extends StatelessWidget {
  const PhoneSignIn(this.invite, {required this.signingIn, required this.error, super.key});

  final PairingInvite invite;
  final bool signingIn;
  final PairingError? error;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final error = this.error;

    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(strings.signInWithPhone, style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          // Dark on white, as cameras read best, whatever the theme; a white border around it, as QR codes need.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: QrImageView(
              data: '$invite',
              size: 200,
              padding: const EdgeInsets.all(12),
              backgroundColor: Colors.white,
              semanticsLabel: strings.signInWithPhone,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.pairingDevice(invite.name, invite.host),
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (signingIn)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Spinner(size: 16, strokeWidth: 2),
                const SizedBox(width: 8),
                Flexible(child: Text(strings.signingInWithPhone, style: text.bodyMedium)),
              ],
            )
          else if (error != null)
            Text(
              strings.pairingFailed(error.name),
              style: text.bodyMedium?.copyWith(color: colors.error),
              textAlign: TextAlign.center,
            )
          else
            Text(strings.signInWithPhoneDetail, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
