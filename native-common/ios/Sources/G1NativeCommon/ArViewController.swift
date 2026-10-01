// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
#if canImport(UIKit) && canImport(ARKit)
import ARKit
import SceneKit
import UIKit

/// ARKit capability check (common for A, B and C). The iOS Simulator has no world tracking: UNSUPPORTED.
public enum ArSupport {
    public static func availability() -> String { ARWorldTrackingConfiguration.isSupported ? "SUPPORTED" : "UNSUPPORTED" }

    /// Only a fully supported device opens the native AR screen; everything else uses the accessible text fallback.
    public static func canStart() -> Bool { availability() == "SUPPORTED" }
}

/// The one native full-screen AR screen used by every candidate on iOS (common-mode tracking and rendering).
/// Safety invariant: the guidance arrow is visible only while tracking is normal AND the pose is established AND the runtime
/// has granted guidance; any other state hides it at once on the main thread (AR-005). In G1 no spatial fixture exists, so a
/// real ARKit session never establishes a pose and never shows the arrow. Injected mode (lab hook ar.inject) replays a
/// state script without a camera and is labelled SIMULATED. Same policy as ArActivity.java on Android.
public final class ArViewController: UIViewController, ARSessionDelegate {
    private let requestId: String
    private let texts: [String: Any]
    private let script: [(String, Int)]?
    private let injected: Bool
    private let emit: (String) -> Void
    private var sceneView: ARSCNView?
    private let status = UILabel()
    private let arrow = UILabel()
    private var state = "INITIALIZING"
    private var poseEstablished = false
    private var guidanceAllowed = false
    private var finishedSent = false
    private var scriptStart = DispatchTime.now()
    private var displayLink: CADisplayLink?
    private var pendingLatency: (visible: Bool, signal: UInt64)?

    /// scriptJson: [[state, at_ms], ...] (injected SIMULATED mode, lab builds only); textsJson: localized strings.
    public init(requestId: String, scriptJson: String?, textsJson: String?, emit: @escaping (String) -> Void) {
        self.requestId = requestId
        self.emit = emit
        self.texts = (textsJson.flatMap { try? Json.parseObject(Data($0.utf8)) }) ?? [:]
        var parsed: [(String, Int)]?
        if BuildFlags.lab, let s = scriptJson, let arr = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [Any] {
            var steps: [(String, Int)] = []
            for item in arr {
                guard let pair = item as? [Any], pair.count == 2, let st = pair[0] as? String, let at = Json.number(pair[1]) else {
                    steps = []
                    break
                }
                steps.append((st, max(0, at.intValue)))
            }
            parsed = steps
        }
        self.script = parsed
        self.injected = parsed != nil
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func text(_ key: String, _ fallback: String) -> String { (texts[key] as? String) ?? fallback }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: 1)
        if !injected {
            let scene = ARSCNView(frame: view.bounds)
            scene.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scene.session.delegate = self
            view.addSubview(scene)
            sceneView = scene
        }
        status.accessibilityIdentifier = "ar.status"
        status.textColor = .white
        status.backgroundColor = UIColor(white: 0, alpha: 0.9)
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .title3)
        status.adjustsFontForContentSizeCategory = true
        status.accessibilityTraits.insert(.updatesFrequently)
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        arrow.accessibilityIdentifier = "ar.arrow"
        arrow.text = "\u{2191}"
        arrow.textColor = UIColor(red: 1, green: 214 / 255, blue: 0, alpha: 1)
        arrow.font = .systemFont(ofSize: 96, weight: .bold)
        arrow.accessibilityLabel = text("arrow", "Guidance arrow")
        arrow.isHidden = true
        arrow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arrow)
        let close = UIButton(type: .system)
        close.accessibilityIdentifier = "ar.close"
        close.setTitle(text("close", "Close AR"), for: .normal)
        close.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        close.titleLabel?.adjustsFontForContentSizeCategory = true
        close.backgroundColor = UIColor(white: 1, alpha: 0.9)
        close.layer.cornerRadius = 8
        close.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        close.addTarget(self, action: #selector(onClose), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arrow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            close.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            close.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            close.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            close.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(onBackground), name: UIApplication.willResignActiveNotification, object: nil)
        updateStatus()
        if injected {
            scriptStart = DispatchTime.now()
            for (st, at) in script ?? [] {
                DispatchQueue.main.asyncAfter(deadline: scriptStart + .milliseconds(at)) { [weak self] in
                    self?.onTrackingSignal(st, G1Trace.nowNanos(), st == "TRACKING")
                }
            }
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !injected, let scene = sceneView else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            emitEvent("error", [("reason", "session")])
            closeWith("unavailable")
            return
        }
        scene.session.run(ARWorldTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        onTrackingSignal("INITIALIZING", G1Trace.nowNanos(), false)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView?.session.pause()
    }

    /// Runtime grant/revoke of guidance (the runtime checks trust and route state); the arrow policy is re-evaluated at once.
    public func setGuidance(_ allowed: Bool) {
        DispatchQueue.main.async {
            self.guidanceAllowed = allowed
            self.applyArrow(G1Trace.nowNanos())
        }
    }

    // ARSessionDelegate (real ARKit mode only). No spatial fixture in G1: pose is never established from tracking alone.
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let next: String
        switch camera.trackingState {
        case .normal: next = "TRACKING"
        case .limited: next = "LIMITED"
        case .notAvailable: next = "LOST"
        }
        let t = G1Trace.nowNanos()
        DispatchQueue.main.async { self.onTrackingSignal(next, t, false) }
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.emitEvent("error", [("reason", "session")])
            self.closeWith("unavailable")
        }
    }

    private func onTrackingSignal(_ newState: String, _ signalNanos: UInt64, _ pose: Bool) {
        if finishedSent { return }
        let old = state
        state = newState
        poseEstablished = pose && newState == "TRACKING"
        if old != newState {
            G1Trace.mark("ar.state", [("state", newState), ("injected", String(injected))])
            emitEvent("state", [("state", newState), ("signal_ns", signalNanos), ("injected", injected)])
        }
        applyArrow(signalNanos)
        updateStatus()
    }

    private func applyArrow(_ signalNanos: UInt64) {
        let visible = state == "TRACKING" && poseEstablished && guidanceAllowed
        let was = !arrow.isHidden
        if visible == was { return }
        arrow.isHidden = !visible
        pendingLatency = (visible, signalNanos)
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(onFrame))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    /// First frame after the visibility change: report the signal-to-frame latency (analog of Choreographer on Android).
    @objc private func onFrame() {
        displayLink?.invalidate()
        displayLink = nil
        guard let p = pendingLatency else { return }
        pendingLatency = nil
        let latency = G1Trace.nowNanos() &- p.signal
        G1Trace.mark("ar.arrow", [("visible", String(p.visible)), ("latency_ns", String(latency))])
        emitEvent("arrow", [("visible", p.visible), ("latency_ns", latency)])
    }

    private func updateStatus() {
        var s: String
        switch state {
        case "TRACKING": s = poseEstablished ? text("tracking", "Tracking") : text("no_pose", "Position not confirmed. Follow the text directions.")
        case "LIMITED": s = text("limited", "Tracking limited. The arrow is hidden.")
        case "LOST": s = text("lost", "Tracking lost. The arrow is hidden. Follow the text directions.")
        case "PAUSED": s = text("paused", "AR paused.")
        default: s = text("initializing", "Starting AR...")
        }
        if injected { s = "SIMULATED \u{00B7} " + s }
        if status.text != s {
            status.text = s
            UIAccessibility.post(notification: .announcement, argument: s)
        }
    }

    private func emitEvent(_ type: String, _ body: [(String, Any?)]) {
        emit(Json.object([("type", type)] + body))
    }

    @objc private func onClose() { closeWith("user") }

    /// Background: no camera, no guidance; a stale pose is never reused after resume (pose must be re-established).
    @objc private func onBackground() { onTrackingSignal("PAUSED", G1Trace.nowNanos(), false) }

    private func closeWith(_ reason: String) {
        if finishedSent { return }
        state = "CLOSED"
        arrow.isHidden = true
        emitEvent("closed", [("reason", reason)])
        finishedSent = true
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
        displayLink = nil
        sceneView?.session.pause()
        G1Native.unregisterArScreen(requestId)
        if presentingViewController != nil { dismiss(animated: false) }
    }
}
#endif
