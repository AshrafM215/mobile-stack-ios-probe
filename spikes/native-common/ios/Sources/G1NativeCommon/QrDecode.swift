// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
#if canImport(CoreImage) && canImport(ImageIO)
import CoreImage
import Foundation
import ImageIO

/// The one common decoder path on iOS (Core Image QR detector) for injected images and camera frames; no network, no
/// telemetry. Android uses ZXing core 3.5.4 for the same two paths.
public enum QrDecode {
    private static let lock = NSLock()
    private static let detector: CIDetector? = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                                                          options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

    /// Decodes one frame; returns the payload text or nil when no QR code is found.
    public static func decode(_ image: CIImage) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let features = detector?.features(in: image) else { return nil }
        for f in features {
            if let q = f as? CIQRCodeFeature, let text = q.messageString { return text }
        }
        return nil
    }

    /// Injected synthetic PNG (B11 INJ.* cases, SIMULATED provenance; never an optical scan). Bounded before decoding.
    public static func decodePng(_ data: Data) -> String? {
        guard data.count <= 4 * 1024 * 1024, let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              w > 0, h > 0, w <= 4096, h <= 4096,
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return decode(CIImage(cgImage: cg))
    }
}
#endif
