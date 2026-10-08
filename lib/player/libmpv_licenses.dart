import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Each library media_kit brings with libmpv, by its name, and its files in assets/licenses: its notice, then the texts
/// of its licenses.
const _libraries = [
  ('mpv', ['mpv.txt', 'LGPL-2.1.txt']),
  ('FFmpeg', ['ffmpeg.txt', 'LGPL-2.1.txt', 'LGPL-3.0.txt', 'GPL-3.0.txt']),
  ('Mbed TLS', ['mbedtls.txt', 'Apache-2.0.txt']),
];

/// Adds to the licenses Flutter gathers ([LicenseRegistry], which the licenses' page lists) those of libmpv and what it
/// is built with, which media_kit brings into the app on Android, iOS, macOS and Windows: native libraries, not Dart
/// packages, so Flutter misses them. On Linux the app plays with the system's libmpv, which it doesn't bring.
void addLibmpvLicenses() {
  if (defaultTargetPlatform == TargetPlatform.linux) {
    return;
  }

  LicenseRegistry.addLicense(() async* {
    for (final (library, files) in _libraries) {
      final texts = [for (final file in files) await rootBundle.loadString('assets/licenses/$file')];
      yield LicenseEntryWithLineBreaks([library], texts.join('\n'));
    }
  });
}
