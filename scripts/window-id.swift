#!/usr/bin/env swift
// Prints "<windowId> <x> <y> <w> <h>" for every on-screen window of a given owner.
// Usage: swift scripts/window-id.swift <owner-name>
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "KeyLock"
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for window in list {
    guard let windowOwner = window[kCGWindowOwnerName as String] as? String, windowOwner == owner,
          let number = window[kCGWindowNumber as String] as? Int,
          let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
          let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
    print("\(number) \(Int(rect.origin.x)) \(Int(rect.origin.y)) \(Int(rect.width)) \(Int(rect.height))")
}
