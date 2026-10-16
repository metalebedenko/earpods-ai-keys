#!/usr/bin/swift
import AppKit
import Foundation

// Original Finder-window background, drawn entirely with native AppKit.
// No app/folder pictures are embedded: Finder supplies the actual two icons.
// Usage from the project root:
// /usr/bin/swift app/Tools/GenerateDMGBackground.swift app/Resources/DMG
// Canvas: 720 × 450 logical points. Coordinates below are from the top left.
// Finder icon centres: app (190, 245), Applications alias (530, 245).
// Suggested Finder icon size: 128 points; labels stay below the empty icon areas.

let canvas = NSSize(width: 720, height: 450)

struct BackgroundError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

func point(_ x: CGFloat, _ yFromTop: CGFloat) -> NSPoint {
    NSPoint(x: x, y: canvas.height-yFromTop)
}

func centeredText(_ value: String, top: CGFloat, height: CGFloat, font: NSFont, tint: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: tint, .paragraphStyle: paragraph
    ]
    NSAttributedString(string: value, attributes: attributes).draw(
        in: NSRect(x: 40, y: canvas.height-top-height, width: canvas.width-80, height: height)
    )
}

func drawBackground() {
    let backdrop = NSBezierPath(rect: NSRect(origin: .zero, size: canvas))
    NSGradient(colors: [color(0.956, 0.970, 0.991), color(0.985, 0.990, 0.998)])!
        .draw(in: backdrop, angle: 90)

    centeredText("EarPods AI Keys", top: 51, height: 40,
                 font: .systemFont(ofSize: 30, weight: .semibold), tint: color(0.10, 0.29, 0.72))
    centeredText("Перетащите в «Программы»", top: 105, height: 28,
                 font: .systemFont(ofSize: 18), tint: color(0.33, 0.38, 0.47))

    let arrow = NSBezierPath()
    arrow.move(to: point(304, 245))
    arrow.line(to: point(416, 245))
    arrow.move(to: point(406, 238))
    arrow.line(to: point(416, 245))
    arrow.line(to: point(406, 252))
    arrow.lineWidth = 1.8
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0.29, 0.49, 0.80).setStroke()
    arrow.stroke()
}

func png(scale: Int) throws -> Data {
    let width = Int(canvas.width)*scale
    let height = Int(canvas.height)*scale
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw BackgroundError(message: "Could not create the DMG background bitmap.")
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    drawBackground()
    context.flushGraphics()
    bitmap.size = canvas
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw BackgroundError(message: "Could not encode the DMG background PNG.")
    }
    return data
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw BackgroundError(message: "Usage: /usr/bin/swift app/Tools/GenerateDMGBackground.swift <output-directory>")
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // 1× is the unambiguous 720×450 Finder background. The second file is a
    // Retina preview of the same layout, with the same encoded logical size.
    try png(scale: 1).write(to: directory.appendingPathComponent("background.png"), options: .atomic)
    try png(scale: 2).write(to: directory.appendingPathComponent("background-preview.png"), options: .atomic)
} catch {
    fputs(error.localizedDescription+"\n", stderr)
    exit(1)
}
