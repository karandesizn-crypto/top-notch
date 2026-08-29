import AppKit

extension RailWindowController {
    /// Where the rail landed, and on which screen.
    ///
    /// Verifying placement otherwise needs a screenshot, which needs screen-recording
    /// permission. This also makes the display-reconnect acceptance criterion checkable:
    /// plug or unplug a monitor and run it again.
    func placementDescription() -> String {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return "no screen" }
        let frame = panelFrame
        var lines: [String] = []
        lines.append("screens      \(NSScreen.screens.count)")
        lines.append("screen       \(Int(screen.frame.width))x\(Int(screen.frame.height))")
        lines.append("panel        \(Int(frame.width))x\(Int(frame.height)) at (\(Int(frame.minX)), \(Int(frame.minY)))")
        lines.append("right edge   panel \(Int(frame.maxX)) vs screen \(Int(screen.frame.maxX))")
        lines.append("top gap      \(Int(screen.visibleFrame.maxY - frame.maxY))pt below the menu bar")
        return lines.joined(separator: "\n")
    }
}
