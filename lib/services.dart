import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'connect/connect.dart';
import 'lyrics/lrclib.dart';
import 'mobile_data.dart';
import 'player/engine.dart';
import 'player/play_counter.dart';
import 'pictures/fanart_tv.dart';
import 'player/player.dart';
import 'quality_choice.dart';
import 'releases/musicbrainz.dart';
import 'segue/client.dart';
import 'segue/discovery.dart';
import 'segue/protocol.dart';
import 'server/playlist_editor.dart';
import 'server/server.dart';
import 'server/sign_in.dart';
import 'session.dart';

/// Everything a signed-in session runs on.
class Services {
  Services(
    this.session,
    this.api,
    this.player,
    this.connect, {
    this.lrclib,
    this.musicBrainz,
    this.fanartTv,
    this.playCounter,
    this.mobileData,
  });

  /// Starts a session: the API, this device's player, which streams in the quality picked ([quality]; the automatic one,
  /// with none) and, if a hub is found, the connection to it.
  static Future<Services> start(Session session, {AudioEngine? engine, ValueListenable<StreamQuality>? quality}) async {
    final api = openServer(
      session.server,
      session.credentials,
      deviceId: session.deviceId,
      deviceName: session.deviceName,
    );
    final mobileData = await MobileData.watch();
    final player = PlayerController(
      engine ?? MediaKitEngine(),
      api,
      quality: () => (quality?.value ?? StreamQuality.automatic).inUse(onMobileData: mobileData.value),
    );
    final hubUrl = await discoverHub(session.server, hub: session.hub);
    final client = hubUrl == null
        ? null
        : SegueClient(
            url: hubUrl,
            auth: api.auth,
            device: DeviceInfo(
              id: session.deviceId,
              name: session.deviceName,
              client: clientName,
              version: appVersion,
              api: api.api,
              roles: Role.values,
              capabilities: CommandAction.values,
            ),
          );
    final services = Services(
      session,
      api,
      player,
      ConnectController(player: player, client: client),
      lrclib: Lrclib(),
      musicBrainz: MusicBrainz(remembersCountries: true),
      fanartTv: fanartTvKey.isEmpty ? null : FanartTv(apiKey: fanartTvKey),
      playCounter: PlayCounter(player, api),
      mobileData: mobileData,
    );
    unawaited(client?.start());
    return services;
  }

  final Session session;
  final MediaServer api;
  final PlayerController player;
  final ConnectController connect;

  /// What the app changes the user's playlists through.
  late final playlistEditor = PlaylistEditor(api);

  /// Where lyrics come from when the media server has none; null, nowhere.
  final Lrclib? lrclib;

  /// Where an album's release date and record labels come from when the media server doesn't say them; null,
  /// nowhere.
  final MusicBrainz? musicBrainz;

  /// Where more pictures of an artist than the media server's one come from, for their biography; null, nowhere, as
  /// in a build without the app's key.
  final FanartTv? fanartTv;

  /// What counts the player's plays on the media server; null, nothing.
  final PlayCounter? playCounter;

  /// Whether the device is on mobile data, for the automatic quality; null, never.
  final MobileData? mobileData;

  Future<void> dispose() async {
    connect.dispose();
    playlistEditor.dispose();
    await connect.client?.close();
    playCounter?.dispose();
    mobileData?.dispose();
    await player.dispose();
    api.close();
    lrclib?.close();
    musicBrainz?.close();
    fanartTv?.close();
  }
}

/// Hands [Services] down the widget tree.
class ServicesScope extends InheritedWidget {
  const ServicesScope({required this.services, required super.child, super.key});

  final Services services;

  static Services of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ServicesScope>()!.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) => services != oldWidget.services;
}
