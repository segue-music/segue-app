import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/pictures/fanart_tv.dart';
import 'package:segue/server/models.dart';

const aerosmith = Artist(id: 'ar1', name: 'Aerosmith', musicBrainzId: 'mb1');

/// A thumb of fanart.tv's, as it lists them: its likes in a string.
Map<String, Object?> thumb(String name, int likes) => {
  'id': name,
  'url': 'https://assets.fanart.tv/fanart/$name.jpg',
  'likes': '$likes',
};

/// fanart.tv, answering each request with [answer]; [asked] gets every request.
FanartTv fanartTv(http.Response Function() answer, {List<http.Request>? asked}) => FanartTv(
  apiKey: 'key',
  client: MockClient((request) async {
    asked?.add(request);

    return answer();
  }),
);

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('an artist\'s pictures are fanart.tv\'s thumbs of them, by their MusicBrainz id, the most liked first, over '
      'HTTPS', () async {
    final asked = <http.Request>[];
    final fanart = fanartTv(
      () => json({
        'name': 'Aerosmith',
        'mbid_id': 'mb1',
        'artistbackground': [thumb('wide', 9)],
        'artistthumb': [
          thumb('liked', 6),
          thumb('new', 0),
          thumb('loved', 8),
          {'id': 'old', 'url': 'http://assets.fanart.tv/fanart/music/mb1/artistthumb/old.jpg', 'likes': '6'},
        ],
      }),
      asked: asked,
    );

    expect(await fanart.artistPictures(aerosmith), [
      Uri.parse('https://assets.fanart.tv/fanart/loved.jpg'),
      Uri.parse('https://assets.fanart.tv/fanart/liked.jpg'),
      Uri.parse('https://assets.fanart.tv/fanart/music/mb1/artistthumb/old.jpg'),
      Uri.parse('https://assets.fanart.tv/fanart/new.jpg'),
    ]);
    final request = asked.single;
    expect(request.url.host, 'webservice.fanart.tv');
    expect(request.url.path, '/v3/music/mb1');
    expect(request.url.queryParameters['api_key'], 'key');
    expect(request.headers['User-Agent'], startsWith('Segue/'));

    // Remembered for the session.
    await fanart.artistPictures(aerosmith);
    expect(asked, hasLength(1));
  });

  test('none for an artist without a MusicBrainz id, asking nothing, nor for one fanart.tv has nothing of', () async {
    final asked = <http.Request>[];

    for (final answer in [
      json({}),
      json({'name': 'Aerosmith'}),
      json({'error': 'not found'}, 404),
    ]) {
      expect(await fanartTv(() => answer, asked: asked).artistPictures(aerosmith), isEmpty, reason: answer.body);
    }

    asked.clear();
    final unknown = fanartTv(
      () => json({
        'artistthumb': [thumb('liked', 1)],
      }),
      asked: asked,
    );
    expect(await unknown.artistPictures(const Artist(id: 'ar2', name: 'Cheap Trick')), isEmpty);
    expect(asked, isEmpty);
  });

  test('the pictures it has found come at once: none for an artist without a MusicBrainz id, and nothing before they '
      'have come, nor where they failed to', () async {
    var fails = true;
    final fanart = fanartTv(
      () => fails
          ? json({'error': 'invalid API key'}, 401)
          : json({
              'artistthumb': [thumb('liked', 1)],
            }),
    );
    expect(fanart.foundPictures(const Artist(id: 'ar2', name: 'Cheap Trick')), isEmpty);
    expect(fanart.foundPictures(aerosmith), isNull);

    await fanart.artistPictures(aerosmith);
    expect(fanart.foundPictures(aerosmith), isNull, reason: 'it failed');

    fails = false;
    final pictures = fanart.artistPictures(aerosmith);
    expect(fanart.foundPictures(aerosmith), isNull, reason: 'not yet');
    await pictures;
    expect(fanart.foundPictures(aerosmith), [Uri.parse('https://assets.fanart.tv/fanart/liked.jpg')]);
  });

  test('none when it fails, asked again the next time', () async {
    var fails = true;
    final asked = <http.Request>[];
    final fanart = fanartTv(
      () => fails
          ? json({'error': 'invalid API key'}, 401)
          : json({
              'artistthumb': [thumb('liked', 1)],
            }),
      asked: asked,
    );

    expect(await fanart.artistPictures(aerosmith), isEmpty);
    fails = false;
    expect(await fanart.artistPictures(aerosmith), [Uri.parse('https://assets.fanart.tv/fanart/liked.jpg')]);
    expect(asked, hasLength(2));
  });
}
