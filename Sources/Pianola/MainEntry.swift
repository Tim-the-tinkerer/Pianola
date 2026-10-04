import AppKit
import SwiftUI

@main
struct MainEntry {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            exit(PianolaSelfTest.run())
        }
        let app = NSApplication.shared
        let delegate = AppDelegate.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var window: NSWindow?
    private var pendingURLs: [URL] = []

    private let minSize = NSSize(width: 860, height: 580)
    private let defaultSize = NSSize(width: 1020, height: 680)

    private override init() {
        super.init()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        buildMainMenu()
        showMainWindow()
        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            DispatchQueue.main.async {
                for url in urls {
                    NotificationCenter.default.post(name: .pianolaOpenURL, object: url)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        urls.forEach { open($0) }
    }

    private func open(_ url: URL) {
        if window == nil {
            pendingURLs.append(url)
            return
        }
        NotificationCenter.default.post(name: .pianolaOpenURL, object: url)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ContentView(engine: MIDIEngine.shared)
            .frame(minWidth: minSize.width, minHeight: minSize.height)

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: defaultSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pianola"
        window.contentView = hosting
        window.setContentSize(defaultSize)
        window.contentMinSize = minSize
        window.isRestorable = false
        window.setFrameAutosaveName("PianolaMain")
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    @objc private func showAbout(_ sender: Any?) {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        let versionLine: String
        switch (short, build) {
        case let (s?, b?): versionLine = "Version \(s) (\(b))"
        case let (s?, nil): versionLine = "Version \(s)"
        default: versionLine = "Version 1.0.0"
        }
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Pianola",
            .version: build ?? "1",
            .applicationVersion: versionLine,
            .credits: NSAttributedString(
                string: """
                A MIDI file player with a live piano roll and keyboard.

                Open Standard MIDI files (.mid), watch notes light up as they play, \
                and drop in your own sequences. Bundled with two C major scale studies.

                Uses the macOS General MIDI DLS synth. As written plays Theremin when the file names that instrument.
                """,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func openDocument(_ sender: Any?) {
        NotificationCenter.default.post(name: .pianolaOpenPanel, object: nil)
    }

    @objc private func togglePlay(_ sender: Any?) {
        NotificationCenter.default.post(name: .pianolaTogglePlay, object: nil)
    }

    @objc private func stopPlayback(_ sender: Any?) {
        NotificationCenter.default.post(name: .pianolaStop, object: nil)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About Pianola",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Hide Pianola",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit Pianola",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(
            withTitle: "Open…",
            action: #selector(openDocument(_:)),
            keyEquivalent: "o"
        )
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let controlsMenuItem = NSMenuItem()
        mainMenu.addItem(controlsMenuItem)
        let controlsMenu = NSMenu(title: "Controls")
        controlsMenuItem.submenu = controlsMenu
        let playItem = controlsMenu.addItem(
            withTitle: "Play/Pause",
            action: #selector(togglePlay(_:)),
            keyEquivalent: " "
        )
        playItem.keyEquivalentModifierMask = []
        controlsMenu.addItem(
            withTitle: "Stop",
            action: #selector(stopPlayback(_:)),
            keyEquivalent: "."
        )

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
