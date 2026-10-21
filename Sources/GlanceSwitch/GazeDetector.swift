import AVFoundation
import Vision
import AppKit

/// Captures frames from the front camera and reports estimated head-yaw
/// (how far your head is turned left/right, in radians).
final class GazeDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Called on a background queue with the latest head pose in radians.
    /// `yaw`: turned left/right. `pitch`: tilted up/down.
    var onPose: ((_ yaw: Double, _ pitch: Double) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.sampersonal.glanceswitch.camera")
    private let request: VNDetectFaceRectanglesRequest
    private var lastProcessed = Date.distantPast
    private let minInterval: TimeInterval = 0.08  // ~12 fps of Vision work

    private(set) var isRunning = false

    /// All available video cameras (built-in, external/USB, Continuity).
    static func availableCameras() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types.append(.external)
            types.append(.continuityCamera)
        }
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types,
                                                       mediaType: .video,
                                                       position: .unspecified)
        return session.devices
    }

    override init() {
        request = VNDetectFaceRectanglesRequest()
        // Revision 3 populates continuous yaw/pitch/roll on the observation.
        request.revision = VNDetectFaceRectanglesRequestRevision3
        super.init()
    }

    func start(completion: ((Bool) -> Void)? = nil) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            self.queue.async {
                let ok = self.configureAndRun()
                DispatchQueue.main.async { completion?(ok) }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.session.stopRunning()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.isRunning = false
        }
    }

    /// Stop and restart the capture session (e.g. after switching cameras).
    /// Assumes camera access was already granted.
    func restart(completion: ((Bool) -> Void)? = nil) {
        stop()
        queue.async { [weak self] in
            guard let self = self else { return }
            let ok = self.configureAndRun()
            DispatchQueue.main.async { completion?(ok) }
        }
    }

    private func configureAndRun() -> Bool {
        guard !isRunning else { return true }

        session.beginConfiguration()
        session.sessionPreset = .medium

        let device = Self.selectedDevice()

        guard let camera = device,
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addOutput(output)

        // Pin mirroring so the yaw sign is deterministic across cameras/sessions.
        // Mirrored (selfie view): turning your head right moves your face right in
        // the image, so right turn -> positive yaw -> right-most screen.
        if let connection = output.connection(with: .video),
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        session.commitConfiguration()
        session.startRunning()
        isRunning = true
        return true
    }

    /// Resolve the camera to use: the user's saved choice if still present,
    /// otherwise the system default.
    private static func selectedDevice() -> AVCaptureDevice? {
        if let id = Preferences.shared.cameraUniqueID,
           let device = availableCameras().first(where: { $0.uniqueID == id }) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessed) >= minInterval else { return }
        lastProcessed = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  let yaw = observation.yaw?.doubleValue else { return }
            let pitch = observation.pitch?.doubleValue ?? 0
            onPose?(yaw, pitch)
        } catch {
            // Transient Vision errors are ignored; next frame will retry.
        }
    }
}
