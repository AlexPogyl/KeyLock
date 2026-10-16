import Foundation
import IOKit

/// Best-effort control of the Touch Bar (the "Dynamic Function Row").
///
/// The Touch Bar is driven by `/System/Library/PrivateFrameworks/DFRFoundation.framework`.
/// `DFRSetStatus(0)` asks the system to hide the row; restoring the previously
/// reported status brings it back. The keyboard half of the lock additionally
/// swallows the Touch Bar's own HID key events, because the row reports its
/// touches through a virtual keyboard device (`TouchBarUserDevice`).
final class TouchBarController {

    static let shared = TouchBarController()

    typealias SetStatus = @convention(c) (Int32) -> Void
    typealias GetStatus = @convention(c) () -> Int32

    private var setStatus: SetStatus?
    private var getStatus: GetStatus?
    private var savedStatus: Int32?

    private(set) var isAvailable = false
    private(set) var isBlocked = false

    private init() {
        let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        guard let setSymbol = dlsym(handle, "DFRSetStatus"),
              let getSymbol = dlsym(handle, "DFRGetStatus") else { return }
        setStatus = unsafeBitCast(setSymbol, to: SetStatus.self)
        getStatus = unsafeBitCast(getSymbol, to: GetStatus.self)
        isAvailable = true
    }

    @discardableResult
    func block() -> Bool {
        guard let setStatus, let getStatus else { return false }
        if !isBlocked { savedStatus = getStatus() }
        setStatus(0)
        isBlocked = true
        return true
    }

    func unblock() {
        guard let setStatus, isBlocked else { return }
        setStatus(1)
        savedStatus = nil
        isBlocked = false
    }
}
