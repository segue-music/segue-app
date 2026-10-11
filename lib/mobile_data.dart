import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device is online through mobile data, which a data plan counts, rather than Wi-Fi or a cable: as the
/// system says (connectivity_plus), and as that changes. Only Android and iOS are asked, the systems with mobile data:
/// elsewhere, and where the system can't say, it isn't. On Linux connectivity_plus would ask NetworkManager, on the
/// system's D-Bus, which tool/flutter.sh's container hasn't got, and which it fails to reach with an error no caller
/// can catch.
class MobileData extends ValueNotifier<bool> {
  MobileData._() : super(false);

  StreamSubscription<List<ConnectivityResult>>? _changes;

  /// Asks the system now and, where it answers, follows what it says next. [askSystem] says whether to, which tests
  /// set; by default, on Android and iOS.
  static Future<MobileData> watch({@visibleForTesting bool? askSystem}) async {
    final mobileData = MobileData._();

    if (!(askSystem ?? (Platform.isAndroid || Platform.isIOS))) {
      return mobileData;
    }

    final connectivity = Connectivity();

    try {
      // Services.start waits for it, as the app opens.
      mobileData.value = inUse(await connectivity.checkConnectivity().timeout(const Duration(seconds: 2)));
    } on Object catch (e) {
      debugPrint('no news of the connection: $e');
      return mobileData;
    }

    mobileData._changes = connectivity.onConnectivityChanged.listen(
      (connections) => mobileData.value = inUse(connections),
      onError: (Object e) => debugPrint('no news of the connection: $e'),
    );

    return mobileData;
  }

  /// Whether the device is online through mobile data, when [connections] are the ones it is online through: mobile
  /// data alone, since with Wi-Fi or a cable too the system sends through those.
  @visibleForTesting
  static bool inUse(List<ConnectivityResult> connections) =>
      connections.contains(ConnectivityResult.mobile) &&
      !connections.contains(ConnectivityResult.wifi) &&
      !connections.contains(ConnectivityResult.ethernet);

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
