// G1 candidate C (native iOS: Swift + SwiftUI) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Synthetic wayfinding benchmark app (G1-CIC-1.0). Not a product; synthetic data only; not for navigation.
import G1NativeCommon
import SwiftUI

/// Process-wide app objects (one scene; the state outlives view updates).
final class AppModel {
    static let shared = AppModel()
    let state: AppState
    let map: MapController
    let lab: LabController
    private var started = false

    private init() {
        G1Native.initialize(appId: "C")
        func strings(_ lang: String) -> Strings {
            guard let url = Bundle.main.url(forResource: lang, withExtension: "json", subdirectory: "strings") ??
                    Bundle.main.url(forResource: lang, withExtension: "json"),
                  let text = try? String(contentsOf: url, encoding: .utf8), let s = try? Strings.parse(lang, text) else {
                fatalError("strings missing: \(lang)")
            }
            return s
        }
        state = AppState(strings: ["ar": strings("ar"), "en": strings("en")])
        map = MapController(state: state)
        state.map = map
        lab = LabController(state: state)
    }

    @MainActor
    func start() async {
        if started { return }
        started = true
        let launch = LabCommand.fromLaunchArguments()
        await state.boot()
        await lab.start(launch)
    }
}

@main
struct G1CandidateCApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var previousPhase: ScenePhase?
    private let model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView(state: model.state, map: model.map)
                .task { await model.start() }
                .onOpenURL { url in
                    // lab hook transport for a running app: g1bench-c://cmd?name=<cmd>&args=<json>
                    if url.scheme == "g1bench-c", let c = LabCommand.fromURL(url) { model.lab.enqueue(c.name, c.argsJson) }
                }
        }
        .onChange(of: phase) { next in
            if next == .active, let prev = previousPhase, prev != .active { model.state.onResumed() }
            previousPhase = next
        }
    }
}
