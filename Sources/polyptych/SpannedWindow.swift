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

        // ARC owns this window; without this AppKit would also release it on
        // close(), over-releasing and crashing in objc_release.
        isReleasedWhenClosed = false

        level = .floating
        collectionBehavior = [.canJoinAllSpaces]

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}
