#!/usr/bin/env swift
//
// Renders the KeyLock app icon:
//   a graphite "liquid glass" squircle with a white padlock and a keyhole.
//
// Usage: swift scripts/make-icon.swift <output-directory>
//
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "Resources/icon.iconset")

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()

func drawIcon(size: CGFloat) -> CGImage? {
    let pixels = Int(size)
    guard let ctx = CGContext(data: nil,
                              width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    let s = size
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // ---------------------------------------------------------------- squircle
    let inset = s * 0.055
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.238
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Graphite glass gradient
    let bg = CGGradient(colorsSpace: colorSpace, colors: [
        rgb(150, 154, 162), rgb(88, 91, 98), rgb(46, 48, 53), rgb(30, 31, 35),
    ] as CFArray, locations: [0.0, 0.42, 0.82, 1.0])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Specular sheen in the upper-left corner
    let sheen = CGGradient(colorsSpace: colorSpace, colors: [
        rgb(255, 255, 255, 0.30), rgb(255, 255, 255, 0.05), rgb(255, 255, 255, 0.0),
    ] as CFArray, locations: [0.0, 0.5, 1.0])!
    ctx.drawRadialGradient(sheen,
                           startCenter: CGPoint(x: body.minX + body.width * 0.22,
                                                y: body.maxY - body.height * 0.16),
                           startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.midY),
                           endRadius: body.width * 0.95, options: [])

    // Cool bottom glow so the glass has depth
    let glow = CGGradient(colorsSpace: colorSpace, colors: [
        rgb(120, 170, 230, 0.22), rgb(120, 170, 230, 0.0),
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: body.midX, y: body.minY + body.height * 0.08),
                           startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.midY),
                           endRadius: body.width * 0.8, options: [])
    ctx.restoreGState()

    // ------------------------------------------------------------- padlock part
    let centerX = s / 2

    // Lock body geometry
    let lockW = s * 0.44
    let lockH = s * 0.335
    let lockBottom = s * 0.235
    let lockRect = CGRect(x: centerX - lockW / 2, y: lockBottom, width: lockW, height: lockH)
    let lockRadius = lockW * 0.20
    let lockPath = CGPath(roundedRect: lockRect, cornerWidth: lockRadius,
                          cornerHeight: lockRadius, transform: nil)

    // Shackle geometry
    let shackleRadius = lockW * 0.30
    let shackleWidth = lockW * 0.155
    let shackleCenterY = lockRect.maxY + s * 0.012

    // Shadow under the whole padlock
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                  blur: s * 0.035, color: rgb(0, 0, 0, 0.45))
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: centerX, y: shackleCenterY), radius: shackleRadius,
               startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.setLineWidth(shackleWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(238, 241, 246))
    ctx.strokePath()

    ctx.addPath(lockPath)
    ctx.setFillColor(rgb(244, 246, 250))
    ctx.fillPath()
    ctx.restoreGState()

    // Shackle gloss: slightly darker band on the inner side
    ctx.saveGState()
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: centerX, y: shackleCenterY), radius: shackleRadius,
               startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.setLineWidth(shackleWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(255, 255, 255))
    ctx.strokePath()
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: centerX, y: shackleCenterY), radius: shackleRadius - shackleWidth * 0.26,
               startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.setLineWidth(shackleWidth * 0.28)
    ctx.setStrokeColor(rgb(160, 168, 180, 0.55))
    ctx.strokePath()
    ctx.restoreGState()

    // Vertical gloss on the lock body
    ctx.saveGState()
    ctx.addPath(lockPath)
    ctx.clip()
    let bodyGloss = CGGradient(colorsSpace: colorSpace, colors: [
        rgb(255, 255, 255), rgb(226, 231, 239), rgb(190, 197, 209),
    ] as CFArray, locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(bodyGloss,
                           start: CGPoint(x: lockRect.minX, y: lockRect.maxY),
                           end: CGPoint(x: lockRect.minX, y: lockRect.minY), options: [])
    ctx.restoreGState()

    // ---------------------------------------------------------------- keyhole
    let keyholeColor = rgb(48, 51, 58)
    let holeRadius = lockW * 0.115
    let holeCenter = CGPoint(x: centerX, y: lockRect.midY + lockH * 0.08)
    ctx.setFillColor(keyholeColor)
    ctx.fillEllipse(in: CGRect(x: holeCenter.x - holeRadius, y: holeCenter.y - holeRadius,
                               width: holeRadius * 2, height: holeRadius * 2))

    let slotW = holeRadius * 0.92
    let slotTop = holeCenter.y
    let slotBottom = lockRect.minY + lockH * 0.22
    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: holeCenter.x - slotW / 2, y: slotBottom))
    slot.addLine(to: CGPoint(x: holeCenter.x + slotW / 2, y: slotBottom))
    slot.addLine(to: CGPoint(x: holeCenter.x + holeRadius * 0.62, y: slotTop))
    slot.addLine(to: CGPoint(x: holeCenter.x - holeRadius * 0.62, y: slotTop))
    slot.closeSubpath()
    ctx.addPath(slot)
    ctx.fillPath()

    // Soft inner vignette at the very top so the slab reads as a lit pane of glass.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let vignette = CGGradient(colorsSpace: colorSpace, colors: [
        rgb(0, 0, 0, 0.30), rgb(0, 0, 0, 0.0),
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(vignette,
                           start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.maxY - body.height * 0.22),
                           options: [])
    ctx.restoreGState()

    // ------------------------------------------------------------ glass rim
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setLineWidth(max(1, s * 0.008))
    ctx.setStrokeColor(rgb(255, 255, 255, 0.30))
    ctx.strokePath()

    ctx.addPath(squircle)
    ctx.clip()
    let rim = CGGradient(colorsSpace: colorSpace, colors: [
        rgb(255, 255, 255, 0.38), rgb(255, 255, 255, 0.06), rgb(0, 0, 0, 0.22),
    ] as CFArray, locations: [0.0, 0.55, 1.0])!
    ctx.setLineWidth(s * 0.02)
    ctx.addPath(squircle)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(rim,
                           start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    ctx.restoreGState()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "icon", code: 1) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 2) }
}

let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    guard let image = drawIcon(size: variant.size) else {
        FileHandle.standardError.write("failed to render \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try write(image, to: outDir.appendingPathComponent(variant.name))
}

// A 1024px master for the README / GitHub social preview.
if let master = drawIcon(size: 1024) {
    try write(master, to: outDir.appendingPathComponent("icon-preview.png"))
}

print("iconset written to \(outDir.path)")
