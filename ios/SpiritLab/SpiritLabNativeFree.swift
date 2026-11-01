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
    var body: some Scene {
        WindowGroup { SpiritLabConnectionScreen() }
    }
}

// If Tailscale or the private HTTPS server is unreachable, explain why instead
// of leaving the investigator with a blank, white WKWebView.
struct SpiritLabConnectionScreen: View {
    @AppStorage("spiritLabURL") private var address = "https://spiritlab.houseofsqueak.com/"
    @State private var reloadID = UUID()
    @State private var statusText = "Connecting to your private SpiritLab..."
    @State private var connecting = true
    @State private var failure: String? = nil
    @State private var settings = false
    @State private var addressDraft = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.04, green: 0.05, blue: 0.09).ignoresSafeArea()
            SpiritLabBrowser(address: address) { message, failed in
                connecting = message != nil && !failed
                statusText = message ?? ""
                failure = failed ? message : nil
            }
            .id(reloadID)
            .ignoresSafeArea(edges: .bottom)
            if connecting || failure != nil {
                VStack(spacing: 16) {
                    Image(systemName: failure == nil ? "waveform.path.ecg.rectangle" : "wifi.exclamationmark")
                        .font(.system(size: 44)).foregroundStyle(.mint)
                    Text(failure == nil ? "Connecting to SpiritLab" : "Connection Problem")
                        .font(.title3.bold()).foregroundStyle(.white)
                    Text(failure ?? statusText)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    if connecting { ProgressView().tint(.mint) }
                    if failure != nil {
                        Text("Ensure Tailscale is connected on this iPhone. Your Safari session and the app do not share their private web state.")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Button("Retry") { reload() }.buttonStyle(.borderedProminent).tint(.mint)
                        Button("Open in Safari") {
                            if let url = URL(string: address), url.scheme == "https" {
                                UIApplication.shared.open(url)
                            }
                        }.buttonStyle(.bordered)
                    }
                    Button("Server Settings") { addressDraft = address; settings = true }
                        .foregroundStyle(.mint)
                }
                .padding(24).frame(maxWidth: 360)
                .background(Color(red: 0.08, green: 0.10, blue: 0.16), in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                addressDraft = address
                settings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .padding(12).background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("SpiritLab server settings")
            .padding(12)
        }
        .onAppear {
            // Upgrade only our original default. Preserve explicitly chosen custom hosts.
            if address == "https://sqeak--worker.tail7517d1.ts.net:8443/" {
                address = "https://spiritlab.houseofsqueak.com/"
                reload()
            }
        }
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Section("Private SpiritLab URL") {
                        TextField("https://...", text: $addressDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("Save & Connect") {
                            guard safeURL(addressDraft) else { return }
                            address = addressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            settings = false
                            reload()
                        }.disabled(!safeURL(addressDraft))
                    }
                    Section("Connection") {
                        Text("The iPhone must have Tailscale enabled. This app never bypasses certificate verification.")
                    }
                }
                .navigationTitle("SpiritLab Settings")
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { settings = false }
                }}
            }
        }
    }

    private func safeURL(_ input: String) -> Bool {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    private func reload() {
        failure = nil
        connecting = true
        statusText = "Connecting to your private SpiritLab..."
        reloadID = UUID()
    }
}

struct SpiritLabBrowser: UIViewRepresentable {
    let address: String
    let onStatus: (String?, Bool) -> Void

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
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onStatus = onStatus
        if let url = URL(string: address), url.scheme == "https",
           let host = url.host, url.user == nil, url.password == nil {
            context.coordinator.allowedHost = host
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
        } else {
            DispatchQueue.main.async { onStatus("Invalid HTTPS URL. Open Server Settings.", true) }
        }
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onStatus = onStatus
    }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopAll()
        for name in ["spiritLabSensor", "spiritLabTorch", "spiritLabLidar", "spiritLabEnvironment"] {
            uiView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, ARSessionDelegate {
        weak var webView: WKWebView?
        var allowedHost = ""
        var onStatus: ((String?, Bool) -> Void)?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onStatus?("Contacting SpiritLab via private Tailscale HTTPS...", false)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onStatus?(nil, false)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onStatus?("The web view stopped unexpectedly. Tap Retry.", true)
        }
        private func report(_ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            onStatus?("\(ns.localizedDescription) (error \(ns.code))", true)
        }
        private let motion = CMMotionManager()
        private let altimeter = CMAltimeter()
        private var session: ARSession?
        private let depthQueue = DispatchQueue(label: "spiritlab.arkit.depth", qos: .userInitiated)
        private var lastDepthTime = 0.0
        private var lastPoseTime = -100.0
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
            lastDepthTime = -100.0
            lastPoseTime = -100.0
            lastMedian = nil
            lastPosition = nil
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
            if frame.timestamp - lastPoseTime >= 1.6 {
                lastPoseTime = frame.timestamp
                detectOpticalHumanPose(frame.capturedImage)
            }
        }
        private func detectOpticalHumanPose(_ captured: CVPixelBuffer) {
            // Apple Vision is an optical human-pose *prediction*; never label as a spirit.
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: captured, options: [:])
            do {
                try handler.perform([request])
                let people = (request.results ?? []).prefix(3)
                let names: [(VNHumanBodyPoseObservation.JointName, String)] = [
                    (.nose,"nose"),(.neck,"neck"),(.leftShoulder,"leftShoulder"),
                    (.rightShoulder,"rightShoulder"),(.leftElbow,"leftElbow"),
                    (.rightElbow,"rightElbow"),(.leftWrist,"leftWrist"),
                    (.rightWrist,"rightWrist"),(.leftHip,"leftHip"),
                    (.rightHip,"rightHip"),(.leftKnee,"leftKnee"),
                    (.rightKnee,"rightKnee"),(.leftAnkle,"leftAnkle"),
                    (.rightAnkle,"rightAnkle")
                ]
                let skeletons: [[String: Any]] = people.map { person in
                    var points = [String: [String: Double]]()
                    for (key, name) in names {
                        if let point = try? person.recognizedPoint(key), point.confidence >= 0.45 {
                            points[name] = ["x": Double(point.location.x),
                                            "y": Double(point.location.y),
                                            "conf": Double(point.confidence)]
                        }
                    }
                    return ["joints": points]
                }
                emit("spiritlab:native-depth", [
                    "kind": "pose", "source": "iOS Vision optical body-pose model",
                    "skeletons": skeletons, "people": skeletons.count,
                    "note": "Camera-based prediction only; ordinary people or false positives possible",
                    "capturedAt": ISO8601DateFormatter().string(from: Date())
                ])
            } catch {
                emit("spiritlab:native-depth", ["kind": "pose", "skeletons": [],
                     "note": "Optical model unavailable for current camera image"])
            }
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
            if url.scheme == "https", (url.host == allowedHost ||
                (allowedHost == "spiritlab.houseofsqueak.com" &&
                 url.host == "weathered-leaf-b8c1.cloudflareaccess.com")) {
                // Permit only our exact Cloudflare Access login host; never bridge
                // native sensor commands into its origin (handled by the host guard).
                decisionHandler(.allow)
            }
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
