import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where [place] is on a map, found by its name ("Boston, Estados Unidos"), on [platform]: on Android, in the maps app
/// the user picks (a geo URI); on iOS and macOS, in Apple Maps; elsewhere, OpenStreetMap's search, in the browser.
Uri mapUrl(String place, TargetPlatform platform) => switch (platform) {
  TargetPlatform.android => Uri(scheme: 'geo', path: '0,0', queryParameters: {'q': place}),
  TargetPlatform.iOS || TargetPlatform.macOS => Uri.https('maps.apple.com', '/', {'q': place}),
  TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.fuchsia => _openStreetMap(place),
};

/// OpenStreetMap's search for [place].
Uri _openStreetMap(String place) => Uri.https('www.openstreetmap.org', '/search', {'query': place});

/// Opens [place] on a map ([mapUrl]), out of the app: on an Android without a maps app, OpenStreetMap's, in the browser.
/// Nothing where neither opens.
Future<void> showOnMap(String place, {required TargetPlatform platform}) async {
  try {
    if (await launchUrl(mapUrl(place, platform), mode: LaunchMode.externalApplication) ||
        platform != TargetPlatform.android) {
      return;
    }

    await launchUrl(_openStreetMap(place), mode: LaunchMode.externalApplication);
  } on Object {
    // Nothing to open it with.
  }
}
