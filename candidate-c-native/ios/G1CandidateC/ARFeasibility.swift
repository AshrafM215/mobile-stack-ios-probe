// G1 candidate C (native iOS reference) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import ARKit

/// ARKit integration feasibility: capability check, safe fallback and a linked native AR view.
enum ARFeasibility {
    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    static func describe() -> String {
        let supported = isSupported
        G1Probe.mark("ar_check", "supported=\(supported)")
        return supported ? "supported" : "unsupported (safe 2D/text fallback)"
    }

    /// Compile/link proof for the native AR scene view; it is never presented on the simulator.
    static func makeSceneView() -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = true
        return view
    }
}
