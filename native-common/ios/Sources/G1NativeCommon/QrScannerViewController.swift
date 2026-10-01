// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
#if canImport(UIKit) && canImport(AVFoundation) && canImport(CoreImage)
import AVFoundation
import CoreImage
import UIKit

/// Common camera QR scanner (AVFoundation frames + the common Core Image decoder). Camera permission is requested here, only
/// when the user enters QR. Results: a decoded payload, or PERMISSION_DENIED / CAMERA_UNAVAILABLE / CANCELLED. The payload is
/// validated by the caller through G1Native.validateQr; nothing is opened or navigated here.
public final class QrScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let requestId: String
    private let completion: (String?, String?) -> Void
    private var delivered = false
    private let session = AVCaptureSession()
    private let frames = DispatchQueue(label: "g1-qr-frames")
    private var preview: AVCaptureVideoPreviewLayer?

    public init(requestId: String, completion: @escaping (String?, String?) -> Void) {
        self.requestId = requestId
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let cancel = UIButton(type: .system)
        cancel.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
        cancel.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancel.titleLabel?.adjustsFontForContentSizeCategory = true
        cancel.accessibilityIdentifier = "qr.cancel"
        cancel.addTarget(self, action: #selector(onCancel), for: .touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(onBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard AVCaptureDevice.default(for: .video) != nil else { finish(nil, "CAMERA_UNAVAILABLE"); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.startCamera() : self.finish(nil, "PERMISSION_DENIED") }
            }
        default: finish(nil, "PERMISSION_DENIED")
        }
    }

    private func startCamera() {
        guard !delivered, let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else {
            finish(nil, "CAMERA_UNAVAILABLE")
            return
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frames)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            finish(nil, "CAMERA_UNAVAILABLE")
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        preview = layer
        frames.async { self.session.startRunning() }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer), let text = QrDecode.decode(CIImage(cvPixelBuffer: pixels)) else { return }
        DispatchQueue.main.async { self.finish(text, nil) }
    }

    @objc private func onCancel() { finish(nil, "CANCELLED") }

    /// No camera use in the background (PRM05): leaving the scanner ends it.
    @objc private func onBackground() { finish(nil, "CANCELLED") }

    private func finish(_ payload: String?, _ error: String?) {
        if delivered { return }
        delivered = true
        NotificationCenter.default.removeObserver(self)
        frames.async { if self.session.isRunning { self.session.stopRunning() } }
        let done = completion
        if presentingViewController != nil {
            dismiss(animated: false) { done(payload, error) }
        } else {
            done(payload, error)
        }
    }
}
#endif
