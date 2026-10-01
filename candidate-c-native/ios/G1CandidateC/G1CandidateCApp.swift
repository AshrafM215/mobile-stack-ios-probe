// G1 candidate C (native iOS reference) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation
import SwiftUI

@main
struct G1CandidateCApp: App {
    init() {
        G1Probe.mark("launch")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Synthetic unified-log markers for feasibility evidence; no personal or device data.
enum G1Probe {
    static func mark(_ event: String, _ detail: String = "") {
        NSLog("G1_PROBE app=candidate-c-native platform=ios event=%@ %@", event, detail)
    }
}
