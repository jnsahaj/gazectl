import CoreVideo
import Vision

final class FaceTracker {
    private let camera = CameraCapture()
    private let lock = NSLock()
    private var _latestYaw: Double?
    private var _smoothedYaw: Double?
    private var _latestPitch: Double?
    private var _smoothedPitch: Double?
    private var _frameCount: Int = 0

    /// EMA smoothing factor (0–1). Lower = smoother / more lag, higher = more responsive / more noise.
    private let smoothing: Double = 0.3

    var latestYaw: Double? {
        lock.lock()
        defer { lock.unlock() }
        return _smoothedYaw
    }

    var latestPitch: Double? {
        lock.lock()
        defer { lock.unlock() }
        return _smoothedPitch
    }

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _frameCount
    }

    func start(cameraIndex: Int) throws {
        camera.onFrame = { [weak self] pixelBuffer in
            self?.processFrame(pixelBuffer)
        }
        try camera.start(cameraIndex: cameraIndex)
    }

    func stop() {
        camera.stop()
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3

        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let face = request.results?.first,
              let yawNumber = face.yaw else {
            lock.lock()
            _latestYaw = nil
            _latestPitch = nil
            _frameCount += 1
            lock.unlock()
            return
        }

        let yawDegrees = yawNumber.doubleValue * 180.0 / .pi
        let pitchDegrees = face.pitch.map { $0.doubleValue * 180.0 / .pi }

        lock.lock()
        _latestYaw = yawDegrees
        if let prev = _smoothedYaw {
            _smoothedYaw = prev + smoothing * (yawDegrees - prev)
        } else {
            _smoothedYaw = yawDegrees
        }
        if let pitch = pitchDegrees {
            if let prev = _smoothedPitch {
                _smoothedPitch = prev + smoothing * (pitch - prev)
            } else {
                _smoothedPitch = pitch
            }
            _latestPitch = pitch
        }
        _frameCount += 1
        lock.unlock()
    }
}
