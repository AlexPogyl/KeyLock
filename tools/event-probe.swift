// Diagnostic: logs every CGEvent type that reaches a HID-level tap, so we can see
// what (if anything) the Touch Bar's touches turn into.
//
//   swift tools/event-probe.swift [seconds] [output-file]
import Cocoa
import CoreGraphics
import Foundation

enum Probe {
    static let names: [CGEventType: String] = [
        .null: "null", .leftMouseDown: "leftMouseDown", .leftMouseUp: "leftMouseUp",
        .rightMouseDown: "rightMouseDown", .rightMouseUp: "rightMouseUp",
        .mouseMoved: "mouseMoved", .leftMouseDragged: "leftMouseDragged",
        .rightMouseDragged: "rightMouseDragged", .keyDown: "keyDown", .keyUp: "keyUp",
        .flagsChanged: "flagsChanged", .scrollWheel: "scrollWheel",
        .tabletPointer: "tabletPointer", .tabletProximity: "tabletProximity",
        .otherMouseDown: "otherMouseDown", .otherMouseUp: "otherMouseUp",
        .otherMouseDragged: "otherMouseDragged",
        CGEventType(rawValue: 14)!: "systemDefined",
        CGEventType(rawValue: 15)!: "appKitDefined",
        CGEventType(rawValue: 16)!: "applicationDefined",
        CGEventType(rawValue: 17)!: "periodic",
        CGEventType(rawValue: 18)!: "cursorUpdate",
        CGEventType(rawValue: 29)!: "dockControl",
        CGEventType(rawValue: 30)!: "docked",
    ]

    static let noisy: Set<CGEventType> = [.mouseMoved, .flagsChanged, .null]
    static var counts: [CGEventType: Int] = [:]
    static var systemDefinedSubtypes: [Int64: Int] = [:]
    static var handle: FileHandle?

    static func log(_ text: String) {
        handle?.write((text + "\n").data(using: .utf8)!)
        try? handle?.synchronize()
    }
}

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 30 : 30
let outputPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/event-probe.log"
FileManager.default.createFile(atPath: outputPath, contents: nil)
Probe.handle = FileHandle(forWritingAtPath: outputPath)

let mask: CGEventMask = (1 << 32) - 1
let callback: CGEventTapCallBack = { _, type, event, _ in
    Probe.counts[type, default: 0] += 1
    if type.rawValue == 14 {
        let subtype = event.getIntegerValueField(.eventSourceUserData)
        Probe.systemDefinedSubtypes[subtype, default: 0] += 1
    }
    if !Probe.noisy.contains(type) {
        Probe.log("t=\(String(format: "%.2f", CACurrentMediaTime())) type=\(type.rawValue) \(Probe.names[type] ?? "?") flags=\(event.flags.rawValue)")
    }
    return Unmanaged.passUnretained(event)
}

guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                  options: .defaultTap, eventsOfInterest: mask,
                                  callback: callback, userInfo: nil) else {
    Probe.log("could not create tap")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
Probe.log("probing for \(seconds)s")

let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
    CFRunLoopRunInMode(.defaultMode, 0.25, false)
}

Probe.log("=== summary ===")
for (type, count) in Probe.counts.sorted(by: { $0.value > $1.value }) {
    Probe.log("\(Probe.names[type] ?? "type \(type.rawValue)"): \(count)")
}
Probe.log("=== systemDefined subtypes ===")
for (subtype, count) in Probe.systemDefinedSubtypes.sorted(by: { $0.value > $1.value }) {
    Probe.log("subtype \(subtype): \(count)")
}
