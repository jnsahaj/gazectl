import CoreVideo
import Vision

struct FaceSample {
    let yaw: Double?
    let pitch: Double?
    let frameCount: Int
}

final class FaceTracker {
    private let camera = CameraCapture()
    private let condition = NSCondition()
    private var latestSampleState = FaceSample(yaw: nil, pitch: nil, frameCount: 0)
    private var smoothedYaw: Double?
    private var smoothedPitch: Double?
    private let sequenceHandler = VNSequenceRequestHandler()
    private let faceRequest: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }()

    /// EMA smoothing factor (0–1). Lower = smoother / more lag, higher = more responsive / more noise.
    private let smoothing: Double = 0.3

    var latestYaw: Double? {
        snapshot().yaw
    }

    var latestPitch: Double? {
        snapshot().pitch
    }

    var frameCount: Int {
        snapshot().frameCount
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

    func snapshot() -> FaceSample {
        condition.lock()
        defer { condition.unlock() }
        return latestSampleState
    }

    func waitForNextSample(after frameCount: Int, timeout: TimeInterval) -> FaceSample? {
        let deadline = Date().addingTimeInterval(timeout)

        condition.lock()
        defer { condition.unlock() }

        while latestSampleState.frameCount <= frameCount {
            if !condition.wait(until: deadline), latestSampleState.frameCount <= frameCount {
                return nil
            }
        }

        return latestSampleState
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        autoreleasepool {
            do {
                try sequenceHandler.perform([faceRequest], on: pixelBuffer)
            } catch {
                return
            }

            guard let face = faceRequest.results?.first,
                  let yawNumber = face.yaw else {
                publishCurrentState()
                return
            }

            let yawDegrees = yawNumber.doubleValue * 180.0 / .pi
            let pitchDegrees = face.pitch.map { $0.doubleValue * 180.0 / .pi }
            updateSample(yaw: yawDegrees, pitch: pitchDegrees)
        }
    }

    private func publishCurrentState() {
        condition.lock()
        latestSampleState = FaceSample(
            yaw: smoothedYaw,
            pitch: smoothedPitch,
            frameCount: latestSampleState.frameCount + 1
        )
        condition.broadcast()
        condition.unlock()
    }

    private func updateSample(yaw: Double, pitch: Double?) {
        condition.lock()

        if let previousYaw = smoothedYaw {
            smoothedYaw = previousYaw + smoothing * (yaw - previousYaw)
        } else {
            smoothedYaw = yaw
        }

        if let pitch {
            if let previousPitch = smoothedPitch {
                smoothedPitch = previousPitch + smoothing * (pitch - previousPitch)
            } else {
                smoothedPitch = pitch
            }
        }

        latestSampleState = FaceSample(
            yaw: smoothedYaw,
            pitch: smoothedPitch,
            frameCount: latestSampleState.frameCount + 1
        )
        condition.broadcast()
        condition.unlock()
    }
}
