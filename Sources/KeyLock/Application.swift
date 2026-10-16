import Cocoa

/// Entry point. Written as `@main` (instead of a `main.swift` top level) so the
/// whole bootstrap can be `@MainActor`-isolated, which AppKit expects.
@main
struct KeyLockApplication {

    /// Strong reference for the process lifetime — `NSApplication.delegate` is weak.
    @MainActor static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
