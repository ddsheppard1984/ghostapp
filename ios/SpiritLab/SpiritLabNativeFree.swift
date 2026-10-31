import SwiftUI
import WebKit
import CoreMotion
import AVFoundation
import ARKit
import Vision
import CoreVideo
import simd

@main
struct SpiritLabNativeApp: App {
    @AppStorage("spiritLabURL") private var address = "https://sqeak--worker.tail7517d1.ts.net:8443/"
    var body: some Scene {
        WindowGroup { SpiritLabBrowser(address: address) }
    }
}

struct SpiritLabBrowser: UIViewRepresentable {
    let address: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        for name in ["spiritLabSensor", "spiritLabTorch", "spiritLabLidar", "spiritLabEnvironment"] {
            config.userContentController.add(context.coordinator, name: name)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        if let url = URL(string: address), url.scheme == "https", url.host != nil {
            context.coordinator.allowedHost = url.host!
            webView.load(URLRequest(url: url))
        }
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopAll()
        for name in ["spiritLabSensor", "spiritLabTorch", "spiritLabLidar", "spiritLabEnvironment"] {
            uiView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, ARSessionDelegate {
        weak var webView: WKWebView?
        var allowedHost = ""
        private let motion = CMMotionManager()
        private let altimeter = CMAltimeter()
        private var session: ARSession?
        private let depthQueue = DispatchQueue(label: "spiritlab.arkit.depth", qos: .userInitiated)
        private var lastDepthTime = 0.0
        private var lastPosition: SIMD3<Float>?
        private var lastMedian: Float?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let page = webView?.url, page.scheme == "https", page.host == allowedHost,
                  message.frameInfo.securityOrigin.host == allowedHost,
                  let command = message.body as? String else { return }
            switch (message.name,command) {
            case ("spiritLabSensor", "start"): startMagnetometer()
            case ("spiritLabSensor", "stop"): motion.stopMagnetometerUpdates()
            case ("spiritLabTorch", "on"): torch(true)
            case ("spiritLabTorch", "off"): torch(false)
            case ("spiritLabLidar", "start"): startDepth()
            case ("spiritLabLidar", "stop"): stopDepth()
            case ("spiritLabEnvironment", "start"): startEnvironment()
            case ("spiritLabEnvironment", "stop"): stopEnvironment()
            default: break
            }
        }

        private func emit(_ event: String, _ payload: [String:Any]) {
            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let body = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.webView?.url?.host == self.allowedHost else { return }
                self.webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('\(event)',{detail:\(body)}))", completionHandler: nil)
            }
        }
        private func startMagnetometer() {
            guard motion.isMagnetometerAvailable else {
                emit("spiritlab:native-environment",["kind":"status","state":"magnetometer-unavailable"])
                return
            }
            motion.magnetometerUpdateInterval = 0.1
            motion.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
                guard let d = data else { return }
                let v = d.magneticField
                guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { return }
                self?.webView?.evaluateJavaScript("window.SpiritLabNativeMagnetometer?.(\(v.x),\(v.y),\(v.z))",completionHandler:nil)
            }
        }
        private func startEnvironment() {
            if motion.isDeviceMotionAvailable {
                motion.deviceMotionUpdateInterval = 0.1
                motion.startDeviceMotionUpdates(to: .main) { [weak self] value, _ in
                    guard let a = value?.userAcceleration else { return }
                    let strength = sqrt(a.x*a.x + a.y*a.y + a.z*a.z) * 9.80665
                    self?.emit("spiritlab:sensor",["type":"motion","value":strength,"unit":"m/s²","source":"CoreMotion"])
                }
            }
            if CMAltimeter.isRelativeAltitudeAvailable() {
                altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] info, _ in
                    guard let info = info else { return }
                    self?.emit("spiritlab:native-environment",[
                        "kind":"pressure","kPa":info.pressure.doubleValue,
                        "relativeAltitudeM":info.relativeAltitude.doubleValue,
                        "source":"CoreMotion barometer"])
                }
            }
            emit("spiritlab:native-environment",["kind":"status","state":"active"])
        }
        private func stopEnvironment() {
            motion.stopDeviceMotionUpdates()
            altimeter.stopRelativeAltitudeUpdates()
        }
        private func torch(_ enabled: Bool) {
            guard let camera = AVCaptureDevice.default(for: .video), camera.hasTorch else { return }
            do {
                try camera.lockForConfiguration()
                defer { camera.unlockForConfiguration() }
                if enabled { try camera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) }
                else { camera.torchMode = .off }
            } catch { emit("spiritlab:native-environment",["kind":"status","state":"torch-unavailable"]) }
        }
        private func startDepth() {
            guard ARWorldTrackingConfiguration.isSupported,
                  ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
                emit("spiritlab:native-depth",["kind":"status","state":"unsupported","message":"LiDAR not available on this iPhone"])
                return
            }
            stopDepth()
            let tracking = ARWorldTrackingConfiguration()
            tracking.frameSemantics.insert(.sceneDepth)
            let newSession = ARSession()
            newSession.delegate = self
            newSession.delegateQueue = depthQueue
            newSession.run(tracking, options:[.resetTracking,.removeExistingAnchors])
            session = newSession
            emit("spiritlab:native-depth",["kind":"status","state":"starting"])
        }
        private func stopDepth() {
            session?.pause()
            session?.delegate = nil
            session = nil
            emit("spiritlab:native-depth",["kind":"status","state":"stopped"])
        }
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard self.session === session, frame.timestamp-lastDepthTime >= 0.25 else { return }
            lastDepthTime = frame.timestamp
            guard let buffer = frame.sceneDepth?.depthMap,
                  CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else { return }
            CVPixelBufferLockBaseAddress(buffer,.readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
            guard let address = CVPixelBufferGetBaseAddress(buffer) else { return }
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
            let row = CVPixelBufferGetBytesPerRow(buffer)/MemoryLayout<Float>.size
            let samples = address.assumingMemoryBound(to:Float.self)
            var distances = [Float]()
            for y in stride(from:0,to:height,by:max(1,height/24)) {
                for x in stride(from:0,to:width,by:max(1,width/36)) {
                    let d = samples[y*row+x]
                    if d.isFinite && d > 0.12 && d < 12 { distances.append(d) }
                }
            }
            guard distances.count >= 20 else { return }
            distances.sort()
            let med = distances[distances.count/2]
            let position = SIMD3<Float>(frame.camera.transform.columns.3.x,frame.camera.transform.columns.3.y,frame.camera.transform.columns.3.z)
            let moved = lastPosition.map { simd_length(position - $0) } ?? 0
            let delta = lastMedian.map { abs(med-$0) } ?? 0
            lastPosition = position
            lastMedian = med
            emit("spiritlab:native-depth",[
                "kind":"lidar","source":"iOS ARKit LiDAR sceneDepth",
                "medianM":Double(med),"nearM":Double(distances[0]),
                "farM":Double(distances[distances.count-1]),
                "depthDeltaM":Double(delta),"cameraMotionM":Double(moved),
                "validSamples":distances.count,"tracking":"sensor-derived",
                "capturedAt":ISO8601DateFormatter().string(from:Date())])
        }
        func stopAll() {
            motion.stopMagnetometerUpdates()
            stopEnvironment()
            stopDepth()
            torch(false)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "https",url.host == allowedHost { decisionHandler(.allow) }
            else if action.navigationType == .linkActivated,url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else { decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision)->Void) {
            decisionHandler(origin.host == allowedHost ? .grant : .deny)
        }
    }
}
