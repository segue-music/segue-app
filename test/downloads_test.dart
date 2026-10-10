import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/downloads/downloads.dart';
import 'package:segue/downloads/server_with_downloads.dart';
import 'package:segue/server/models.dart';
import 'package:segue/server/reachability.dart';
import 'package:segue/server/server.dart';
import 'package:segue/subsonic/api.dart';

import 'fakes.dart';

const album = Album(
  id: 'al1',
  name: 'Toys in the Attic',
  artist: 'Aerosmith',
  artistId: 'ar1',
  coverArt: 'al1',
  year: 1975,
  releaseDate: ReleaseDate(1975, month: 4, day: 8),
  genres: [Genre(id: 'Rock', name: 'Rock')],
  releaseType: ReleaseType.album,
);

const songs = [
  Song(
    id: 's1',
    title: 'Walk This Way',
    artist: 'Aerosmith',
    album: 'Toys in the Attic',
    albumId: 'al1',
    coverArt: 'al1',
    duration: Duration(seconds: 220),
    artists: [Artist(id: 'ar1', name: 'Aerosmith')],
    replayGain: ReplayGain(trackGain: -6.5, albumGain: -7, trackPeak: 0.9),
  ),
  Song(id: 's2', title: 'Sweet Emotion', artist: 'Aerosmith', albumId: 'al1', coverArt: 'al1'),
];

const playlist = Playlist(id: 'p1', name: 'Road trip', coverArt: 'p1', songCount: 2);

/// Waits for [downloads] to have nothing left to fetch, or to stop fetching: until no file came for a while.
Future<void> settled(Downloads downloads) async {
  for (var quiet = 0; quiet < 10; quiet++) {
    final changed = Completer<void>();

    void done() => changed.isCompleted ? null : changed.complete();

    downloads.addListener(done);
    await Future.any([changed.future, Future<void>.delayed(const Duration(milliseconds: 20))]);
    downloads.removeListener(done);

    if (changed.isCompleted) {
      quiet = 0;
    }
  }
}

void main() {
  late Directory directory;
  late FileServer server;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('segue-downloads');
    server = FileServer();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  /// The downloads opened, which the test closes ([close]), or else its end.
  final opened = <Downloads>[];
  tearDown(() {
    for (final downloads in opened) {
      downloads.dispose();
    }

    opened.clear();
  });

  Future<Downloads> open({Reachability? reachability}) async {
    final downloads = await Downloads.open(directory, server.api, client: server.client, reachability: reachability);
    opened.add(downloads);
    return downloads;
  }

  void close(Downloads downloads) {
    opened.remove(downloads);
    downloads.dispose();
  }

  test('an album downloaded has its songs as their files are and its covers on the device', () async {
    final downloads = await open();
    await downloads.addAlbum(album, songs);
    await settled(downloads);
    final download = downloads.ofAlbum('al1')!;
    expect(downloads.progressOf(download), (done: 2, failed: 0, total: 2));
    expect(downloads.songFile('s1')!.readAsStringSync(), 'audio of s1');
    expect(downloads.coverFile('al1')!.readAsStringSync(), 'image of al1');
    expect(downloads.songFile('s3'), isNull);
    // The files as they are: nothing transcoded. And the cover once, though each song names it.
    expect(server.requests, ['stream.view s1', 'stream.view s2', 'getCoverArt.view al1']);
    expect(Uri.parse(server.api.streamUrl('s1').toString()).queryParameters, isNot(contains('maxBitRate')));
  });

  test('downloads stay as the app opens again, with all they say of the album and its songs', () async {
    final first = await open();
    await first.addAlbum(album, songs);
    await settled(first);
    close(first);
    server.requests.clear();

    final again = await open();
    await settled(again);
    expect(server.requests, isEmpty, reason: 'nothing to fetch again');
    final download = again.ofAlbum('al1')!;
    expect(download.album!.releaseDate?.day, 8);
    expect(download.album!.genres.single.name, 'Rock');
    expect(download.album!.releaseType, ReleaseType.album);
    expect(download.songs.first.replayGain?.albumGain, -7);
    expect(download.songs.first.artists.single.name, 'Aerosmith');
    expect(download.songs.first.duration, const Duration(seconds: 220));
    expect(again.songFile('s2'), isNotNull);
  });

  test('a song in two downloads is on the device once, until both go', () async {
    final downloads = await open();
    await downloads.addAlbum(album, songs);
    await downloads.addPlaylist(playlist, [songs[1]]);
    await settled(downloads);
    expect(server.requests.where((request) => request == 'stream.view s2'), hasLength(1));
    expect(downloads.all.map((download) => download.name), ['Road trip', 'Toys in the Attic']);

    await downloads.remove(downloads.ofAlbum('al1')!);
    expect(downloads.songFile('s1'), isNull);
    expect(Directory('${directory.path}/songs').listSync(), hasLength(1));
    expect(downloads.songFile('s2'), isNotNull);

    await downloads.remove(downloads.ofPlaylist('p1')!);
    expect(downloads.songFile('s2'), isNull);
    expect(downloads.coverFile('al1'), isNull);
    expect(Directory('${directory.path}/songs').listSync(), isEmpty);
    expect(Directory('${directory.path}/covers').listSync(), isEmpty);
  });

  test('a song that fails to come is tried again, as asked', () async {
    final downloads = await open();
    server.failing.add('s2');
    await downloads.addAlbum(album, songs);
    await settled(downloads);
    expect(downloads.progressOf(downloads.ofAlbum('al1')!), (done: 1, failed: 1, total: 2));

    server.failing.clear();
    downloads.retry();
    await settled(downloads);
    expect(downloads.progressOf(downloads.ofAlbum('al1')!), (done: 2, failed: 0, total: 2));
  });

  test('with the server out of reach, nothing comes until it is back', () async {
    final reachability = Reachability(() async {
      if (!server.reachable) {
        throw const SocketException('no route to host');
      }
    }, retry: const Duration(hours: 1));
    addTearDown(reachability.dispose);
    server.reachable = false;
    await reachability.check();
    final downloads = await open(reachability: reachability);
    await downloads.addAlbum(album, songs);
    await settled(downloads);
    expect(server.requests, isEmpty);
    expect(downloads.progressOf(downloads.ofAlbum('al1')!), (done: 0, failed: 0, total: 2));

    server.reachable = true;
    await reachability.check();
    await settled(downloads);
    expect(downloads.progressOf(downloads.ofAlbum('al1')!), (done: 2, failed: 0, total: 2));
  });

  test('a download that fails for the network tells that the server is out of reach', () async {
    final reachability = Reachability(() async {}, retry: const Duration(hours: 1));
    addTearDown(reachability.dispose);
    final downloads = await open(reachability: reachability);
    server.reachable = false;
    await downloads.addAlbum(album, songs);
    await settled(downloads);
    expect(reachability.value, isFalse);
    expect(downloads.progressOf(downloads.ofAlbum('al1')!).done, 0);
  });

  test('an index that can\'t be read leaves the files there', () async {
    final first = await open();
    await first.addAlbum(album, songs);
    await settled(first);
    close(first);
    File('${directory.path}/index.json').writeAsStringSync('{not json');

    final again = await open();
    expect(again.all, isEmpty);
    expect(Directory('${directory.path}/songs').listSync(), hasLength(2));
  });

  group('the server with the downloads', () {
    late Reachability reachability;
    late Downloads downloads;
    late ServerWithDownloads api;

    setUp(() async {
      reachability = Reachability(() async {
        if (!server.reachable) {
          throw const SocketException('no route to host');
        }
      }, retry: const Duration(hours: 1));
      addTearDown(reachability.dispose);
      downloads = await open(reachability: reachability);
      await downloads.addAlbum(album, songs);
      await downloads.addPlaylist(playlist, [songs[1]]);
      await settled(downloads);
      api = ServerWithDownloads(server.api, downloads, reachability);
    });

    test('a downloaded song plays from its file, and a downloaded cover shows from its own, in reach too', () async {
      expect(api.streamUrl('s1', maxBitRate: 160), downloads.songFile('s1')!.uri);
      expect(await api.transcodedStreamUrl('s1', maxBitRate: 160, from: const Duration(seconds: 30)), isNull);
      expect(api.streamUrl('s3').host, 'music.test');
      expect(api.coverArtUrl('al1', size: 300), downloads.coverFile('al1')!.uri);
      expect(utf8.decode(await api.coverArt('al1')), 'image of al1');
      expect(api.coverArtUrl('al9').host, 'music.test');
    });

    test('out of reach, the albums, playlists, artists and genres are the downloaded ones', () async {
      server.reachable = false;
      await reachability.check();
      expect((await api.albums(order: AlbumOrder.name)).map((album) => album.name), ['Toys in the Attic']);
      expect(await api.albums(order: AlbumOrder.mostPlayed), isEmpty);
      expect((await api.album('al1')).$2.map((song) => song.title), ['Walk This Way', 'Sweet Emotion']);
      expect((await api.playlists()).single.name, 'Road trip');
      expect((await api.playlist('p1')).$2.single.id, 's2');
      expect((await api.artists()).single, isA<Artist>().having((artist) => artist.albumCount, 'albumCount', 1));
      expect((await api.artist('ar1')).$2.single.id, 'al1');
      expect((await api.genres()).single.name, 'Rock');
      expect((await api.genreAlbums('Rock')).single.id, 'al1');
      expect((await api.search('sweet')).songs.single.id, 's2');
      expect((await api.search('attic')).albums.single.id, 'al1');
      expect(await api.lyrics('s1'), isNull);
      expect(await api.mostPlayedAlbums(), isEmpty);
      await expectLater(api.album('al9'), throwsA(ServerWithDownloads.unreachable));
      await expectLater(api.renamePlaylist('p1', 'Other'), throwsA(ServerWithDownloads.unreachable));
      expect(server.requests.where((request) => !request.startsWith('stream') && !request.startsWith('get')), isEmpty);
    });

    test(
      'a request that fails for the network takes the downloads, and the server is out of reach from then',
      () async {
        server.reachable = false;
        expect((await api.playlists()).single.name, 'Road trip');
        expect(reachability.value, isFalse);
      },
    );

    test('a refusal is the server answering: it fails as it is', () async {
      final refusing = SubsonicApi(
        Uri.parse('https://music.test'),
        const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
        client: MockClient((_) async => http.Response('', 503)),
      );
      final api = ServerWithDownloads(refusing, downloads, reachability);
      await expectLater(api.playlists(), throwsA(isA<ServerError>()));
      expect(reachability.value, isTrue);
    });
  });
}
