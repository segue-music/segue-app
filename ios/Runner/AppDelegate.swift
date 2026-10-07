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
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
