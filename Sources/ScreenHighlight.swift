import AppKit

enum ScreenHighlight {
    private static var overlayWindow: NSWindow?

    static func show(for displayID: Int) {
        hide()

        guard let screen = screenFor(displayID: CGDirectDisplayID(displayID)) else { return }

        // Ensure NSApplication is initialized so we can display windows from CLI
        if NSApp == nil { _ = NSApplication.shared }
        NSApp.setActivationPolicy(.accessory)

        let frame = screen.frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let borderView = HighlightBorderView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = borderView

        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        overlayWindow = window

        // Flush UI so the window renders before readLine() blocks
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    static func hide() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    private static func screenFor(displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return num == displayID
        }
    }
}

private final class HighlightBorderView: NSView {
    private static let borderWidth: CGFloat = 20

    override func draw(_ dirtyRect: NSRect) {
        let w = Self.borderWidth
        let inset = w / 2

        // Outer glow
        let outerPath = NSBezierPath(rect: bounds.insetBy(dx: inset / 2, dy: inset / 2))
        outerPath.lineWidth = w * 1.5
        NSColor(calibratedRed: 0, green: 1, blue: 1, alpha: 0.25).setStroke()
        outerPath.stroke()

        // Main border
        let path = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
        path.lineWidth = w
        NSColor(calibratedRed: 0, green: 1, blue: 1, alpha: 1).setStroke()
        path.stroke()
    }
}
