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
    print("""
    polyptych \(polyptychVersion) (\(polyptychCommit)) — fullscreen video across multiple displays

    USAGE:
      polyptych <file>                    Play a local file
      polyptych <url>                     Play a network stream (YouTube etc.)
      polyptych --youtube <search terms>  Search YouTube, download 1080p, and play
      polyptych --no-cache --youtube <search terms>
                                          Same, but ignore the download cache

    OPTIONS:
      -h, --help                          Show this help and exit
      -v, --version                       Show the version and exit
      -d, --debug                         Print fps/timing diagnostics to stderr

    CONTROLS:
      Space                               Pause / resume
      ← →                                 Seek -5s / +5s
      ↓ ↑                                 Seek -60s / +60s
      [ ]                                 Audio delay -/+ 50ms
      { }                                 Frame delay -/+ 50ms
      q, Esc                              Quit (saves position for resume)

    Configuration: ~/.config/polyptych/config.json
    """)
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
