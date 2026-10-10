import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'connect/connect.dart';
import 'download_choice.dart';
import 'downloads/downloads.dart';
import 'downloads/pending_plays.dart';
import 'downloads/server_with_downloads.dart';
import 'equalizer_choice.dart';
import 'lyrics/lrclib.dart';
import 'mobile_data.dart';
import 'player/engine.dart';
import 'player/play_counter.dart';
import 'pictures/fanart_tv.dart';
import 'player/player.dart';
import 'quality_choice.dart';
import 'replay_gain_choice.dart';
import 'releases/musicbrainz.dart';
import 'segue/client.dart';
import 'segue/discovery.dart';
import 'segue/protocol.dart';
import 'server/models.dart';
import 'server/playlist_editor.dart';
import 'server/reachability.dart';
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
    this.downloads,
    this.reachability,
    this.downloadHold,
  });

  /// Starts a session: the API, with what the user downloaded, this device's player, which streams in the quality picked
  /// ([quality]; the original, with none), levels the songs' loudness the way picked ([replayGain]; not at all, with
  /// none) and plays them through the equalizer as set ([equalizer]; as they are, with none), and, if a hub is found,
  /// the connection to it. With the media server out of reach, the hub is the one last found next to it, which the
  /// connection reaches once it can.
  static Future<Services> start(
    Session session, {
    AudioEngine? engine,
    ValueListenable<StreamQuality>? quality,
    ValueListenable<ReplayGainMode>? replayGain,
    ValueListenable<EqualizerSettings>? equalizer,
    ValueListenable<DownloadSettings>? downloadSettings,
  }) async {
    final server = openServer(
      session.server,
      session.credentials,
      deviceId: session.deviceId,
      deviceName: session.deviceName,
    );
    final reachability = Reachability(server.ping);
    // At once, rather than one after the other: out of reach, each waits for nothing to answer.
    final (reachable, foundHub) = await (reachability.check(), discoverHub(session.server, hub: session.hub)).wait;
    final mobileData = await MobileData.watch();
    final lrclib = Lrclib();
    final fanartTv = fanartTvKey.isEmpty ? null : FanartTv(apiKey: fanartTvKey);
    final downloadHold = DownloadHold(downloadSettings ?? ValueNotifier(const DownloadSettings()), mobileData);
    // Where there is nowhere to keep them, none: the app plays from the server alone.
    Downloads? downloads;
    PendingPlays? pendingPlays;

    try {
      final directory = await downloadsDirectory(session);
      downloads = await Downloads.open(
        directory,
        server,
        reachability: reachability,
        maxBitRate: () => downloadSettings?.value.quality.maxBitRate,
        hold: downloadHold,
        lyricsOf: (song) => _lyricsOf(song, server, lrclib),
        artistPicture: fanartTv == null ? null : (artist) => _fanartPicture(artist, fanartTv),
      );
      pendingPlays = await PendingPlays.open(File('${directory.path}/plays.json'));
    } on Object catch (e) {
      debugPrint('downloads unavailable: $e');
    }

    final api = downloads == null
        ? server
        : ServerWithDownloads(server, downloads, reachability, pendingPlays: pendingPlays);
    final player = PlayerController(
      engine ?? MediaKitEngine(),
      api,
      quality: () => (quality?.value ?? StreamQuality.original).inUse(onMobileData: mobileData.value),
      replayGain: replayGain,
      equalizer: equalizer,
    );
    final hubUrl = foundHub ?? (reachable ? null : await _rememberedHub(session.server));

    if (foundHub != null) {
      await _rememberHub(session.server, foundHub);
    }

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
      lrclib: lrclib,
      musicBrainz: MusicBrainz(remembersCountries: true),
      fanartTv: fanartTv,
      playCounter: PlayCounter(player, api),
      mobileData: mobileData,
      downloads: downloads,
      reachability: reachability,
      downloadHold: downloadHold,
    );
    unawaited(client?.start());
    return services;
  }

  /// The lyrics a downloaded [song] keeps: the media server's, or else LRCLIB's, as the lyrics' view finds them. LRCLIB
  /// failing for the network fails them as anything else would, to be asked again, rather than as the media server
  /// out of reach.
  static Future<Lyrics?> _lyricsOf(Song song, MediaServer server, Lrclib lrclib) async {
    final lyrics = await server.lyrics(song.id);
    final artist = song.artist;

    if (lyrics != null || artist == null) {
      return lyrics;
    }

    try {
      return await lrclib.find(title: song.title, artist: artist, album: song.album, duration: song.duration);
    } on Object catch (e) {
      throw Exception('LRCLIB: $e');
    }
  }

  /// The picture of [artist] fanart.tv's users like most, for a download; failing as [_lyricsOf]'s LRCLIB does.
  static Future<Uri?> _fanartPicture(Artist artist, FanartTv fanartTv) async {
    try {
      return (await fanartTv.artistPictures(artist)).firstOrNull;
    } on Object catch (e) {
      throw Exception('fanart.tv: $e');
    }
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

  /// The albums and playlists the user downloaded; null, none, nor a way to download them.
  final Downloads? downloads;

  /// Whether the media server is in reach; null, as it always were.
  final Reachability? reachability;

  /// Whether the downloads wait for Wi-Fi or a cable; null, they never do.
  final DownloadHold? downloadHold;

  /// The hub last found next to [server] ([Session.foundHub]); null where none was, or the preferences can't be read.
  static Future<Uri?> _rememberedHub(Uri server) async {
    try {
      return await Session.foundHub(server);
    } on Object catch (e) {
      debugPrint('found hub unknown: $e');
      return null;
    }
  }

  /// Keeps [hub] as the hub found next to [server], where the preferences can be written.
  static Future<void> _rememberHub(Uri server, Uri hub) async {
    try {
      await Session.rememberFoundHub(server, hub);
    } on Object catch (e) {
      debugPrint('found hub not kept: $e');
    }
  }

  /// Where the downloads of [session]'s user on its server are kept: a folder of their own, in the app's.
  static Future<Directory> downloadsDirectory(Session session) async {
    final account = base64Url
        .encode(utf8.encode('${session.server}\n${session.credentials.username}'))
        .replaceAll('=', '');
    return Directory('${(await getApplicationSupportDirectory()).path}/downloads/$account');
  }

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
    downloads?.dispose();
    downloadHold?.dispose();
    reachability?.dispose();
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
