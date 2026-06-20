import AppKit
import CoreGraphics

enum DisplayLayout {
    static func selectedScreens() -> [NSScreen] {
        NSScreen.screens
    }

    static func unionRect(of screens: [NSScreen]) -> NSRect {
        guard let first = screens.first else { return .zero }
        var union = first.frame
        for screen in screens.dropFirst() {
            union = union.union(screen.frame)
        }
        return union
    }

    static func slices(for screens: [NSScreen], relativeTo rect: NSRect) -> [(screen: NSScreen, slice: NSRect)] {
        screens.map { screen in
            let slice = NSRect(
                x: screen.frame.origin.x - rect.origin.x,
                y: screen.frame.origin.y - rect.origin.y,
                width: screen.frame.width,
                height: screen.frame.height
            )
            return (screen, slice)
        }
    }

    static func isBuiltin(_ screen: NSScreen) -> Bool {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID ?? 0
        return CGDisplayIsBuiltin(id) != 0
    }
}
