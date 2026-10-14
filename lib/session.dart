import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'device.dart';
import 'jellyfin/api.dart';
import 'segue/protocol.dart';
import 'server/server.dart';
import 'subsonic/api.dart';

final _log = Logger('Session');

/// Who is signed in, where, and as which device. The token (and Subsonic's salt), or an API key, is as good as the
/// password on that server, so it goes to the system's secure storage; the rest to plain preferences.
class Session {
  const Session({
    required this.server,
    required this.credentials,
    required this.deviceId,
    required this.deviceName,
    this.hub,
  });

  final Uri server;

  /// `SubsonicCredentials` or `JellyfinCredentials`, by the API the server speaks.
  final Credentials credentials;

  /// Stable for this installation: the hub knows the device by it.
  final String deviceId;
  final String deviceName;

  /// The hub's address, when the user typed one; otherwise it is looked for next to [server].
  final Uri? hub;

  static const _secure = FlutterSecureStorage();
  static final _prefs = SharedPreferencesAsync();

  /// The saved session, or null: none saved, or the secure storage can't be read (no keyring
  /// running), which just means signing in again.
  static Future<Session?> load() async {
    final server = await _prefs.getString('server');
    final username = await _prefs.getString('username');

    if (server == null || username == null) {
      return null;
    }

    final String? token, salt, apiKey;

    try {
      token = await _secure.read(key: 'token');
      salt = await _secure.read(key: 'salt');
      apiKey = await _secure.read(key: 'apiKey');
    } on Exception catch (e) {
      _log.warning('secure storage unavailable', e);
      return null;
    }

    final api = await _prefs.getString('api');
    final userId = await _prefs.getString('userId');
    final Credentials credentials;

    if (api == Api.jellyfin.name && userId != null && token != null) {
      credentials = JellyfinCredentials(username: username, userId: userId, token: token);
    } else if (api == Api.subsonic.name && apiKey != null) {
      credentials = SubsonicApiKey(username: username, apiKey: apiKey);
    } else if (api == Api.subsonic.name && token != null && salt != null) {
      credentials = SubsonicToken(username: username, token: token, salt: salt);
    } else {
      return null;
    }

    final hub = await _prefs.getString('hub');

    return Session(
      server: Uri.parse(server),
      credentials: credentials,
      deviceId: await thisDeviceId(),
      deviceName: await thisDeviceName(),
      hub: hub == null ? null : Uri.parse(hub),
    );
  }

  Future<void> save() async {
    await _prefs.setString('server', server.toString());
    await _prefs.setString('username', credentials.username);

    if (hub == null) {
      await _prefs.remove('hub');
    } else {
      await _prefs.setString('hub', hub.toString());
    }

    switch (credentials) {
      case SubsonicToken(:final token, :final salt):
        await _prefs.setString('api', Api.subsonic.name);
        await _prefs.remove('userId');
        await _secure.write(key: 'token', value: token);
        await _secure.write(key: 'salt', value: salt);
        await _secure.delete(key: 'apiKey');
      case SubsonicApiKey(:final apiKey):
        await _prefs.setString('api', Api.subsonic.name);
        await _prefs.remove('userId');
        await _secure.write(key: 'apiKey', value: apiKey);
        await _secure.delete(key: 'token');
        await _secure.delete(key: 'salt');
      case JellyfinCredentials(:final userId, :final token):
        await _prefs.setString('api', Api.jellyfin.name);
        await _prefs.setString('userId', userId);
        await _secure.write(key: 'token', value: token);
        await _secure.delete(key: 'salt');
        await _secure.delete(key: 'apiKey');
    }
  }

  /// The hub last found next to [server] (its WebSocket's address), for when it can't be found again as the app opens
  /// (the server out of reach, the network blinking); null where none was.
  static Future<Uri?> foundHub(Uri server) async {
    final hub = await _prefs.getString('foundHub');

    return hub != null && await _prefs.getString('foundHubServer') == server.toString() ? Uri.parse(hub) : null;
  }

  /// Keeps [hub] as the hub found next to [server] ([foundHub]).
  static Future<void> rememberFoundHub(Uri server, Uri hub) async {
    await _prefs.setString('foundHubServer', server.toString());
    await _prefs.setString('foundHub', hub.toString());
  }

  /// Signs out. The device id stays: it is this installation's, not the session's.
  static Future<void> clear() async {
    await _secure.delete(key: 'token');
    await _secure.delete(key: 'salt');
    await _secure.delete(key: 'apiKey');
    await _prefs.remove('username');
    await _prefs.remove('userId');
  }

  // SEGUE_DEVICE_ID and SEGUE_DEVICE_NAME let a second copy of the app on the same computer, with
  // the same login, be another device: for trying Connect out. They are never saved.

  /// The id the hub knows this device by: one per installation, generated the first time.
  static Future<String> thisDeviceId() async {
    final fromEnv = Platform.environment['SEGUE_DEVICE_ID'];

    if (fromEnv != null) {
      return fromEnv;
    }

    final existing = await _prefs.getString('deviceId');

    if (existing != null) {
      return existing;
    }

    final id = const Uuid().v4();

    await _prefs.setString('deviceId', id);

    return id;
  }

  /// The name other devices see: the one the system gives this device (not the system's own).
  static Future<String> thisDeviceName() async => Platform.environment['SEGUE_DEVICE_NAME'] ?? await systemDeviceName();
}

/// What the user typed as the server, as a URL: https unless they said otherwise.
Uri normalizeServer(String input) {
  final text = input.trim();

  return Uri.parse(text.contains('://') ? text : 'https://$text');
}
