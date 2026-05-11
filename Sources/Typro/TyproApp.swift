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
}
