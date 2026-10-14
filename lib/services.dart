import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'connect/connect.dart';
import 'download_choice.dart';
import 'downloads/downloads.dart';
import 'downloads/pending_plays.dart';
import 'downloads/server_with_downloads.dart';
import 'home_cache.dart';
import 'lyrics/lrclib.dart';
import 'mobile_data.dart';
import 'player/crossfade_engine.dart';
import 'player/engine.dart';
import 'player/play_counter.dart';
import 'pictures/cover_cache.dart';
import 'pictures/fanart_tv.dart';
import 'player/player.dart';
import 'player/sleep_timer.dart';
import 'quality_choice.dart';
import 'releases/musicbrainz.dart';
import 'segue/client.dart';
import 'segue/discovery.dart';
import 'segue/protocol.dart';
import 'server/favorites.dart';
import 'server/models.dart';
import 'server/playlist_editor.dart';
import 'server/reachability.dart';
import 'server/server.dart';
import 'server/sign_in.dart';
import 'session.dart';
import 'settings.dart';

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
    this.sleepTimer,
    this.homeCache,
    this.covers,
  });

  /// Starts a session: the API, with what the user downloaded, this device's player, which plays as [settings] say (its
  /// quality, loudness, equalizer, autoplay, crossfade and volume; with none, the songs as they are, one after the other
  /// to the queue's end, as loud as the system's volume), and the connection to the hub last found next to the media
  /// server, which reaches it once it can. It waits for nothing from the network, which out of reach took a few seconds:
  /// the media server is pinged meanwhile, what asks it waiting for the answer ([Reachability.settled]), and the hub is
  /// looked for ([_discoverHub]).
  static Future<Services> start(Session session, {AudioEngine? engine, Settings? settings}) async {
    final server = openServer(
      session.server,
      session.credentials,
      deviceId: session.deviceId,
      deviceName: session.deviceName,
    );
    final reachability = Reachability(server.ping);

    unawaited(reachability.check());

    final mobileData = await MobileData.watch();
    final lrclib = Lrclib();
    final fanartTv = fanartTvKey.isEmpty ? null : FanartTv(apiKey: fanartTvKey);
    final downloadHold = DownloadHold(settings?.download ?? ValueNotifier(const DownloadSettings()), mobileData);

    // Where there is nowhere to keep them, none: the app plays from the server alone.
    Downloads? downloads;
    PendingPlays? pendingPlays;

    try {
      final directory = await downloadsDirectory(session);
      downloads = await Downloads.open(
        directory,
        server,
        reachability: reachability,
        maxBitRate: () => settings?.download.value.quality.maxBitRate,
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

    // Where there is nowhere to keep them, none: the home comes from the server alone, and the covers.
    HomeCache? homeCache;
    CoverCache? covers;

    try {
      final directory = await cacheDirectory(session);
      homeCache = await HomeCache.open(File('${directory.path}/home.json'), reachability: reachability);
      covers = CoverCache(Directory('${directory.path}/covers'));
      unawaited(covers.trim());
    } on Object catch (e) {
      debugPrint('cache unavailable: $e');
    }

    final player = PlayerController(
      engine ?? MediaKitEngine(),
      api,
      quality: () => (settings?.quality.value ?? StreamQuality.original).inUse(onMobileData: mobileData.value),
      replayGain: settings?.replayGain,
      equalizer: settings?.equalizer,
      autoplay: settings?.autoplay,
      crossfade: settings?.crossfade,
      crossfadeEngine: settings == null ? null : () => CrossfadeEngine(() => settings.crossfade.value),
      volume: settings?.volume,
    );
    final rememberedHub = await _rememberedHub(session.server);
    final services = Services(
      session,
      api,
      player,
      ConnectController(player: player),
      lrclib: lrclib,
      musicBrainz: MusicBrainz(remembersCountries: true),
      fanartTv: fanartTv,
      playCounter: PlayCounter(player, api),
      mobileData: mobileData,
      downloads: downloads,
      reachability: reachability,
      downloadHold: downloadHold,
      sleepTimer: SleepTimer(player),
      homeCache: homeCache,
      covers: covers,
    );

    if (rememberedHub != null) {
      services._join(rememberedHub);
    }

    unawaited(services._discoverHub());
    unawaited(services._loadFavorites());
    reachability.addListener(() {
      if (reachability.value) {
        unawaited(services._loadFavorites());
      }
    });

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

  /// The user's favorite songs, albums and artists, which the app changes through it too. [start] loads them, and loads
  /// them again as the media server comes back in reach.
  late final favorites = Favorites(api);

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

  /// What pauses [player] after a while, or as the song ends; null, nothing does, nor shows a way to.
  final SleepTimer? sleepTimer;

  /// What the home showed, which it shows at once as the app opens; null, nothing kept.
  final HomeCache? homeCache;

  /// The covers and pictures shown, kept on the device; null, none are, each loaded again.
  final CoverCache? covers;

  bool _disposed = false;

  /// Connects to the hub at [url], [connect] going through it.
  void _join(Uri url) {
    final client = SegueClient(
      url: url,
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

    connect.attach(client);
    unawaited(client.start());
  }

  /// Looks for the hub next to the media server, which is kept for the next time ([Session.foundHub]): the connection
  /// goes to it, as it starts where none was known (the first time, or a hub new there), and where the one known has
  /// moved, as it connects again. Not found, the one known stays, the server in reach too: a request that failed as the
  /// app opened (the network blinking, a VPN coming up) left the app without one until it was opened again.
  Future<void> _discoverHub() async {
    final found = await discoverHub(session.server, hub: session.hub);

    if (found == null || _disposed) {
      return;
    }

    await _rememberHub(session.server, found);

    if (_disposed) {
      return;
    }

    if (connect.client case final client?) {
      client.url = found;
    } else {
      _join(found);
    }
  }

  /// Loads the favorites, where the media server gives them.
  Future<void> _loadFavorites() async {
    try {
      await favorites.load();
    } on Object catch (e) {
      debugPrint('favorites unknown: $e');
    }
  }

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
  static Future<Directory> downloadsDirectory(Session session) async =>
      Directory('${(await getApplicationSupportDirectory()).path}/downloads/${_account(session)}');

  /// Where what is kept of [session]'s user on its server, to show at once, is ([HomeCache], [CoverCache]): a folder of
  /// their own in the app's cache, which the system may empty.
  static Future<Directory> cacheDirectory(Session session) async =>
      Directory('${(await getApplicationCacheDirectory()).path}/library/${_account(session)}');

  /// Deletes what is kept of [session]'s user, as they sign out ([cacheDirectory]).
  static Future<void> clearCache(Session session) async {
    try {
      final directory = await cacheDirectory(session);

      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on Object catch (e) {
      debugPrint('cache not cleared: $e');
    }
  }

  /// A folder's name for [session]'s user on its server: both, in base 64, as URLs have it, without its padding.
  static String _account(Session session) =>
      base64Url.encode(utf8.encode('${session.server}\n${session.credentials.username}')).replaceAll('=', '');

  Future<void> dispose() async {
    _disposed = true;
    connect.dispose();
    playlistEditor.dispose();
    favorites.dispose();
    playCounter?.dispose();
    sleepTimer?.dispose();
    mobileData?.dispose();
    // Before the hub's connection, whose close can wait on the network: a window closing waits for the player, which
    // left playing as the app ends aborts it (app.dart, _exit).
    await player.dispose();
    await connect.client?.close();
    api.close();
    lrclib?.close();
    musicBrainz?.close();
    fanartTv?.close();
    downloads?.dispose();
    downloadHold?.dispose();
    reachability?.dispose();
    homeCache?.close();
    covers?.close();
  }
}

/// Hands [Services] down the widget tree.
class ServicesScope extends InheritedWidget {
  const ServicesScope({required this.services, required super.child, super.key});

  final Services services;

  static Services of(BuildContext context) => maybeOf(context)!;

  /// The services, where there are some: a picture from elsewhere shows without them.
  static Services? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>()?.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) => services != oldWidget.services;
}
