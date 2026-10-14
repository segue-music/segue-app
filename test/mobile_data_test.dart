import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/mobile_data.dart';

void main() {
  test('on mobile data only when it is the one connection, as the system sends through Wi-Fi or a cable first', () {
    expect(MobileData.inUse([ConnectivityResult.mobile]), isTrue);
    expect(MobileData.inUse([ConnectivityResult.mobile, ConnectivityResult.vpn]), isTrue, reason: 'a VPN over it');
    expect(MobileData.inUse([ConnectivityResult.wifi]), isFalse);
    expect(MobileData.inUse([ConnectivityResult.wifi, ConnectivityResult.mobile]), isFalse);
    expect(MobileData.inUse([ConnectivityResult.ethernet, ConnectivityResult.mobile]), isFalse);
    expect(MobileData.inUse([ConnectivityResult.none]), isFalse);
    expect(MobileData.inUse(const []), isFalse);
  });

  test('where the system can\'t say, it is no mobile data: with no binding (as the hub\'s tests start the services), '
      'or with no plugin', () async {
    for (final binding in [false, true]) {
      if (binding) {
        TestWidgetsFlutterBinding.ensureInitialized();
      }

      final mobileData = await MobileData.watch(askSystem: true);

      await Future<void>.delayed(const Duration(milliseconds: 100)); // for an error that would come later
      expect(mobileData.value, isFalse);
      mobileData.dispose();
    }
  });

  test('a computer isn\'t asked, and has no mobile data', () async {
    final mobileData = await MobileData.watch();

    addTearDown(mobileData.dispose);
    expect(mobileData.value, isFalse);
  });
}
