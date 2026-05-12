import Cocoa
import SwiftUI

@main
struct TyproApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var engine: TypoEngine!
    private var prefsWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private var logTailer: LogTailer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TyproSettings.shared.bootstrap()
        engine = TypoEngine()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildStatusItem()

        TyproSettings.shared.onChange = { [weak self] in
            self?.rebuildStatusItem()
            self?.engine.settingsChanged()
        }

        if PermissionsHelper.accessibilityGranted() {
            engine.start()
        } else {
            PermissionsHelper.promptForAccessibility()
        }
    }

    private func rebuildStatusItem() {
        guard let button = statusItem.button else { return }
        let enabled = TyproSettings.shared.enabled
        let symbol = enabled ? "text.badge.checkmark" : "text.badge.xmark"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Typro")
        button.image?.isTemplate = true

        let menu = NSMenu()
        let toggleTitle = enabled ? "Pause Typro" : "Resume Typro"
        menu.addItem(withTitle: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(withTitle: "Dashboard…", action: #selector(openDashboard), keyEquivalent: "d")
        menu.addItem(withTitle: "Show Correction Log", action: #selector(showCorrectionLog), keyEquivalent: "")
        menu.addItem(withTitle: "Check Accessibility Permission", action: #selector(checkPermissions), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Typro", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        TyproSettings.shared.enabled.toggle()
    }

    @objc private func checkPermissions() {
        if PermissionsHelper.accessibilityGranted() {
            engine.start()
        } else {
            PermissionsHelper.promptForAccessibility()
        }
    }

    @objc private func openDashboard() {
        if dashboardWindow == nil {
            let tailer = LogTailer()
            tailer.start()
            logTailer = tailer
            let hosting = NSHostingController(rootView: DashboardView(tailer: tailer))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Typro Dashboard"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openPreferences() {
        if prefsWindow == nil {
            let view = PreferencesView()
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Typro Preferences"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 460, height: 420))
            window.isReleasedWhenClosed = false
            window.center()
            prefsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showCorrectionLog() {
        let url = CorrectionLog.shared.fileURLForDisplay
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
