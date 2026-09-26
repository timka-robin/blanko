#!/usr/bin/env swift
// Turns a square 1024x1024 artwork into a proper macOS icon:
// applies the standard icon grid (rounded "squircle" 824x824 inside 1024x1024),
// a soft shadow and can emit an .iconset for `iconutil`.
//
//   tools/make-icon.swift sheet     artwork.png out.png
//   tools/make-icon.swift iconset   artwork.png AppIcon.iconset
//   tools/make-icon.swift contact   out.png artwork1.png artwork2.png ...

import AppKit
import Foundation

let canvas: CGFloat = 1024
let contentInset: CGFloat = 100          // Apple icon grid: 824 content inside 1024
let cornerExponent: CGFloat = 4.6        // superellipse approximation of the squircle

/// Continuous-curvature rounded square, sampled from a superellipse.
func squirclePath(in rect: CGRect, exponent: CGFloat = cornerExponent) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 1024
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let x = rect.midX + a * copysign(pow(abs(ct), 2 / exponent), ct)
        let y = rect.midY + b * copysign(pow(abs(st), 2 / exponent), st)
        if step == 0 {
            path.move(to: NSPoint(x: x, y: y))
        } else {
            path.line(to: NSPoint(x: x, y: y))
        }
    }
    path.close()
    return path
}

func loadArtwork(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: path) else {
        FileHandle.standardError.write("cannot open \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return image
}

/// Draws the artwork as a macOS icon of the given pixel size.
func drawIcon(artwork: NSImage, size: CGFloat) {
    let scale = size / canvas
    let rect = NSRect(
        x: contentInset * scale,
        y: contentInset * scale,
        width: (canvas - contentInset * 2) * scale,
        height: (canvas - contentInset * 2) * scale
    )
    let path = squirclePath(in: rect)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 18 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    artwork.draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high.rawValue]
    )
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: CGFloat, artwork: NSImage) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write("cannot allocate bitmap\n".data(using: .utf8)!)
        exit(1)
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    drawIcon(artwork: artwork, size: size)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("cannot encode \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    try? FileManager.default.createDirectory(
        at: URL(fileURLWithPath: path).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        FileHandle.standardError.write("cannot write \(path): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

func label(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .medium),
        .foregroundColor: color,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(at: point)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: make-icon.swift sheet|iconset <artwork.png> <output>")
    print("       make-icon.swift contact <output.png> <artwork1.png> ...")
    exit(2)
}

switch arguments[1] {
case "sheet":
    let artwork = loadArtwork(arguments[2])
    writePNG(render(size: canvas, artwork: artwork), to: arguments[3])
    print("wrote \(arguments[3])")

case "iconset":
    let artwork = loadArtwork(arguments[2])
    let directory = arguments[3]
    let variants: [(String, CGFloat)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, size) in variants {
        writePNG(render(size: size, artwork: artwork), to: "\(directory)/\(name).png")
    }
    print("wrote iconset \(directory)")

case "contact":
    let output = arguments[2]
    let artworks = arguments.dropFirst(3).map(loadArtwork)
    let columns = min(3, artworks.count)
    let rows = Int(ceil(Double(artworks.count) / Double(columns)))
    let cellWidth: CGFloat = 420
    let cellHeight: CGFloat = 470
    let bigSize: CGFloat = 330
    let smallSizes: [CGFloat] = [72, 36, 18]
    let margin: CGFloat = 44
    let headerHeight: CGFloat = 74

    let width = CGFloat(columns) * cellWidth
    let height = CGFloat(rows) * cellHeight + headerHeight

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width),
        pixelsHigh: Int(height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let sheetColour = NSColor(calibratedWhite: 0.96, alpha: 1)
    sheetColour.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    for (index, artwork) in artworks.enumerated() {
        let column = index % columns
        let row = index / columns
        let originX = CGFloat(column) * cellWidth
        let blockTop = height - CGFloat(row) * cellHeight - 34

        label(
            "\(index + 1)",
            at: NSPoint(x: originX + 14, y: blockTop - 28),
            size: 30,
            color: NSColor(calibratedWhite: 0.25, alpha: 1)
        )

        let bigY = blockTop - 50 - bigSize
        NSGraphicsContext.saveGraphicsState()
        let bigTransform = NSAffineTransform()
        bigTransform.translateX(by: originX + margin, yBy: bigY)
        bigTransform.concat()
        drawIcon(artwork: artwork, size: bigSize)
        NSGraphicsContext.restoreGraphicsState()

        var smallX = originX + margin
        for size in smallSizes {
            NSGraphicsContext.saveGraphicsState()
            let smallTransform = NSAffineTransform()
            smallTransform.translateX(by: smallX, yBy: bigY - 52)
            smallTransform.concat()
            drawIcon(artwork: artwork, size: size)
            NSGraphicsContext.restoreGraphicsState()
            smallX += size + 14
        }
    }

    label(
        "Blanko — варианты иконки. Под каждым: 72 / 36 / 18 px",
        at: NSPoint(x: 24, y: 22),
        size: 24,
        color: NSColor(calibratedWhite: 0.3, alpha: 1)
    )
    NSGraphicsContext.restoreGraphicsState()

    writePNG(rep, to: output)
    print("wrote \(output)")

default:
    FileHandle.standardError.write("unknown command \(arguments[1])\n".data(using: .utf8)!)
    exit(2)
}
