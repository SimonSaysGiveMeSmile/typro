import Cocoa
import ApplicationServices

enum PermissionsHelper {
    static func accessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    static func promptForAccessibility() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(opts)

        let alert = NSAlert()
        alert.messageText = "Typro needs Accessibility access"
        alert.informativeText = """
        Typro watches keystrokes to detect typos and auto-selects the wrong part of a word so you can delete it with one tap.

        Open System Settings → Privacy & Security → Accessibility, and enable Typro in the list. Then relaunch Typro.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
