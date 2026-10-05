// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The home map through MapLibre Native iOS (MLNMapView hosted in SwiftUI), following G1-STYLE-1.0 and the map policy.
import CoreLocation
import Foundation
import MapLibre
import QuartzCore
import SwiftUI

final class MapController: NSObject, MapPort, MLNMapViewDelegate {
    private let state: AppState
    let view: MLNMapView
    private var style: MLNStyle?
    private var generation = 0
    private var cameraSet = false
    private var built: (gen: Int, floor: Int, lang: String) = (-1, 1, "ar")

    /// An empty local style until the verified bundle is loaded (the binding's default style would use the network).
    private static let placeholderStyle: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("g1-style-empty.json")
        try? Data(#"{"version":8,"sources":{},"layers":[]}"#.utf8).write(to: url, options: .atomic)
        return url
    }()

    init(state: AppState) {
        self.state = state
        view = MLNMapView(frame: .zero, styleURL: MapController.placeholderStyle)
        super.init()
        view.delegate = self
        view.allowsRotating = false
        view.allowsTilting = false
        view.compassView.isHidden = true
    }

    /// Loads the style of the active bundle for the current floor and language (initial load and after a bundle change).
    func reload() {
        guard let d = state.data else { return }
        generation += 1
        built = (generation, state.floor, state.lang)
        style = nil
        guard let json = try? buildStyle(d.styleJson, bundleDir: d.dir, floor: built.floor, lang: built.lang) else { return }
        // the built style is written next to the app's caches and loaded by file URL (it addresses the bundle by file URLs)
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("g1-style-\(generation).json")
        guard (try? Data(json.utf8).write(to: url, options: .atomic)) != nil else { return }
        if !cameraSet, let o = (try? JSON.decode(d.styleJson)) as? [String: Any], let c = o["center"] as? [NSNumber], c.count == 2,
           let z = o["zoom"] as? NSNumber {
            view.setCenter(CLLocationCoordinate2D(latitude: c[1].doubleValue, longitude: c[0].doubleValue), zoomLevel: z.doubleValue, animated: false)
            cameraSet = true
        }
        view.styleURL = url
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        guard built.gen == generation else { return }
        self.style = style
        state.onStyleLoaded()
        // the style was built for the floor and language current at build time; re-apply in case they changed meanwhile
        if state.floor != built.floor { setFloor(state.floor) }
        if state.lang != built.lang { setLanguage(state.lang) }
        setRoute(state.routeFc)
    }

    func setFloor(_ floor: Int) {
        guard let style, let d = state.data, let filters = try? floorFilters(d.styleJson, floor) else { return }
        for (id, filter) in filters {
            (style.layer(withIdentifier: id) as? MLNVectorStyleLayer)?.predicate = NSPredicate(mglJSONObject: filter)
        }
    }

    func setLanguage(_ lang: String) {
        (style?.layer(withIdentifier: "room-labels") as? MLNSymbolStyleLayer)?.text = NSExpression(mglJSONObject: textField(lang))
    }

    func setRoute(_ featureCollection: String) {
        guard let source = style?.source(withIdentifier: "route") as? MLNShapeSource else { return }
        source.shape = try? MLNShape(data: Data(featureCollection.utf8), encoding: String.Encoding.utf8.rawValue)
    }

    func easeTo(lon: Double, lat: Double, zoom: Double, durationMs: Int) {
        let altitude = MLNAltitudeForZoomLevel(zoom, 0, lat, view.bounds.size)
        let camera = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: altitude, pitch: 0, heading: 0)
        view.setCamera(camera, withDuration: Double(durationMs) / 1000, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
    }
}

/// Hosts the controller's MLNMapView (created once and kept for the whole process).
struct MapPanel: UIViewRepresentable {
    let controller: MapController

    func makeUIView(context: Context) -> MLNMapView { controller.view }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}
}

/// Reports every SwiftUI update of the root (the bench frame waiters resolve at the next CADisplayLink frame).
struct CommitProbe: UIViewRepresentable {
    let state: AppState
    let revision: Int

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { state.onCommit() }
}
