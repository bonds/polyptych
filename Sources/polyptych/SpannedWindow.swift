import AppKit

final class SpannedWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    init(screenFrame: NSRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = true
        backgroundColor = .black
        hasShadow = false

        level = .floating
        collectionBehavior = [.canJoinAllSpaces]

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}
