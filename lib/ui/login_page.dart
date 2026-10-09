import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../language_choice.dart';
import '../server/server.dart';
import '../server/sign_in.dart';
import '../session.dart';
import 'language_button.dart';
import 'spinner.dart';

/// Server, user and password: the media server's own account, nothing else to create. Whether the
/// server speaks Subsonic or Jellyfin, the app finds out.
class LoginPage extends StatefulWidget {
  const LoginPage({required this.onSignedIn, this.languageChoice, @visibleForTesting this.client, super.key});

  final void Function(Session session) onSignedIn;

  /// The language picked, which a menu in the top right corner picks; none, no menu.
  final LanguageChoice? languageChoice;

  /// What talks to the media server, for tests.
  final http.Client? client;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _hub = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_server, _username, _password, _hub]) {
      controller.dispose();
    }

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
      api = await signIn(
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
    } on ServerError catch (e) {
      setState(() => _error = e.isAuth ? strings.wrongCredentials : strings.serverRefused('$e'));
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
    final languageChoice = widget.languageChoice;
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

    if (languageChoice == null) {
      return Scaffold(body: form);
    }

    // The language menu in the top right corner, out of the form's way. For the keyboard's Tab it comes after the form,
    // rather than first, as the top of the page; the arrows (a TV remote's) go up to it from the first field.
    return Scaffold(
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Stack(
          children: [
            FocusTraversalOrder(order: const NumericFocusOrder(0), child: form),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FocusTraversalOrder(order: const NumericFocusOrder(1), child: LanguageButton(languageChoice)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
