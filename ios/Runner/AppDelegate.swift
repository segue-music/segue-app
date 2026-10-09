import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // What the app asks of iOS itself (lib/device.dart).
    let device = FlutterMethodChannel(
      name: "segue/device", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    device.setMethodCallHandler { call, result in
      switch call.method {
      // The name in Settings > General > About. Since iOS 16, only with Apple's
      // user-assigned-device-name entitlement; without it, iOS says "iPhone" or "iPad".
      case "deviceName": result(UIDevice.current.name)
      case "hasMobileData": result(self.hasMobileData())
      // While the app is in front, the screen stays on (lib/device.dart's KeepScreenOn).
      case "keepScreenOn":
        UIApplication.shared.isIdleTimerDisabled = call.arguments as? Bool ?? false
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  /// An iPhone always has a mobile network; an iPad, only the model with a SIM, which has its
  /// network interface (pdp_ip0) whether or not a SIM is in.
  private func hasMobileData() -> Bool {
    if UIDevice.current.userInterfaceIdiom == .phone {
      return true
    }

    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0, let first = interfaces else {
      return false
    }

    defer { freeifaddrs(interfaces) }
    return sequence(first: first, next: { $0.pointee.ifa_next }).contains {
      String(cString: $0.pointee.ifa_name).hasPrefix("pdp_ip")
    }
  }
}
