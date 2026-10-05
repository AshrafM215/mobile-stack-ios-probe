// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-LAYOUT-1.0 of G1-CIC-1.0: the layout mode of the home screen from the app window and the text scale (pure
// functions; the constants and the vectors of the contract are pinned by the unit tests).
import Foundation

enum LayoutMode: String {
    case regular
    case compact
}

enum LayoutPolicy {
    static let minWidth = 360.0
    static let minHeight = 600.0
    static let compactMapMaxHeight = 240.0
    static let compactMapMaxWindowFraction = 0.5

    /// width and height: the app window inside the safe area in points; fontScale: the text scale factor.
    static func mode(width: Double, height: Double, fontScale: Double) -> LayoutMode {
        width / fontScale >= minWidth && height / fontScale >= minHeight ? .regular : .compact
    }

    /// Height of the map in the compact mode for a window of windowHeight.
    static func compactMapHeight(windowHeight: Double) -> Double {
        min(compactMapMaxHeight, windowHeight * compactMapMaxWindowFraction)
    }
}
