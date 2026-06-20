import AppKit

enum InputMode {
    case file(String)
    case url(String)
    case youtubeSearch(String)
}

func parseArgs() -> InputMode? {
    let args = CommandLine.arguments.dropFirst()
    guard let first = args.first else { return nil }

    if first == "-yt" || first == "--youtube" {
        let query = args.dropFirst().joined(separator: " ")
        guard !query.isEmpty else { return nil }
        return .youtubeSearch(query)
    }

    if first.hasPrefix("ytdl://") || first.hasPrefix("http://") || first.hasPrefix("https://") {
        return .url(first)
    }

    return .file(first)
}

guard let mode = parseArgs() else {
    fputs("Usage: polyptych <video-file>\n       polyptych <url>\n       polyptych --youtube <search terms>\n", stderr)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let menubar = NSMenu(title: "polyptych")
let appItem = NSMenuItem(title: "polyptych", action: nil, keyEquivalent: "")
let appMenu = NSMenu(title: "polyptych")
let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenu.addItem(quitItem)
appItem.submenu = appMenu
menubar.addItem(appItem)
app.mainMenu = menubar

let delegate = AppDelegate(mode: mode)
app.delegate = delegate
app.run()
