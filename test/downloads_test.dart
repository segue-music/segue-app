import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/downloads/downloads.dart';
import 'package:segue/downloads/pending_plays.dart';
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
  discTitles: {1: 'Side A'},
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
    track: 4,
    disc: 1,
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
    server = FileServer()..artists['ar1'] = {'id': 'ar1', 'name': 'Aerosmith', 'coverArt': 'ar-ar1'};
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

  Future<Downloads> open({
    Reachability? reachability,
    int? Function()? maxBitRate,
    ValueListenable<bool>? hold,
    Future<Lyrics?> Function(Song song)? lyricsOf,
    Future<Uri?> Function(Artist artist)? artistPicture,
  }) async {
    final downloads = await Downloads.open(
      directory,
      server.api,
      client: server.client,
      reachability: reachability,
      maxBitRate: maxBitRate,
      hold: hold,
      lyricsOf: lyricsOf,
      artistPicture: artistPicture,
    );

    opened.add(downloads);

    return downloads;
  }

  Future<void> close(Downloads downloads) {
    opened.remove(downloads);

    return downloads.close();
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
    // The files as they are: nothing transcoded. And the cover once, though each song names it; then the artist, with
    // their picture.
    expect(server.requests, [
      'stream.view s1',
      'stream.view s2',
      'getCoverArt.view al1',
      'getArtist.view ar1',
      'getCoverArt.view ar-ar1',
    ]);
    expect(downloads.artist('ar1')?.coverArt, 'ar-ar1');
    expect(downloads.coverFile('ar-ar1')!.readAsStringSync(), 'image of ar-ar1');
    expect(
      [
        for (final url in server.urls)
          if (url.path.endsWith('stream.view')) url.queryParameters['maxBitRate'],
      ],
      [null, null],
    );
  });

  test('downloads stay as the app opens again, with all they say of the album and its songs', () async {
    final first = await open();

    await first.addAlbum(album, songs);
    await settled(first);
    await close(first);
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
    expect((download.songs.first.track, download.songs.first.disc), (4, 1));
    expect(download.album!.discTitles, {1: 'Side A'});
    expect(again.songFile('s2'), isNotNull);
  });

  group('the server\'s ids from before Navidrome 0.64', () {
    // A library older than Navidrome 0.55, whose ids were hex, as 0.64 writes them in base 62; a playlist's was a UUID.
    const oldAlbum = 'e3b7fc2ae9447bbec37a13bf916e3cf6', newAlbum = '6VHl3uR4kss6sUPKA8Cwnk';
    const oldSong = '000000000000000000000000000000ff', newSong = '0000000000000000000047';
    const oldPlaylist = 'f47ac10b-58cc-4372-a567-0e02b2c3d479', newPlaylist = '7rke2SAWaicSeSYzkhww6R';
    const song = Song(
      id: oldSong,
      title: 'Walk This Way',
      albumId: oldAlbum,
      coverArt: 'mf-${oldSong}_0',
      artists: [Artist(id: 'ar1', name: 'Aerosmith')],
    );

    /// A file's path under the downloads' folder, as they name it after an id.
    String file(String folder, String id) => '$folder/${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';

    test(
      'downloads take the ids the server has now, as it answers, their files renamed rather than downloaded again',
      () async {
        server.version = '0.63.2 (1a2b3c4)';
        final lyrics = Lyrics([LyricLine('Backstroke lover')]);
        final first = await open(lyricsOf: (song) async => lyrics);

        await first.addAlbum(
          const Album(
            id: oldAlbum,
            name: 'Toys in the Attic',
            artistId: 'ar1',
            coverArt: 'al-${oldAlbum}_0',
            genres: [Genre(id: 'Rock', name: 'Rock')],
          ),
          [song],
        );
        await first.addPlaylist(const Playlist(id: oldPlaylist, name: 'Road trip', coverArt: 'pl-${oldPlaylist}_0'), [
          song,
        ]);
        await settled(first);
        await close(first);
        server.requests.clear();

        server.version = '0.64.2 (1a2b3c4)';
        final reachability = Reachability(server.api.ping, retry: const Duration(hours: 1));

        addTearDown(reachability.dispose);
        unawaited(reachability.check());

        final again = await open(reachability: reachability, lyricsOf: (song) async => fail('lyrics asked again'));

        await settled(again);
        expect(server.requests, ['ping.view '], reason: 'nothing downloaded again');
        expect(again.ofAlbum(oldAlbum), isNull);

        final album = again.ofAlbum(newAlbum)!;

        expect(album.album!.coverArt, 'al-${newAlbum}_0');
        expect(album.album!.genres.single.id, 'Rock', reason: 'a genre is named by its name');
        expect(album.songs.single.id, newSong);
        expect(album.songs.single.albumId, newAlbum);
        expect(album.songs.single.coverArt, 'mf-${newSong}_0');
        expect(album.songs.single.artistId, 'ar1', reason: 'an artist\'s id was a hash already');

        final playlist = again.ofPlaylist(newPlaylist)!;

        expect(playlist.playlist!.coverArt, 'pl-${newPlaylist}_0');
        expect(again.progressOf(playlist), (done: 1, failed: 0, total: 1));
        expect(again.songFile(newSong)!.readAsStringSync(), 'audio of $oldSong');
        expect(again.coverFile('al-${newAlbum}_0')!.readAsStringSync(), 'image of al-${oldAlbum}_0');
        expect(again.coverFile('mf-${newSong}_0')!.readAsStringSync(), 'image of mf-${oldSong}_0');
        expect((await again.lyrics(newSong))?.lines.single.text, 'Backstroke lover');
        expect(again.artist('ar1')?.coverArt, 'ar-ar1');
        expect(Directory('${directory.path}/songs').listSync(), hasLength(1));
        await close(again);

        final third = await open();

        await settled(third);
        expect(third.ofAlbum(newAlbum), isNotNull, reason: 'the index keeps them');
        expect(third.songFile(newSong), isNotNull);
        expect(jsonDecode(File('${directory.path}/index.json').readAsStringSync()), isNot(contains('renames')));
      },
    );

    test('a renaming cut short goes on as the downloads open again, rather than lose the files', () async {
      // As it was left: the index with the new ids, and the files to rename in it, still under the old ones.
      Directory('${directory.path}/songs').createSync();
      File('${directory.path}/${file('songs', oldSong)}').writeAsStringSync('audio of $oldSong');
      File('${directory.path}/index.json').writeAsStringSync(
        jsonEncode({
          'downloads': [
            {
              'album': const Album(id: newAlbum, name: 'Toys in the Attic').toJson(),
              'songs': [const Song(id: newSong, title: 'Walk This Way').toJson()],
              'added': 0,
            },
          ],
          'renames': {file('songs', oldSong): file('songs', newSong)},
        }),
      );

      final downloads = await open();

      await settled(downloads);
      expect(downloads.songFile(newSong)!.readAsStringSync(), 'audio of $oldSong');
      expect(server.requests, isNot(contains('stream.view $newSong')));
      expect(Directory('${directory.path}/songs').listSync(), hasLength(1));
      expect(jsonDecode(File('${directory.path}/index.json').readAsStringSync()), isNot(contains('renames')));
    });
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

  test(
    'downloads asked for at once go in the index one after the other: both are there as the app opens again',
    () async {
      final downloads = await open();

      await Future.wait([
        downloads.addAlbum(album, songs),
        downloads.addPlaylist(playlist, [songs[1]]),
      ]);
      await close(downloads);

      final again = await open();

      expect([for (final download in again.all) download.id], ['p1', 'al1']);
    },
  );

  test('a download taken off says so again once its files are gone, for the room they took to show', () async {
    final downloads = await open();

    await downloads.addAlbum(album, songs);
    await settled(downloads);

    final songsThere = <int>[];

    downloads.addListener(() => songsThere.add(Directory('${directory.path}/songs').listSync().length));
    await downloads.remove(downloads.ofAlbum('al1')!);
    expect(songsThere.last, 0);
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

  test('a song the server refuses with its error in place of the song, as a Subsonic server does, fails to come rather '
      'than comes as its error', () async {
    final downloads = await open();

    server.refused.add('s2');
    await downloads.addAlbum(album, songs);
    await settled(downloads);
    expect(downloads.progressOf(downloads.ofAlbum('al1')!), (done: 1, failed: 1, total: 2));
    expect(downloads.songFile('s2'), isNull);
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

  test('an index that can\'t be read goes aside, and leaves its files there, downloads to come and the app opening '
      'again too', () async {
    final first = await open();

    await first.addAlbum(album, songs);
    await settled(first);
    await close(first);
    File('${directory.path}/index.json').writeAsStringSync('{not json');

    final again = await open();

    expect(again.all, isEmpty);
    expect(File('${directory.path}/index.unreadable.json').readAsStringSync(), '{not json');
    expect(Directory('${directory.path}/songs').listSync(), hasLength(2));

    await again.addPlaylist(playlist, const [Song(id: 's3', title: 'Dream On', coverArt: 'al2')]);
    await settled(again);
    await close(again);

    final third = await open();

    await settled(third);
    expect(third.all.single.playlist?.id, 'p1');
    expect(third.songFile('s1')?.readAsStringSync(), 'audio of s1');
    expect(Directory('${directory.path}/songs').listSync(), hasLength(3));

    // Downloaded again, the album has its files, which go with it.
    await third.addAlbum(album, songs);
    await settled(third);
    await third.remove(third.ofAlbum('al1')!);
    expect(third.songFile('s1'), isNull);
    expect(Directory('${directory.path}/songs').listSync(), hasLength(1));
  });

  test('an index the disk fails to read stays as it is, and the downloads with it, to open the next time', () async {
    final first = await open();

    await first.addAlbum(album, songs);
    await settled(first);
    await close(first);

    final index = File('${directory.path}/index.json');
    final written = index.readAsStringSync();

    await Process.run('chmod', ['000', index.path]);

    try {
      index.readAsStringSync();
      await Process.run('chmod', ['644', index.path]);
      markTestSkipped('the disk reads it all the same, for root');
      return;
    } on FileSystemException {
      // as it should
    }

    await expectLater(open(), throwsA(isA<FileSystemException>()));
    await Process.run('chmod', ['644', index.path]);
    expect(index.readAsStringSync(), written);
    expect(Directory('${directory.path}/songs').listSync(), hasLength(2));
    expect((await open()).ofAlbum('al1'), isNotNull);
  });

  test('the songs come in the quality picked for downloads, as each comes', () async {
    var bitRate = 160;
    final downloads = await open(maxBitRate: () => bitRate);
    server.held['s2'] = Completer<void>();
    await downloads.addAlbum(album, songs);
    await settled(downloads);
    bitRate = 96;
    server.held.remove('s2')!.complete();
    await settled(downloads);

    final streams = server.urls.where((url) => url.path.endsWith('stream.view'));

    expect([for (final url in streams) url.queryParameters['maxBitRate']], ['160', '160']);

    await downloads.addPlaylist(playlist, [const Song(id: 's3', title: 'Other')]);
    await settled(downloads);
    expect(server.urls.lastWhere((url) => url.path.endsWith('stream.view')).queryParameters['maxBitRate'], '96');
  });

  test('held, as on mobile data, nothing comes until they are let go', () async {
    final hold = ValueNotifier(true);
    final downloads = await open(hold: hold);

    await downloads.addAlbum(album, songs);
    await settled(downloads);
    expect(downloads.held, isTrue);
    expect(server.requests, isEmpty);

    hold.value = false;
    await settled(downloads);
    expect(downloads.progressOf(downloads.ofAlbum('al1')!).done, 2);
  });

  test('the songs\' lyrics come with them, asked once, none too', () async {
    var asked = 0;

    Future<Lyrics?> lyricsOf(Song song) async {
      asked++;

      return song.id == 's1'
          ? const Lyrics([LyricLine('Backstroke lover', start: Duration(seconds: 12))], provider: 'LRCLIB')
          : null;
    }

    final downloads = await open(lyricsOf: lyricsOf);

    await downloads.addAlbum(album, songs);
    await settled(downloads);

    final lyrics = await downloads.lyrics('s1');

    expect(lyrics?.lines.single.text, 'Backstroke lover');
    expect(lyrics?.lines.single.start, const Duration(seconds: 12));
    expect(lyrics?.provider, 'LRCLIB');
    expect(await downloads.lyrics('s2'), isNull);
    expect(asked, 2);
    await close(downloads);

    final again = await open(lyricsOf: lyricsOf);

    await settled(again);
    expect(asked, 2);
    expect((await again.lyrics('s1'))?.lines, hasLength(1));
  });

  test('an artist the server has no picture of has the one found elsewhere, which goes with them', () async {
    server.artists['ar2'] = {'id': 'ar2', 'name': 'Run-DMC', 'musicBrainzId': 'mb2'};
    final downloads = await open(
      artistPicture: (artist) async => Uri.parse('https://fanart.test/${artist.musicBrainzId}.jpg'),
    );

    await downloads.addPlaylist(playlist, [
      const Song(
        id: 's9',
        title: 'Walk This Way',
        artists: [Artist(id: 'ar2', name: 'Run-DMC')],
      ),
    ]);
    await settled(downloads);
    expect(downloads.artist('ar2')?.coverArt, 'fanart:mb2');
    expect(downloads.coverFile('fanart:mb2')!.readAsStringSync(), 'picture at /mb2.jpg');

    await downloads.remove(downloads.ofPlaylist('p1')!);
    expect(downloads.artist('ar2'), isNull);
    expect(downloads.coverFile('fanart:mb2'), isNull);
  });

  test('the picture found elsewhere out of reach fails as anything else would, to come again, the server staying in '
      'reach', () async {
    final reachability = Reachability(() async {}, retry: const Duration(hours: 1));

    addTearDown(reachability.dispose);
    server
      ..artists['ar2'] = {'id': 'ar2', 'name': 'Run-DMC', 'musicBrainzId': 'mb2'}
      ..fanartReachable = false;

    final downloads = await open(
      reachability: reachability,
      artistPicture: (artist) async => Uri.parse('https://fanart.test/${artist.musicBrainzId}.jpg'),
    );

    await downloads.addPlaylist(playlist, [
      const Song(
        id: 's9',
        title: 'Walk This Way',
        artists: [Artist(id: 'ar2', name: 'Run-DMC')],
      ),
    ]);
    await settled(downloads);
    expect(reachability.value, isTrue);
    expect(downloads.artist('ar2'), isNull);

    server.fanartReachable = true;
    downloads.retry();
    await settled(downloads);
    expect(downloads.artist('ar2')?.coverArt, 'fanart:mb2');
  });

  group('plays made out of reach', () {
    test('made at once are kept one after the other, all of them', () async {
      final pendingPlays = await PendingPlays.open(File('${directory.path}/plays.json'));
      final time = DateTime.utc(2026, 10, 10, 12);

      await Future.wait([pendingPlays.add('s1', time), pendingPlays.add('s2', time)]);
      expect([for (final play in (await PendingPlays.open(pendingPlays.file)).plays) play.songId], ['s1', 's2']);
    });

    test('are kept, and counted at the time they were made as the server is back', () async {
      final reachability = Reachability(() async {
        if (!server.reachable) {
          throw const SocketException('no route to host');
        }
      }, retry: const Duration(hours: 1));

      addTearDown(reachability.dispose);

      final downloads = await open(reachability: reachability);
      final pendingPlays = await PendingPlays.open(File('${directory.path}/plays.json'));
      final api = ServerWithDownloads(server.api, downloads, reachability, pendingPlays: pendingPlays);
      server.reachable = false;
      await reachability.check();

      final time = DateTime.utc(2026, 10, 10, 12);

      await api.scrobble('s1', time: time);
      expect(pendingPlays.plays.single.songId, 's1');
      expect((await PendingPlays.open(pendingPlays.file)).plays, hasLength(1), reason: 'kept on the device');

      server.reachable = true;
      await reachability.check();
      Future<bool> counted() async =>
          pendingPlays.plays.isEmpty && (await PendingPlays.open(pendingPlays.file)).plays.isEmpty;

      // Written on the device as each goes.
      for (var i = 0; i < 100 && !await counted(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final scrobble = server.urls.lastWhere((url) => url.path.endsWith('scrobble.view'));

      expect(scrobble.queryParameters['id'], 's1');
      expect(scrobble.queryParameters['time'], '${time.millisecondsSinceEpoch}');
      expect(pendingPlays.plays, isEmpty);
      expect((await PendingPlays.open(pendingPlays.file)).plays, isEmpty);
      api.close();
    });

    test('stop at a play that fails for the network, the rest kept; one the server refuses goes', () async {
      final pendingPlays = await PendingPlays.open(File('${directory.path}/plays.json'));

      await pendingPlays.add('s1', DateTime.utc(2026));
      await pendingPlays.add('gone', DateTime.utc(2026));
      await pendingPlays.add('s2', DateTime.utc(2026));
      await pendingPlays.add('s3', DateTime.utc(2026));

      final counted = <String>[];
      final failure = await pendingPlays.send((play) async {
        switch (play.songId) {
          case 'gone':
            throw const ServerError('no such song');
          case 's3':
            throw const SocketException('no route to host');
        }

        counted.add(play.songId);
      });

      expect(failure, isA<SocketException>());
      expect(counted, ['s1', 's2']);
      expect([for (final play in pendingPlays.plays) play.songId], ['s3']);
    });

    test('stop at a play the server fails at for now, as a proxy answers while it restarts: that one and the rest are '
        'kept', () async {
      final pendingPlays = await PendingPlays.open(File('${directory.path}/plays.json'));

      await pendingPlays.add('s1', DateTime.utc(2026));
      await pendingPlays.add('s2', DateTime.utc(2026));

      final failure = await pendingPlays.send(
        (_) => Future.error(const ServerError('music.test: HTTP 502', statusCode: 502)),
      );

      expect(failure, isA<ServerError>());
      expect([for (final play in pendingPlays.plays) play.songId], ['s1', 's2']);
      expect((await PendingPlays.open(pendingPlays.file)).plays, hasLength(2));
    });

    test('a server that fails at them for now, in reach all the same, has them again in a while', () async {
      final reachability = Reachability(() async {}, retry: const Duration(milliseconds: 50));

      addTearDown(reachability.dispose);
      await reachability.check();

      final downloads = await open(reachability: reachability);
      final pendingPlays = await PendingPlays.open(File('${directory.path}/plays.json'));

      await pendingPlays.add('s1', DateTime.utc(2026));
      server.failing.add('s1');

      final api = ServerWithDownloads(server.api, downloads, reachability, pendingPlays: pendingPlays);

      addTearDown(api.close);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(pendingPlays.plays, hasLength(1), reason: 'the server failing for now');
      server.failing.clear();

      Future<bool> counted() async =>
          pendingPlays.plays.isEmpty && (await PendingPlays.open(pendingPlays.file)).plays.isEmpty;

      // Written on the device as each goes.
      for (var i = 0; i < 100 && !await counted(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(await counted(), isTrue);
      expect(reachability.value, isTrue);
    });
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
      expect(
        await api.transcodedStreamUrl('s3', maxBitRate: 160, from: const Duration(seconds: 30)),
        isNotNull,
        reason: 'the server can, for a song not downloaded',
      );
      expect(api.streamUrl('s3').host, 'music.test');
      expect(api.coverArtUrl('al1', size: 300), downloads.coverFile('al1')!.uri);
      expect(utf8.decode(await api.coverArt('al1')), 'image of al1');
      expect(api.coverArtUrl('al9').host, 'music.test');
    });

    test('out of reach, the albums, playlists, artists and genres are the downloaded ones', () async {
      server.reachable = false;
      await reachability.check();

      final asked = server.requests.length;

      expect((await api.artist('ar1')).$1.coverArt, 'ar-ar1', reason: 'with their picture');
      expect((await api.albums(order: AlbumOrder.name)).map((album) => album.name), ['Toys in the Attic']);
      expect(await api.albums(order: AlbumOrder.mostPlayed), isEmpty);
      expect(await api.albums(order: AlbumOrder.recentlyPlayed), isEmpty, reason: 'nor when');
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
      expect(await api.similarSongs(songs.first), isEmpty, reason: 'autoplay goes quietly without');
      await expectLater(
        api.radioSongs('al1'),
        throwsA(ServerWithDownloads.unreachable),
        reason: 'a radio says why it doesn\'t play',
      );
      expect(server.requests.skip(asked), isEmpty, reason: 'the server not asked');
    });

    test('out of reach, a mix\'s songs are those of the downloaded albums of its genre and its years', () async {
      server.reachable = false;
      await reachability.check();
      Future<Set<String>> ids({String? genre, ({int from, int to})? years}) async => {
        for (final song in await api.randomSongs(genre: genre, years: years)) song.id,
      };

      expect(await ids(), {'s1', 's2'}, reason: 'not again for the playlist');
      expect(await ids(genre: 'Rock', years: (from: 1970, to: 1979)), {'s1', 's2'});
      expect(await ids(genre: 'Jazz'), isEmpty);
      expect(await ids(years: (from: 1980, to: 1989)), isEmpty);
      expect(await api.randomSongs(size: 1), hasLength(1));
      expect(await api.mostPlayedDecades(), isEmpty);
    });

    test(
      'a request that fails for the network takes the downloads, and the server is out of reach from then',
      () async {
        server.reachable = false;
        expect((await api.playlists()).single.name, 'Road trip');
        expect(reachability.value, isFalse);
      },
    );

    test('as the app opens, a request waits for the first ping to answer: out of reach, it takes the downloads, the '
        'server not asked', () async {
      final ping = Completer<void>();
      final opening = Reachability(() => ping.future, retry: const Duration(hours: 1));

      addTearDown(opening.dispose);

      final api = ServerWithDownloads(server.api, downloads, opening);

      unawaited(opening.check());

      final asked = server.requests.length;
      final playlists = api.playlists();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(server.requests, hasLength(asked));

      ping.completeError(const SocketException('no route to host'));
      expect((await playlists).single.name, 'Road trip');
      expect(server.requests, hasLength(asked));
    });

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
