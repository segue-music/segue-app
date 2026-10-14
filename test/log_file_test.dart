import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:segue/jellyfin/api.dart';
import 'package:segue/log_file.dart';
import 'package:segue/segue/protocol.dart';
import 'package:segue/subsonic/api.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('segue-log'));
  tearDown(() => directory.deleteSync(recursive: true));

  List<String> linesOf(String name) => File('${directory.path}/$name').readAsLinesSync();

  // A record's time ([logTime]).
  const time = r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}[+-]\d\d:\d\d';

  test('a record is a line, at its time and level, with its error, then its stack trace', () async {
    final log = await LogFile.open(directory);

    log
      ..write(LogRecord(Level.WARNING, 'downloads unavailable', 'Downloads', Exception('no room')))
      ..write(LogRecord(Level.SEVERE, 'uncaught', 'uncaught', StateError('no song'), StackTrace.fromString('#0 main')));
    await log.close();

    expect(linesOf('segue.log'), [
      matches('^$time WARNING Downloads: downloads unavailable: Exception: no room\$'),
      matches('^$time SEVERE uncaught: uncaught: Bad state: no song\$'),
      '#0 main',
    ]);
  });

  test('a record\'s time is to the millisecond, with its offset from UTC', () {
    expect(logTime(DateTime.utc(2026, 10, 14, 12, 9, 48, 789, 831)), '2026-10-14T12:09:48.789+00:00');
    expect(logTime(DateTime.utc(2026, 1, 2, 3, 4, 5, 6)), '2026-01-02T03:04:05.006+00:00');

    final now = DateTime.now();
    final offset = now.timeZoneOffset;

    expect(
      logTime(now),
      endsWith(
        '${offset.isNegative ? '-' : '+'}${'${offset.inHours.abs()}'.padLeft(2, '0')}:'
        '${'${offset.inMinutes.abs() % 60}'.padLeft(2, '0')}',
      ),
    );
  });

  test('a log opened again goes on after what it had', () async {
    for (final message in ['the first launch', 'the next']) {
      final log = await LogFile.open(directory);

      log.write(LogRecord(Level.INFO, message, 'Segue'));
      await log.close();
    }

    expect(linesOf('segue.log'), [endsWith('Segue: the first launch'), endsWith('Segue: the next')]);
  });

  test('past its limit, the file makes way for a new one, and the one before it goes', () async {
    final log = await LogFile.open(directory, limit: 200);

    // Some 60 bytes each: three to a file.
    for (var i = 0; i < 10; i++) {
      log.write(LogRecord(Level.INFO, 'line $i of the log', 'Segue'));
    }

    await log.close();

    expect(linesOf('segue.log'), [endsWith('line 9 of the log')]);
    expect(linesOf('segue.1.log'), [
      endsWith('line 6 of the log'),
      endsWith('line 7 of the log'),
      endsWith('line 8 of the log'),
    ]);
    expect(directory.listSync(), hasLength(2));
  });

  test('read, the log is the file before, then the one now', () async {
    final log = await LogFile.open(directory, limit: 200);

    expect(utf8.decode(await log.read()), isEmpty);

    for (var i = 0; i < 4; i++) {
      log.write(LogRecord(Level.INFO, 'line $i of the log', 'Segue'));
    }

    expect(utf8.decode(await log.read()).split('\n'), [for (var i = 0; i < 4; i++) endsWith('line $i of the log'), '']);
    await log.close();
  });

  test('a record goes in the file as it comes, before the log closes', () async {
    final log = await LogFile.open(directory);

    log.write(LogRecord(Level.INFO, 'started', 'Segue'));

    expect(linesOf('segue.log'), [endsWith('Segue: started')]);
    await log.close();
  });

  test('no credential reaches the log', () {
    final subsonic = SubsonicApi(
      Uri.parse('https://music.example'),
      const SubsonicToken(username: 'me', token: 'a1b2c3', salt: 'd4e5f6'),
    );
    final subsonicKey = SubsonicApi(
      Uri.parse('https://music.example'),
      const SubsonicApiKey(username: 'me', apiKey: 'a1b2c3'),
    );
    final jellyfin = JellyfinApi(
      Uri.parse('https://music.example'),
      const JellyfinCredentials(username: 'me', userId: 'u1', token: 'a1b2c3'),
      deviceId: 'd1',
      deviceName: 'laptop',
    );
    final quoted = [
      'Failed to open ${subsonic.streamUrl('1')}.',
      'ClientException: Connection refused, uri=${subsonic.coverArtUrl('al-1')}',
      subsonicKey.streamUrl('1', maxBitRate: 128).toString(),
      jellyfin.streamUrl('1').toString(),
      jellyfin.streamUrl('1', maxBitRate: 128).toString(),
      jsonEncode({'type': 'hello', 'auth': const Auth.subsonic(username: 'me', token: 'a1b2c3', salt: 'd4e5f6')}),
      jsonEncode({'Username': 'me', 'Pw': 'a1b2c3'}),
      jsonEncode({'AccessToken': 'a1b2c3', 'User': <String, Object?>{}}),
      'MediaBrowser Client="Segue", Device="laptop", DeviceId="d1", Version="1.0", Token="a1b2c3"',
    ];

    for (final text in quoted) {
      expect(
        redacted(text),
        allOf(isNot(contains('a1b2c3')), isNot(contains('d4e5f6')), contains('***')),
        reason: text,
      );
    }

    expect(
      redacted(subsonic.streamUrl('1').toString()),
      allOf(contains('id=1'), contains('u=me'), contains('t=***&s=***')),
    );
    expect(
      redacted('https://music.example/rest/search3.view?query=Pt&songCount=10&t=a'),
      'https://music.example/rest/search3.view?query=Pt&songCount=10&t=***',
    );
  });
}
