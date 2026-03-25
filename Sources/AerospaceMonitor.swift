import Foundation

enum AerospaceMonitor {
    struct Monitor {
        let id: Int
        let name: String
    }

    static func listMonitors() -> [Monitor] {
        guard let output = runAerospace(["list-monitors"]) else { return [] }
        var monitors: [Monitor] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            guard let idStr = parts.first,
                  let id = Int(idStr.trimmingCharacters(in: .whitespaces)) else { continue }
            let name = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                : ""
            monitors.append(Monitor(id: id, name: name))
        }
        return monitors
    }

    static func currentMonitor() -> Int? {
        guard let output = runAerospace(["list-monitors", "--focused"]) else { return nil }
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let parts = line.split(separator: "|", maxSplits: 1)
        guard let idStr = parts.first else { return nil }
        return Int(idStr.trimmingCharacters(in: .whitespaces))
    }

    static func isInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["aerospace"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func focusMonitor(_ id: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["aerospace", "focus-monitor", String(id)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private static func runAerospace(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["aerospace"] + args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        if process.terminationStatus != 0 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !errStr.isEmpty {
                CLI.warning("aerospace \(args.joined(separator: " ")): \(errStr)")
            }
            return nil
        }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
