// G1 candidate C (native iOS reference) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import SwiftUI

struct ContentView: View {
    @State private var mapStatus = "loading"
    @State private var arStatus = "not checked"

    var body: some View {
        VStack(spacing: 12) {
            Text("G1 Candidate C - synthetic probe")
                .font(.headline)
                .accessibilityIdentifier("title")
            SyntheticMapView(status: $mapStatus)
                .frame(maxWidth: .infinity, minHeight: 320)
                .accessibilityLabel("Synthetic map")
            Text("Map: \(mapStatus)")
                .accessibilityIdentifier("mapStatus")
            Button("Check AR") {
                arStatus = ARFeasibility.describe()
            }
            .accessibilityIdentifier("checkAR")
            Text("AR: \(arStatus)")
                .accessibilityIdentifier("arStatus")
        }
        .padding()
    }
}
