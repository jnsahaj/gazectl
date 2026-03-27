import Foundation

struct GazePoint {
    let yaw: Double
    let pitch: Double
}

enum Calibration {
    // MARK: - Persistence

    static func load(from path: String) -> [String: GazePoint]? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                CLI.warning("Calibration file is corrupt, will recalibrate")
                return nil
            }
            var result: [String: GazePoint] = [:]
            for (key, value) in dict {
                if let obj = value as? [String: Any],
                   let yaw = obj["yaw"] as? Double,
                   let pitch = obj["pitch"] as? Double {
                    result[key] = GazePoint(yaw: yaw, pitch: pitch)
                } else if value is Double || value is NSNumber {
                    // Old format (yaw-only) — needs recalibration
                    CLI.warning("Old calibration format, will recalibrate")
                    return nil
                }
            }
            return result.isEmpty ? nil : result
        } catch {
            CLI.warning("Cannot read calibration file: \(error.localizedDescription)")
            return nil
        }
    }

    static func save(_ calibration: [String: GazePoint], to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        var dict: [String: [String: Double]] = [:]
        for (key, point) in calibration {
            dict[key] = ["yaw": point.yaw, "pitch": point.pitch]
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: URL(fileURLWithPath: path))
            CLI.success("Saved calibration")
        } catch {
            CLI.error("Failed to save calibration: \(error)")
        }
    }

    // MARK: - Sampling

    static func sampleGaze(faceTracker: FaceTracker, duration: TimeInterval = 2.0) -> GazePoint? {
        var yawSamples: [Double] = []
        var pitchSamples: [Double] = []
        let start = Date()
        let expectedSamples = Int(duration / 0.033)
        var lastFrameCount = faceTracker.frameCount

        while Date().timeIntervalSince(start) < duration {
            guard let sample = faceTracker.waitForNextSample(after: lastFrameCount, timeout: 0.1) else {
                continue
            }

            lastFrameCount = sample.frameCount

            if let yaw = sample.yaw {
                yawSamples.append(yaw)
                if let pitch = sample.pitch {
                    pitchSamples.append(pitch)
                }
                CLI.printSamplingProgress(
                    yaw: yaw,
                    pitch: sample.pitch,
                    sampleCount: yawSamples.count,
                    totalSamples: expectedSamples
                )
            }
        }
        // Clear the progress line
        print("\(Style.clearLine)\r", terminator: "")
        fflush(stdout)

        guard !yawSamples.isEmpty else { return nil }
        let sortedYaw = yawSamples.sorted()
        let sortedPitch = pitchSamples.sorted()
        let medianYaw = sortedYaw[sortedYaw.count / 2]
        let medianPitch = sortedPitch.isEmpty ? 0.0 : sortedPitch[sortedPitch.count / 2]
        return GazePoint(yaw: medianYaw, pitch: medianPitch)
    }

    // MARK: - Interactive calibration

    static func run(
        faceTracker: FaceTracker,
        monitors: [Monitor]
    ) -> [String: GazePoint]? {
        CLI.printCalibrationHeader(monitorCount: monitors.count)

        var calibration: [String: GazePoint] = [:]

        for (index, m) in monitors.enumerated() {
            ScreenHighlight.show(for: m.id)
            CLI.printCalibrationPrompt(m.name, step: index + 1, total: monitors.count)
            guard readLine() != nil else {
                ScreenHighlight.hide()
                return nil
            }

            var gaze = sampleGaze(faceTracker: faceTracker)
            if gaze == nil {
                CLI.warning("No face detected. Try again.")
                CLI.printCalibrationPrompt(m.name, step: index + 1, total: monitors.count)
                guard readLine() != nil else {
                    ScreenHighlight.hide()
                    return nil
                }
                gaze = sampleGaze(faceTracker: faceTracker)
                if gaze == nil {
                    CLI.error("Still no face detected. Skipping.")
                    ScreenHighlight.hide()
                    continue
                }
            }

            ScreenHighlight.hide()
            calibration[String(m.id)] = gaze!
            CLI.printCalibrationResult(m.name, gaze: gaze!)
        }

        if calibration.count < 2 {
            CLI.error("Need at least 2 calibrated monitors.")
            exit(1)
        }

        let sorted = calibration.sorted { $0.value.yaw < $1.value.yaw }
        let entries: [(name: String, gaze: GazePoint)] = sorted.map { idStr, gaze in
            let name = monitors.first { String($0.id) == idStr }?.name ?? "?"
            return (name: name, gaze: gaze)
        }
        CLI.printCalibrationSummary(entries)

        return calibration
    }

    // MARK: - Target monitor selection

    /// Hysteresis factor applied as a distance bonus for the current monitor.
    /// A value of 0.25 means you must be 25% closer to another monitor's
    /// calibration point before switching, preventing flicker at boundaries.
    private static let hysteresis = 0.25

    static func targetMonitor(
        yaw: Double, pitch: Double,
        calibration: [String: GazePoint],
        currentMonitor: Int = 0
    ) -> Int {
        guard !calibration.isEmpty else { return 0 }

        let currentKey = String(currentMonitor)
        var bestMonitor = 0
        var bestDistance = Double.infinity

        for (key, point) in calibration {
            let dy = yaw - point.yaw
            let dp = pitch - point.pitch
            var distance = sqrt(dy * dy + dp * dp)

            // Hysteresis: the current monitor gets a distance bonus,
            // so you have to look noticeably closer to another before switching.
            if key == currentKey {
                distance *= (1.0 - hysteresis)
            }

            if distance < bestDistance {
                bestDistance = distance
                bestMonitor = Int(key) ?? 0
            }
        }

        return bestMonitor
    }

    static func boundaries(from calibration: [String: GazePoint]) -> [Double] {
        let sorted = calibration.sorted { $0.value.yaw < $1.value.yaw }
        var result: [Double] = []
        for i in 0..<(sorted.count - 1) {
            result.append((sorted[i].value.yaw + sorted[i + 1].value.yaw) / 2.0)
        }
        return result
    }
}
