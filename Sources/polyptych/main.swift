import AppKit
import Darwin

var debugMode = false

// Redirect stderr to a log file when launched without a terminal (Finder / extension)
if isatty(STDERR_FILENO) == 0 {
    _ = "/tmp/polyptych.log".withCString { freopen($0, "a", stderr) }
    setvbuf(stderr, nil, _IONBF, 0)
}

enum InputMode {
    case file(String)
    case url(String)
    case youtubeSearch(String, noCache: Bool)
}

func printUsage() {
    // Color only when stdout is a terminal (and the user hasn't opted out).
    let env = ProcessInfo.processInfo.environment
    let useColor: Bool
    if env["NO_COLOR"] != nil || env["TERM"] == "dumb" {
        useColor = false
    } else if let force = env["CLICOLOR_FORCE"], force != "0" {
        useColor = true
    } else {
        useColor = isatty(STDOUT_FILENO) != 0
    }

    func paint(_ code: String, _ s: String) -> String {
        useColor ? "\u{001B}[\(code)m\(s)\u{001B}[0m" : s
    }
    func heading(_ s: String) -> String { paint("1", s) }
    func row(_ lhs: String, _ rhs: String) -> String {
        let width = 42
        let pad = max(1, width - lhs.count)
        return "  " + paint("1;36", lhs) + String(repeating: " ", count: pad) + rhs
    }

    print(paint("1", "polyptych \(polyptychVersion) (\(polyptychCommit))") + " " + paint("2", "— fullscreen video across multiple displays"))
    print()
    print(heading("USAGE:"))
    print(row("polyptych <file>", "Play a local file"))
    print(row("polyptych <url>", "Play a network stream (YouTube etc.)"))
    print(row("polyptych --youtube <search terms>", "Search YouTube, download 1080p, and play"))
    print(row("polyptych --no-cache --youtube <terms>", "Same, but ignore the download cache"))
    print()
    print(heading("OPTIONS:"))
    print(row("-h, --help", "Show this help and exit"))
    print(row("-v, --version", "Show the version and exit"))
    print(row("-d, --debug", "Print fps/timing diagnostics to stderr"))
    print()
    print(heading("CONTROLS:"))
    print(row("Space", "Pause / resume"))
    print(row("← →", "Seek -5s / +5s"))
    print(row("↓ ↑", "Seek -60s / +60s"))
    print(row("[ ]", "Audio delay -/+ 50ms"))
    print(row("{ }", "Frame delay -/+ 50ms"))
    print(row("q, Esc", "Quit (saves position for resume)"))
    print()
    print(paint("2", "Configuration: ~/.config/polyptych/config.json"))
}

func parseArgs() -> InputMode? {
    // Extract --debug from anywhere, keep the rest as args
    let allArgs = CommandLine.arguments.dropFirst()
    var args: [String] = []
    for a in allArgs {
        if a == "--debug" || a == "-d" {
            debugMode = true
        } else {
            args.append(a)
        }
    }

    if debugMode {
        fputs("[polyptych] \(polyptychVersion) (\(polyptychCommit))\n", stderr)
    }

    guard let first = args.first else { return nil }

    if first == "--help" || first == "-h" {
        printUsage()
        exit(0)
    }

    if first == "--version" || first == "-v" {
        print("polyptych \(polyptychVersion) (\(polyptychCommit))")
        exit(0)
    }

    if first == "--no-cache" {
        let next = args.dropFirst().first
        if next == "-yt" || next == "--youtube" {
            let query = args.dropFirst(2).joined(separator: " ")
            guard !query.isEmpty else { return nil }
            return .youtubeSearch(query, noCache: true)
        }
        return nil
    }

    if first == "-yt" || first == "--youtube" {
        let query = args.dropFirst().joined(separator: " ")
        guard !query.isEmpty else { return nil }
        return .youtubeSearch(query, noCache: false)
    }

    if first.hasPrefix("ytdl://") || first.hasPrefix("http://") || first.hasPrefix("https://") {
        return .url(first)
    }

    return .file(first)
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

let delegate = AppDelegate(mode: parseArgs())
app.delegate = delegate
app.run()
