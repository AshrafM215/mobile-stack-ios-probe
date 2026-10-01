// G1 candidate C (native iOS reference) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import CoreLocation
import MapLibre
import SwiftUI

/// MapLibre Native iOS view showing the bundled synthetic style (no network sources).
struct SyntheticMapView: UIViewRepresentable {
    @Binding var status: String

    func makeCoordinator() -> Coordinator {
        Coordinator(status: $status)
    }

    func makeUIView(context: Context) -> MLNMapView {
        guard let url = Bundle.main.url(forResource: "probe-style-v0", withExtension: "json") else {
            fatalError("synthetic style missing from the bundle")
        }
        let map = MLNMapView(frame: .zero, styleURL: url)
        map.delegate = context.coordinator
        map.setCenter(CLLocationCoordinate2D(latitude: 0.0003, longitude: 0.0007), zoomLevel: 16, animated: false)
        return map
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private let status: Binding<String>

        init(status: Binding<String>) {
            self.status = status
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            status.wrappedValue = "style loaded (\(style.layers.count) layers)"
            G1Probe.mark("style_loaded", "layers=\(style.layers.count)")
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            status.wrappedValue = "style failed"
            G1Probe.mark("style_failed")
        }
    }
}
