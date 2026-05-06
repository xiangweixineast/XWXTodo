import AppKit

final class OverlayPanel: NSPanel {
    // The expanded panel needs keyboard focus for editing while the app stays out of the main window cycle.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
