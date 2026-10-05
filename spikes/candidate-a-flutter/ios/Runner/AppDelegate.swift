// G1 candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
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
    // registers the g1_native adapter (common native module) together with maplibre_gl
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
