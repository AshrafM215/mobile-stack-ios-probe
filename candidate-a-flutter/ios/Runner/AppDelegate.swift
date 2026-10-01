// G1 candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import ARKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("G1_PROBE app=candidate-a-flutter platform=ios event=launch")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "G1ArProbe") else {
      return
    }
    let channel = FlutterMethodChannel(name: "com.example.g1bench/ar", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        let supported = ARWorldTrackingConfiguration.isSupported
        NSLog("G1_PROBE app=candidate-a-flutter platform=ios event=native_ar_check supported=%d", supported ? 1 : 0)
        result(supported)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
