import Foundation
import CoreGraphics

// MARK: - CLI argument parsing

struct Config {
    var calibrate = false
    var calibrationFile: String
    var cameraIndex = 0
    var verbose = false

    static let defaultCalibrationPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/share/gazectl/calibration.json"
    }()

    init() {
        calibrationFile = Self.defaultCalibrationPath
    }
}

func parseArgs() -> Config {
    var config = Config()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--calibrate":
            config.calibrate = true
        case "--calibration-file":
            guard !args.isEmpty else {
                CLI.error("--calibration-file requires a path")
                exit(1)
            }
            config.calibrationFile = args.removeFirst()
        case "--camera":
            guard !args.isEmpty, let idx = Int(args.removeFirst()) else {
                CLI.error("--camera requires an integer")
                exit(1)
            }
            config.cameraIndex = idx
        case "--verbose":
            config.verbose = true
        case "-v", "--version":
            CLI.printVersion()
            exit(0)
        case "-h", "--help":
            CLI.printUsage()
            exit(0)
        default:
            CLI.error("Unknown argument: \(arg)")
            CLI.printUsage()
            exit(1)
        }
    }
    return config
}

// MARK: - Signal handling

var running = true

func handleSignal(_: Int32) {
    running = false
}

signal(SIGINT, handleSignal)
signal(SIGTERM, handleSignal)

// MARK: - Main

let config = parseArgs()

CLI.printBanner()

// 1. Check monitors
let monitorSpinner = CLI.Spinner("Detecting monitors…")
monitorSpinner.start()

let monitors = MonitorManager.listMonitors()

if monitors.count < 2 {
    monitorSpinner.fail(finalMessage: "Need at least 2 monitors (found \(monitors.count))")
    exit(1)
}
monitorSpinner.stop(finalMessage: "Found \(monitors.count) monitors")

// 2. Start face tracker
let cameraSpinner = CLI.Spinner("Starting camera…")
cameraSpinner.start()

let faceTracker = FaceTracker()
do {
    try faceTracker.start(cameraIndex: config.cameraIndex)
} catch {
    cameraSpinner.fail(finalMessage: "Cannot open camera \(config.cameraIndex): \(error)")
    exit(1)
}

// Wait for camera to initialize
Thread.sleep(forTimeInterval: 1.0)
cameraSpinner.update("Waiting for frames…")

// Check if camera is actually delivering frames
let initialFrames = faceTracker.frameCount
Thread.sleep(forTimeInterval: 1.0)
if faceTracker.frameCount == initialFrames {
    cameraSpinner.fail(finalMessage: "No frames received from camera")
    CLI.info("Check System Settings → Privacy & Security → Camera")
    faceTracker.stop()
    exit(1)
}
cameraSpinner.stop(finalMessage: "Camera ready")

// 3. Load or run calibration
var calibration: [String: GazePoint]?
if !config.calibrate {
    calibration = Calibration.load(from: config.calibrationFile)
    if calibration != nil {
        CLI.success("Loaded calibration")
    }
}

if calibration == nil {
    calibration = Calibration.run(faceTracker: faceTracker, monitors: monitors)
    guard let cal = calibration else {
        // User cancelled (Ctrl+C / EOF)
        faceTracker.stop()
        CLI.printExit()
        exit(0)
    }
    Calibration.save(cal, to: config.calibrationFile)
}

let cal = calibration!

// 4. Print startup summary
let sortedCal = cal.sorted { $0.value.yaw < $1.value.yaw }
let boundaryValues = Calibration.boundaries(from: cal)

let monitorSummary: [(name: String, gaze: GazePoint)] = sortedCal.map { idStr, gaze in
    let name = monitors.first { String($0.id) == idStr }?.name ?? "?"
    return (name: name, gaze: gaze)
}

CLI.printStartupSummary(
    monitors: monitorSummary,
    boundaries: boundaryValues,
    verbose: config.verbose
)

// 5. Tracking loop
let initialFocusedMonitor = MonitorManager.focusedMonitor()
var focusedMonitor = initialFocusedMonitor ?? MonitorManager.currentMonitor()
var gazeMonitor = focusedMonitor
var lastAppliedGazeMonitor = gazeMonitor
var lastLeftMouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
let switchCooldown: TimeInterval = 0.5   // minimum seconds between switches
var lastSwitchTime = Date.distantPast

while running {
    if let yaw = faceTracker.latestYaw {
        let pitch = faceTracker.latestPitch ?? 0.0
        let cursorMonitor = MonitorManager.currentMonitor()
        let leftMouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        if lastLeftMouseDown && !leftMouseDown, let cursorMonitor {
            focusedMonitor = cursorMonitor
        } else if let detectedFocusedMonitor = MonitorManager.focusedMonitor() {
            focusedMonitor = detectedFocusedMonitor
        }
        lastLeftMouseDown = leftMouseDown

        let target = Calibration.targetMonitor(
            yaw: yaw, pitch: pitch,
            calibration: cal,
            currentMonitor: gazeMonitor ?? focusedMonitor ?? 0
        )
        gazeMonitor = target

        if config.verbose {
            let targetName = monitors.first { $0.id == target }?.name ?? "?"
            CLI.printTrackingStatus(yaw: yaw, pitch: pitch, targetName: targetName)
        }

        if gazeMonitor != lastAppliedGazeMonitor {
            let transition = MonitorManager.transition(
                to: target,
                focusedMonitor: focusedMonitor,
                cursorMonitor: cursorMonitor
            )

            if transition.requiresAction {
                let now = Date()
                if now.timeIntervalSince(lastSwitchTime) >= switchCooldown {
                    let name = monitors.first { $0.id == target }?.name ?? "?"
                    MonitorManager.focusMonitor(target, transition: transition)
                    focusedMonitor = target
                    lastAppliedGazeMonitor = target
                    lastSwitchTime = now
                    CLI.printFocusSwitch(name)
                }
            } else {
                lastAppliedGazeMonitor = target
            }
        }
    }
    Thread.sleep(forTimeInterval: 0.033)
}

// Cleanup
faceTracker.stop()
CLI.printExit()
exit(0)
