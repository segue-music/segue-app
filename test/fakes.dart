import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/player/engine.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/subsonic/api.dart';

/// An engine with no audio: a queue and a clock, like the real one. Its clock is [clock], so that a test
/// in fake time (fake_async) plays in it.
class FakeEngine implements AudioEngine {
  final _changes = StreamController<void>.broadcast(sync: true);

  /// The tracks open got, and their streams as they were then, from the start.
  List<TrackSource> opened = [];
  List<Uri> tracks = [];
  int _index = 0;
  bool _playing = false;
  int _volume = 100;
  List<int> _order = [];
  Repeat _repeat = Repeat.off;
  bool _shuffle = false;
  Duration _position = Duration.zero;
  DateTime _since = clock.now();
  bool _failed = false;

  /// The current track's gain, as [updateGain] last asked it; null before it did.
  TrackGain? gain;

  /// The equalizer's gains, as [setEqualizer] last set them; null before it did.
  Map<int, double>? equalizer;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  bool get playing => _playing;

  @override
  int get index => _index;

  @override
  Duration get position => _playing ? _position + clock.now().difference(_since) : _position;

  @override
  int get volume => _volume;

  @override
  List<int> get order => _order;

  @override
  Repeat get repeat => _repeat;

  @override
  bool get shuffle => _shuffle;

  @override
  bool get failed => _failed;

  /// As when the current track fails to load: the engine stops on it, paused.
  void fail() {
    _failed = true;
    _seek(Duration.zero);
    _playing = false;
    _changes.add(null);
  }

  @override
  Future<void> open(
    List<TrackSource> tracks, {
    required int index,
    required Duration position,
    required bool play,
  }) async {
    _failed = false;
    opened = tracks;
    _order = [for (var i = 0; i < tracks.length; i++) i];
    _index = index;

    if (_shuffle) {
      _shuffleOrder();
    }

    _seek(position);
    _playing = play;
    this.tracks = [for (final track in tracks) track.address()];
    _changes.add(null);
  }

  @override
  Future<int> add(List<TrackSource> tracks, {required bool next}) async {
    if (opened.isEmpty) {
      return -1;
    }

    final at = next ? _order[_index] + 1 : opened.length;
    final place = next ? _index + 1 : _order.length;
    final moved = [for (final track in _order) track < at ? track : track + tracks.length];
    _order = [...moved.take(place), for (var i = 0; i < tracks.length; i++) at + i, ...moved.skip(place)];
    opened = [...opened.take(at), ...tracks, ...opened.skip(at)];
    this.tracks = [...this.tracks.take(at), for (final track in tracks) track.address(), ...this.tracks.skip(at)];
    _changes.add(null);
    return at;
  }

  @override
  Future<({int from, int to})?> move(int from, int to) async {
    if (from < 0 || from >= _order.length || to < 0 || to >= _order.length) {
      return null;
    }

    final current = _order[_index];
    _order = [..._order]
      ..removeAt(from)
      ..insert(to, _order[from]);
    _index = _order.indexOf(current);
    ({int from, int to})? unshuffled;

    // Unshuffled, the tracks move in their order too, which stays the play order.
    if (!_shuffle) {
      opened = [...opened]
        ..removeAt(from)
        ..insert(to, opened[from]);
      tracks = [...tracks]
        ..removeAt(from)
        ..insert(to, tracks[from]);
      _order = [for (var i = 0; i < _order.length; i++) i];
      unshuffled = (from: from, to: to);
    }

    _changes.add(null);
    return unshuffled;
  }

  @override
  Future<int> remove(int index) async {
    if (index < 0 || index >= _order.length || index == _index) {
      return -1;
    }

    final at = _order[index];
    _order = [
      for (final (i, track) in _order.indexed)
        if (i != index) track < at ? track : track - 1,
    ];

    if (index < _index) {
      _index--;
    }

    opened = [...opened]..removeAt(at);
    tracks = [...tracks]..removeAt(at);
    _changes.add(null);
    return at;
  }

  @override
  Future<void> setRepeat(Repeat mode) async {
    _repeat = mode;
    _changes.add(null);
  }

  @override
  Future<void> setShuffle(bool on) async {
    if (on == _shuffle) {
      return;
    }

    _shuffle = on;

    if (on) {
      _shuffleOrder();
    } else if (_order.isNotEmpty) {
      _index = _order[_index];
      _order = [for (var i = 0; i < _order.length; i++) i];
    }

    _changes.add(null);
  }

  /// A predictable shuffle: the current track first, then the others backwards.
  void _shuffleOrder() {
    if (_order.isEmpty) {
      return;
    }

    final current = _order[_index];
    _order = [current, ..._order.reversed.where((track) => track != current)];
    _index = 0;
  }

  @override
  Future<void> play() async => _setPlaying(true);

  @override
  Future<void> pause() async => _setPlaying(false);

  @override
  Future<void> stop() async {
    _failed = false;
    opened = [];
    tracks = [];
    _order = [];
    _index = 0;
    _seek(Duration.zero);
    _playing = false;
    _changes.add(null);
  }

  @override
  Future<void> jump(int index) async {
    _failed = false;
    _index = index;
    _seek(Duration.zero);
    _playing = true;
    _changes.add(null);
  }

  @override
  Future<void> seek(Duration position) async => _seek(position); // like media_kit: not a change

  @override
  Future<void> setVolume(int volume) async {
    _volume = volume;
    _changes.add(null);
  }

  @override
  Future<void> updateGain() async => gain = opened.isEmpty ? null : opened[_order[_index]].gain();

  @override
  Future<void> setEqualizer(Map<int, double> gains) async => equalizer = gains;

  @override
  Future<void> dispose() => _changes.close();

  void _setPlaying(bool playing) {
    _failed &= !playing; // play tries the track again
    _seek(position);
    _playing = playing;
    _changes.add(null);
  }

  void _seek(Duration position) {
    _position = position;
    _since = clock.now();
  }
}

/// A Subsonic server whose songs are their ids' bytes, and whose covers are images of their ids, but for those in
/// [failing], which it answers with an error, and those in [held], which it answers once their completer is; out of
/// reach ([reachable] false), it answers nothing. Its artists are [artists], by their ids, as getArtist gives them; it
/// counts plays (scrobble) and answers pings. Pictures from elsewhere (`fanart.test`) are images of their paths. It
/// keeps what it is asked for: by endpoint and id ([requests]), and whole ([urls]).
class FileServer {
  final requests = <String>[];
  final urls = <Uri>[];
  final failing = <String>{};
  final held = <String, Completer<void>>{};
  final artists = <String, Map<String, Object?>>{};
  bool reachable = true;

  late final client = MockClient((request) async {
    if (!reachable) {
      throw http.ClientException('no route to host', request.url);
    }

    urls.add(request.url);

    if (request.url.host == 'fanart.test') {
      requests.add('fanart ${request.url.path}');
      return http.Response.bytes(utf8.encode('picture at ${request.url.path}'), 200);
    }

    final id = request.url.queryParameters['id'] ?? '';
    final endpoint = request.url.pathSegments.last;
    requests.add('$endpoint $id');
    await held[id]?.future;

    if (failing.contains(id)) {
      return http.Response('', 500);
    }

    http.Response subsonic(Map<String, Object?> body) => http.Response(
      jsonEncode({
        'subsonic-response': {'status': 'ok', ...body},
      }),
      200,
    );

    return switch (endpoint) {
      'stream.view' => http.Response.bytes(utf8.encode('audio of $id'), 200),
      'getCoverArt.view' => http.Response.bytes(
        utf8.encode('image of $id'),
        200,
        headers: {'content-type': 'image/jpeg'},
      ),
      'getArtist.view' when artists.containsKey(id) => subsonic({'artist': artists[id]}),
      'scrobble.view' || 'ping.view' => subsonic({}),
      _ => http.Response('', 404),
    };
  });

  late final api = SubsonicApi(
    Uri.parse('https://music.test'),
    const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
    client: client,
  );
}
