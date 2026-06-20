import AppKit
import CoreGraphics

/// Detect display connection types by refresh rate.
/// Native screens typically run at 120Hz, DisplayLink at 60Hz.
enum DisplayDetector {

    static func classifyDisplays() -> (native: [NSScreen], displayLink: [NSScreen]) {
        var native: [NSScreen] = []
        var dl: [NSScreen] = []

        for screen in NSScreen.screens {
            if screen.maximumFramesPerSecond >= 100 {
                native.append(screen)
            } else {
                dl.append(screen)
            }
        }
        return (native, dl)
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID ?? 0
    }
}
