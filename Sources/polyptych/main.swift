import AppKit

let filePath = CommandLine.arguments.dropFirst().first

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

let delegate = AppDelegate(filePath: filePath)
app.delegate = delegate
app.run()
