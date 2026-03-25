import Foundation

// MARK: - ANSI Escape Codes

enum Style {
    static let reset   = "\u{1B}[0m"
    static let bold    = "\u{1B}[1m"
    static let dim     = "\u{1B}[2m"
    static let italic  = "\u{1B}[3m"

    static let red     = "\u{1B}[31m"
    static let green   = "\u{1B}[32m"
    static let yellow  = "\u{1B}[33m"
    static let blue    = "\u{1B}[34m"
    static let magenta = "\u{1B}[35m"
    static let cyan    = "\u{1B}[36m"
    static let white   = "\u{1B}[37m"
    static let gray    = "\u{1B}[90m"

    static let bgCyan  = "\u{1B}[46m"
    static let bgRed   = "\u{1B}[41m"

    // Cursor control
    static let clearLine = "\u{1B}[2K"
    static let cursorUp  = "\u{1B}[1A"
    static let hideCursor = "\u{1B}[?25l"
    static let showCursor = "\u{1B}[?25h"
    static let saveCursor = "\u{1B}[s"
    static let restoreCursor = "\u{1B}[u"
}

// MARK: - Styled print helpers

enum CLI {

    static func brand(_ text: String) {
        print("\(Style.bold)\(Style.cyan)\(text)\(Style.reset)")
    }

    static func success(_ text: String) {
        print("  \(Style.green)✓\(Style.reset) \(text)")
    }

    static func error(_ text: String) {
        print("  \(Style.red)✗\(Style.reset) \(Style.red)\(text)\(Style.reset)")
    }

    static func warning(_ text: String) {
        print("  \(Style.yellow)!\(Style.reset) \(Style.yellow)\(text)\(Style.reset)")
    }

    static func info(_ text: String) {
        print("  \(Style.dim)\(text)\(Style.reset)")
    }

    static func label(_ key: String, _ value: String) {
        print("  \(Style.dim)\(key)\(Style.reset) \(value)")
    }

    static func monitorLine(_ name: String, _ detail: String) {
        print("  \(Style.bold)\(Style.white)  \(name)\(Style.reset)  \(Style.cyan)\(detail)\(Style.reset)")
    }

    // MARK: - Banner

    private static func fg256(_ n: Int) -> String { "\u{1B}[38;5;\(n)m" }

    static func printBanner() {
        let lines = [
            " ██████╗  █████╗ ███████╗███████╗ ██████╗████████╗██╗     ",
            "██╔════╝ ██╔══██╗╚══███╔╝██╔════╝██╔════╝╚══██╔══╝██║     ",
            "██║  ███╗███████║  ███╔╝ █████╗  ██║        ██║   ██║     ",
            "██║   ██║██╔══██║ ███╔╝  ██╔══╝  ██║        ██║   ██║     ",
            "╚██████╔╝██║  ██║███████╗███████╗╚██████╗   ██║   ███████╗",
            " ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝   ╚═╝   ╚══════╝",
        ]
        // Teal/cyan gradient (256-color palette)
        let colors = [116, 109, 73, 67, 66, 59]

        print()
        for (i, line) in lines.enumerated() {
            let color = colors[i % colors.count]
            print("\(fg256(color))\(line)\(Style.reset)")
        }
        print("\(fg256(59))  ─────────────────────────────────────────────────────\(Style.reset)")
        print("\(fg256(109))  head tracking display switcher\(Style.reset)")
        print()
    }

    // MARK: - Styled help

    static func printUsage() {
        printBanner()
        print("""
          \(Style.dim)$\(Style.reset) gazectl [options]

          \(Style.cyan)--calibrate\(Style.reset)            Force recalibration
          \(Style.cyan)--calibration-file\(Style.reset) F   Path to calibration file
          \(Style.cyan)--camera\(Style.reset) N             Camera index \(Style.dim)(default: 0)\(Style.reset)
          \(Style.cyan)--verbose\(Style.reset)              Print yaw angle continuously
          \(Style.cyan)-h, --help\(Style.reset)             Show this help
        """)
    }

    // MARK: - Spinner

    final class Spinner {
        private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        private var frameIndex = 0
        private var message: String
        private var timer: DispatchSourceTimer?
        private let queue = DispatchQueue(label: "com.gazectl.spinner")
        private var isRunning = false

        init(_ message: String) {
            self.message = message
        }

        func start() {
            isRunning = true
            print(Style.hideCursor, terminator: "")
            fflush(stdout)

            timer = DispatchSource.makeTimerSource(queue: queue)
            timer?.schedule(deadline: .now(), repeating: .milliseconds(80))
            timer?.setEventHandler { [weak self] in
                guard let self = self, self.isRunning else { return }
                let frame = self.frames[self.frameIndex % self.frames.count]
                self.frameIndex += 1
                print("\(Style.clearLine)\r  \(Style.cyan)\(frame)\(Style.reset) \(self.message)", terminator: "")
                fflush(stdout)
            }
            timer?.resume()
        }

        func update(_ newMessage: String) {
            queue.sync { message = newMessage }
        }

        func stop(finalMessage: String? = nil) {
            isRunning = false
            timer?.cancel()
            timer = nil
            print("\(Style.clearLine)\r", terminator: "")
            if let msg = finalMessage {
                print("  \(Style.green)✓\(Style.reset) \(msg)")
            }
            print(Style.showCursor, terminator: "")
            fflush(stdout)
        }

        func fail(finalMessage: String) {
            isRunning = false
            timer?.cancel()
            timer = nil
            print("\(Style.clearLine)\r", terminator: "")
            print("  \(Style.red)✗\(Style.reset) \(Style.red)\(finalMessage)\(Style.reset)")
            print(Style.showCursor, terminator: "")
            fflush(stdout)
        }
    }

    // MARK: - Progress Bar

    static func progressBar(current: Int, total: Int, width: Int = 24) -> String {
        let fraction = Double(current) / Double(max(total, 1))
        let filled = Int(fraction * Double(width))
        let empty = width - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let pct = Int(fraction * 100)
        return "\(Style.cyan)\(bar)\(Style.reset) \(Style.dim)\(pct)%\(Style.reset)"
    }

    static func printSamplingProgress(yaw: Double, sampleCount: Int, totalSamples: Int) {
        let bar = progressBar(current: sampleCount, total: totalSamples)
        let yawStr = String(format: "%+.1f°", yaw)
        print("\(Style.clearLine)\r  \(bar)  \(Style.dim)yaw:\(Style.reset) \(Style.cyan)\(yawStr)\(Style.reset)", terminator: "")
        fflush(stdout)
    }

    // MARK: - Tracking status line

    static func printTrackingStatus(yaw: Double, targetName: String) {
        let yawStr = String(format: "%+6.1f°", yaw)
        print("\(Style.clearLine)\r  \(Style.dim)yaw\(Style.reset) \(Style.cyan)\(yawStr)\(Style.reset)  \(Style.dim)→\(Style.reset)  \(Style.bold)\(targetName)\(Style.reset)", terminator: "")
        fflush(stdout)
    }

    static func printFocusSwitch(_ name: String) {
        print("\(Style.clearLine)\r  \(Style.green)⏵\(Style.reset) \(Style.bold)Focused: \(name)\(Style.reset)")
    }

    // MARK: - Calibration styled output

    static func printCalibrationHeader(monitorCount: Int) {
        print()
        print("  \(Style.bold)\(Style.yellow)◆ Calibration\(Style.reset)")
        print("  \(Style.dim)Found \(monitorCount) monitors\(Style.reset)")
        print()
    }

    static func printCalibrationPrompt(_ monitorName: String, step: Int, total: Int) {
        print("  \(Style.dim)[\(step)/\(total)]\(Style.reset) Look at \(Style.bold)\(monitorName)\(Style.reset), press \(Style.cyan)Enter\(Style.reset), and keep looking for \(Style.bold)2s\(Style.reset)")
    }

    static func printCalibrationResult(_ monitorName: String, yaw: Double) {
        let yawStr = String(format: "%+.1f°", yaw)
        print("  \(Style.green)✓\(Style.reset) \(Style.bold)\(monitorName)\(Style.reset)  \(Style.cyan)\(yawStr)\(Style.reset)")
    }

    static func printCalibrationSummary(_ entries: [(name: String, yaw: Double)]) {
        print()
        print("  \(Style.bold)\(Style.green)✓ Calibration complete\(Style.reset)")
        print()
        for entry in entries {
            let yawStr = String(format: "%+.1f°", entry.yaw)
            print("    \(Style.bold)\(entry.name)\(Style.reset)  \(Style.cyan)\(yawStr)\(Style.reset)")
        }
        print()
    }

    // MARK: - Startup summary

    static func printStartupSummary(
        monitors: [(name: String, yaw: Double)],
        boundaries: [Double],
        verbose: Bool
    ) {
        print()
        print("  \(Style.bold)Monitors\(Style.reset)")
        for m in monitors {
            let yawStr = String(format: "%+.1f°", m.yaw)
            print("    \(Style.cyan)●\(Style.reset) \(Style.bold)\(m.name)\(Style.reset)  \(Style.dim)\(yawStr)\(Style.reset)")
        }
        print()
        let bStr = boundaries.map { String(format: "%+.1f°", $0) }.joined(separator: "  ")
        print("  \(Style.dim)boundaries  \(bStr)\(Style.reset)")
        if verbose {
            print("  \(Style.dim)verbose     on\(Style.reset)")
        }
        print()
        print("  \(Style.dim)Turn your head to switch focus.\(Style.reset)")
        print("  \(Style.dim)Press \(Style.reset)Ctrl+C\(Style.dim) to quit.\(Style.reset)")
        print()
    }

    // MARK: - Exit

    static func printExit() {
        print("\(Style.clearLine)\r")
        print("  \(Style.dim)Stopped.\(Style.reset)")
        print(Style.showCursor, terminator: "")
        fflush(stdout)
    }
}
