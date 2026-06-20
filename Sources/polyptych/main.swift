import AppKit

let filePath = CommandLine.arguments.dropFirst().first
let isURL = filePath.map { $0.hasPrefix("ytdl://") || $0.hasPrefix("http://") || $0.hasPrefix("https://") } ?? false

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

let delegate = AppDelegate(filePath: filePath, isURL: isURL)
app.delegate = delegate
app.run()
