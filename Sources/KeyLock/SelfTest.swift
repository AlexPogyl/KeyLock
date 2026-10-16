import Cocoa
import Carbon.HIToolbox

/// Headless end-to-end test of the safety-critical path, driven by *synthetic*
/// events so it can run without touching the real keyboard.
///
/// Covers, in this order:
///   1. Accessibility / event tap availability
///   2. capturing the unlock combination (the mandatory verification step)
///   3. suppressing ordinary keys while "blocked"
///   4. releasing the block with the unlock combination
///   5. releasing the block with the emergency Escape×5 sequence
///   6. seizing and releasing the built-in trackpad
///
/// Every blocking stage is wrapped in a watchdog that force-unlocks and exits,
/// so a failure can never leave the machine with a dead keyboard.
@MainActor
enum SelfTest {

    private static var failures: [String] = []

    static func run(controller: LockController) {
        log("=== KeyLock self-test ===")
        log("accessibility trusted: \(Permissions.isAccessibilityGranted)")

        guard Permissions.isAccessibilityGranted else {
            log("FAIL: no Accessibility permission — cannot create an event tap")
            finish()
            return
        }

        guard EventTap.shared.install(), EventTap.shared.isEnabled else {
            log("FAIL: event tap could not be installed")
            finish()
            return
        }
        log("PASS: event tap installed and enabled")

        let combo = controller.unlockCombo
        log("unlock combination: \(combo.display)  (keyCode \(combo.keyCode))")

        // ---- 2. capture ----------------------------------------------------
        step("capture the combination (verification)")
        EventTap.shared.setMode(.capture)
        post(combo)
        after(0.4) {
            check("combination captured", EventTap.shared.mode == .idle)
            EventTap.shared.setMode(.idle)

            // ---- 3. suppression ------------------------------------------
            step("block the keyboard and swallow a normal key")
            let before = EventTap.shared.suppressedEventCount
            EventTap.shared.blockKeyboard = true
            EventTap.shared.blockPointer = false
            EventTap.shared.setMode(.blocking)
            watchdog(seconds: 6)
            post(key: UInt16(kVK_ANSI_A), mods: [])

            after(0.4) {
                check("normal key suppressed while blocked",
                      EventTap.shared.suppressedEventCount > before)
                check("still in blocking mode", EventTap.shared.mode == .blocking)

                // ---- 4. unlock by combination ----------------------------
                step("unlock with the combination")
                post(combo)
                after(0.4) {
                    check("unlocked by combination", EventTap.shared.mode == .idle)
                    EventTap.shared.blockKeyboard = false

                    // ---- 5. emergency Escape x5 --------------------------
                    step("unlock with the emergency Escape×5 sequence")
                    EventTap.shared.blockKeyboard = true
                    EventTap.shared.setMode(.blocking)
                    for _ in 0..<5 { post(key: UInt16(kVK_Escape), mods: []) }
                    after(0.4) {
                        check("unlocked by Escape×5", EventTap.shared.mode == .idle)
                        EventTap.shared.blockKeyboard = false
                        EventTap.shared.setMode(.idle)

                        // ---- 6. pointer suppression ----------------------
                        step("pointer suppression (trackpad / mouse)")
                        let beforePointer = EventTap.shared.suppressedEventCount
                        EventTap.shared.blockKeyboard = false
                        EventTap.shared.blockPointer = true
                        EventTap.shared.setMode(.blocking)
                        watchdog(seconds: 5)
                        postMouseMove()
                        after(0.3) {
                            check("pointer event suppressed while blocked",
                                  EventTap.shared.suppressedEventCount > beforePointer)

                            // ---- 6b. cursor pinning ----------------------
                            step("cursor pinning (the trackpad must feel dead)")
                            let origin = CGEvent(source: nil)?.location ?? .zero
                            EventTap.shared.blockPointer = true
                            EventTap.shared.frozenCursorPosition = origin
                            EventTap.shared.setMode(.blocking)
                            // Pretend the window server already applied a swipe.
                            CGWarpMouseCursorPosition(CGPoint(x: origin.x + 240, y: origin.y + 180))
                            postMouseMove(to: CGPoint(x: origin.x + 240, y: origin.y + 180))
                            after(0.3) {
                                let now = CGEvent(source: nil)?.location ?? .zero
                                check("cursor was pinned back",
                                      abs(now.x - origin.x) < 3 && abs(now.y - origin.y) < 3)
                                CGWarpMouseCursorPosition(origin)
                                EventTap.shared.frozenCursorPosition = nil
                                EventTap.shared.blockPointer = false
                                EventTap.shared.setMode(.idle)

                                // ---- 7. Touch Bar ----------------------------
                                step("Touch Bar (system-defined events)")
                                let beforeTouchBar = EventTap.shared.suppressedEventCount
                                EventTap.shared.blockTouchBar = true
                                EventTap.shared.setMode(.blocking)
                                watchdog(seconds: 5)
                                postSystemDefined()
                                after(0.3) {
                                    check("system-defined (Touch Bar) event suppressed",
                                          EventTap.shared.suppressedEventCount > beforeTouchBar)
                                    EventTap.shared.blockTouchBar = false
                                    EventTap.shared.setMode(.idle)

                                    if TouchBarController.shared.isAvailable {
                                        let ok = TouchBarController.shared.block()
                                        check("Touch Bar DFR status applied (best effort)", ok)
                                        TouchBarController.shared.unblock()
                                    } else {
                                        log("SKIP: DFRFoundation unavailable on this machine")
                                    }

                                    // ---- 8. tap placement --------------------
                                    log("event tap level: \(EventTap.shared.isHIDLevel ? "HID" : "session")")
                                    check("event tap is HID level (can freeze the cursor)",
                                          EventTap.shared.isHIDLevel)

                                    finish()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func step(_ text: String) { log("\n-- \(text)") }

    private static func check(_ name: String, _ condition: Bool) {
        log(condition ? "PASS: \(name)" : "FAIL: \(name)")
        if !condition { failures.append(name) }
    }

    private static func log(_ text: String) {
        FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    }

    private static func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { block() }
        }
    }

    /// Hard safety net: never allow the self-test to hold input for long.
    private static func watchdog(seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard EventTap.shared.mode == .blocking else { return }
            log("WATCHDOG: forcing unlock")
            EventTap.shared.blockKeyboard = false
            EventTap.shared.blockPointer = false
            EventTap.shared.setMode(.idle)
            TouchBarController.shared.unblock()
            failures.append("watchdog fired")
            finish()
        }
    }

    private static func post(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: combo.keyCode, keyDown: isDown) else { continue }
            event.flags = combo.flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// A synthetic `kCGEventSystemDefined` event, the shape the Touch Bar uses.
    private static func postSystemDefined() {
        guard let event = CGEvent(source: CGEventSource(stateID: .hidSystemState)) else { return }
        event.type = kSystemDefinedEventType
        event.post(tap: .cghidEventTap)
    }

    private static func postMouseMove(to point: CGPoint = CGPoint(x: 600, y: 400)) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                            mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    private static func post(key: UInt16, mods: Set<Mod>) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            else { continue }
            event.flags = mods.reduce(into: CGEventFlags()) { $0.formUnion($1.flag) }
            event.post(tap: .cghidEventTap)
        }
    }

    private static func finish() {
        EventTap.shared.blockKeyboard = false
        EventTap.shared.blockPointer = false
        EventTap.shared.setMode(.idle)
        TouchBarController.shared.unblock()

        if failures.isEmpty {
            log("\n=== RESULT: ALL CHECKS PASSED ===")
            exit(0)
        } else {
            log("\n=== RESULT: \(failures.count) FAILURE(S): \(failures.joined(separator: ", ")) ===")
            exit(1)
        }
    }
}
