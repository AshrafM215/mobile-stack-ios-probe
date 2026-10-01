// G1 candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Flutter
import g1_native
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// Lab command URLs (g1bench-a://cmd?name=...&args=...) for a running app go to the common module adapter.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      G1NativePlugin.handle(url: context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
