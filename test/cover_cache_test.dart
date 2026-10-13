import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:segue/connect/connect.dart';
import 'package:segue/pictures/cover_cache.dart';
import 'package:segue/player/player.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/widgets/cover.dart';

import 'fakes.dart';

const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');

/// An image, [width] pixels wide, as PNG.
Uint8List png({int width = 2}) => Uint8List.fromList(img.encodePng(img.Image(width: width, height: 2)));

/// A media server whose covers are images [width] pixels wide; [asked] gets the ids of the covers asked for.
SubsonicApi coverServer(List<String> asked, {int width = 2}) => SubsonicApi(
  Uri.parse('https://music.test'),
  credentials,
  client: MockClient((request) async {
    if (!request.url.path.endsWith('getCoverArt.view')) {
      return http.Response('', 404);
    }

    asked.add(request.url.queryParameters['id']!);

    return http.Response.bytes(png(width: width), 200, headers: {'content-type': 'image/png'});
  }),
);

/// Loads [image], as a widget showing it would: from memory no more, as the app opens again.
Future<ImageInfo> load(ImageProvider image) async {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  final loaded = Completer<ImageInfo>();
  image
      .resolve(ImageConfiguration.empty)
      .addListener(
        ImageStreamListener((info, _) => loaded.complete(info), onError: (error, _) => loaded.completeError(error)),
      );

  return loaded.future;
}

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('segue-covers'));
  tearDown(() => directory.deleteSync(recursive: true));

  /// The files kept, once there is one and none is being written, or else [until] holds.
  Future<List<File>> kept({bool Function(List<File> files)? until}) async {
    List<File> files() => directory.listSync().whereType<File>().toList();

    for (var i = 0; i < 100; i++) {
      final kept = files();

      if (kept.isNotEmpty && !kept.any((file) => file.path.endsWith('.part')) && (until?.call(kept) ?? true)) {
        break;
      }

      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    return files();
  }

  testWidgets('a cover comes from the server once, then from its file, as the app opens again too', (tester) async {
    await tester.runAsync(() async {
      final asked = <String>[];
      final server = coverServer(asked);
      expect((await load(CoverCache(directory).cover(server, 'al1', size: 300))).image.width, 2);
      expect(asked, ['al1']);
      expect(await kept(), hasLength(1));

      expect((await load(CoverCache(directory).cover(server, 'al1', size: 300))).image.width, 2);
      expect(asked, ['al1'], reason: 'from its file');

      await load(CoverCache(directory).cover(server, 'al1', size: 600));
      expect(asked, ['al1', 'al1'], reason: 'of another size');
      expect(await kept(until: (files) => files.length == 2), hasLength(2));
    });
  });

  testWidgets('a cover kept for long shows, and comes again for the next time', (tester) async {
    await tester.runAsync(() async {
      final asked = <String>[];
      await load(CoverCache(directory).cover(coverServer(asked), 'al1', size: 300));
      final file = (await kept()).single;
      file.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 31)));

      final info = await load(CoverCache(directory).cover(coverServer(asked, width: 4), 'al1', size: 300));
      expect(info.image.width, 2, reason: 'the one kept');
      await kept(
        until: (files) => files.single.lastModifiedSync().isAfter(DateTime.now().subtract(const Duration(days: 1))),
      );
      expect(asked, ['al1', 'al1']);

      expect((await load(CoverCache(directory).cover(coverServer(asked), 'al1', size: 300))).image.width, 4);
    });
  });

  testWidgets('a kept cover that isn\'t an image comes from the server again', (tester) async {
    await tester.runAsync(() async {
      final asked = <String>[];
      await load(CoverCache(directory).cover(coverServer(asked), 'al1', size: 300));
      (await kept()).single.writeAsStringSync('not an image');

      expect((await load(CoverCache(directory).cover(coverServer(asked), 'al1', size: 300))).image.width, 2);
      expect(asked, ['al1', 'al1']);
      await kept(until: (files) => files.single.lengthSync() == png().length);
    });
  });

  testWidgets('a picture from elsewhere is kept too', (tester) async {
    await tester.runAsync(() async {
      var asked = 0;
      final client = MockClient((request) async {
        asked++;

        return http.Response.bytes(png(), 200, headers: {'content-type': 'image/jpeg'});
      });
      final url = Uri.parse('https://fanart.test/r1.jpg');
      await load(CoverCache(directory, client: client).picture(url));
      await kept();
      await load(CoverCache(directory, client: client).picture(url));
      expect(asked, 1);
    });
  });

  test('trimmed, the oldest files go past the room they may take, and the parts of writes cut short', () async {
    final now = DateTime.now();

    for (final (i, name) in ['old', 'older', 'new'].indexed) {
      File('${directory.path}/$name')
        ..writeAsBytesSync(Uint8List(100))
        ..setLastModifiedSync(now.subtract(Duration(days: [10, 20, 1][i])));
    }

    File('${directory.path}/new.0.part').writeAsBytesSync(Uint8List(10));
    await CoverCache(directory, maxBytes: 250).trim();
    expect([for (final file in directory.listSync()) file.uri.pathSegments.last]..sort(), ['new', 'old']);
  });

  testWidgets('a cover shows as it is kept, where the session keeps them', (tester) async {
    final asked = <String>[];
    final api = coverServer(asked);
    final player = PlayerController(FakeEngine(), api);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
      covers: CoverCache(directory),
    );
    await tester.pumpWidget(
      ServicesScope(
        services: services,
        child: const Directionality(textDirection: TextDirection.ltr, child: Cover('al1')),
      ),
    );
    expect(tester.widget<Image>(find.byType(Image)).image, isNot(isA<NetworkImage>()));
  });
}
