import Cocoa
import ApplicationServices

enum Permissions {

    /// Accessibility (a.k.a. "Универсальный доступ") is what allows a `CGEventTap`
    /// to *modify or suppress* input. Without it `CGEvent.tapCreate` returns nil.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system to show the "grant Accessibility" prompt. The prompt appears
    /// at most once per app identity, so we also offer a direct jump to Settings.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Best-effort detection of whether the running bundle lives in /Applications.
    static var isInstalledInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }
}
