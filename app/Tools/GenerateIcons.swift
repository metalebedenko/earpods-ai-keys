#!/usr/bin/swift
import AppKit
import Foundation

// Original geometric artwork for EarPods AI Keys. The two wired earpieces and
// three-button remote are drawn from these paths, with no imported images,
// SF Symbols, Apple hardware silhouettes or external rendering dependencies.
// Usage: /usr/bin/swift app/Tools/GenerateIcons.swift app/Resources

struct IconError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

let fileManager = FileManager.default

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func stroke(_ path: NSBezierPath, width: CGFloat, color: NSColor) {
    color.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func withTransform(translate: NSPoint = .zero, scale: CGFloat = 1, rotate: CGFloat = 0, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let transform = NSAffineTransform()
    transform.translateX(by: translate.x, yBy: translate.y)
    transform.scale(by: scale)
    transform.rotate(byDegrees: rotate)
    transform.concat()
    draw()
}

// Filled, deliberately abstract oval earpieces; the small grille is decorative.
// Coordinates are in a 100-point canvas, with the earpiece origin at its base.
func drawEarpiece(at origin: NSPoint, angle: CGFloat, compact: Bool) {
    withTransform(translate: origin, rotate: angle) {
        NSColor.white.setFill()
        rounded(NSRect(x: -3.1, y: -12, width: 6.2, height: 17), radius: 3.1).fill()
        NSBezierPath(ovalIn: NSRect(x: -8.4, y: -0.5, width: 16.8, height: 19.4)).fill()
        if !compact {
            color(0.09, 0.31, 0.66).setFill()
            rounded(NSRect(x: -3, y: 6.2, width: 6, height: 7.2), radius: 3).fill()
            color(0.36, 0.61, 0.88).setFill()
            rounded(NSRect(x: -1.1, y: 7.6, width: 2.2, height: 4.4), radius: 1.1).fill()
        }
    }
}

func drawAppIcon(pixelSize: Int) {
    let compact = pixelSize < 64
    let background = rounded(NSRect(x: 7.4, y: 7.4, width: 85.2, height: 85.2), radius: 20.5)
    let gradient = NSGradient(colors: [color(0.10, 0.29, 0.72), color(0.15, 0.53, 0.91)])!
    gradient.draw(in: background, angle: 90)
    stroke(rounded(NSRect(x: 8, y: 8, width: 84, height: 84), radius: 20),
           width: 0.8, color: color(1, 1, 1, 0.13))

    let cable = NSBezierPath()
    cable.move(to: NSPoint(x: 26.5, y: 55.9))
    cable.curve(to: NSPoint(x: 44, y: 18.9), controlPoint1: NSPoint(x: 23.6, y: 33), controlPoint2: NSPoint(x: 24.6, y: 17.3))
    cable.curve(to: NSPoint(x: 71.8, y: 27), controlPoint1: NSPoint(x: 59.5, y: 20.2), controlPoint2: NSPoint(x: 71.8, y: 19))
    stroke(cable, width: compact ? 4 : 2.8, color: .white)
    let rightCable = NSBezierPath()
    rightCable.move(to: NSPoint(x: 67.1, y: 58.7))
    rightCable.curve(to: NSPoint(x: 71.8, y: 52), controlPoint1: NSPoint(x: 70, y: 55), controlPoint2: NSPoint(x: 71.8, y: 57))
    stroke(rightCable, width: compact ? 4 : 2.8, color: .white)

    drawEarpiece(at: NSPoint(x: 31, y: 67), angle: -22, compact: compact)
    drawEarpiece(at: NSPoint(x: 63, y: 70), angle: 20, compact: compact)

    NSColor.white.setFill()
    rounded(NSRect(x: 64.8, y: 25.7, width: 14, height: 28), radius: 7).fill()
    let controlColor = color(0.08, 0.32, 0.71)
    if !compact {
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: 69.4, y: 47.2)); plus.line(to: NSPoint(x: 74.2, y: 47.2))
        plus.move(to: NSPoint(x: 71.8, y: 44.8)); plus.line(to: NSPoint(x: 71.8, y: 49.6))
        stroke(plus, width: 1.3, color: controlColor)
        controlColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 69.3, y: 37.1, width: 5, height: 5)).fill()
        let minus = NSBezierPath()
        minus.move(to: NSPoint(x: 69.4, y: 32.1)); minus.line(to: NSPoint(x: 74.2, y: 32.1))
        stroke(minus, width: 1.3, color: controlColor)
    } else {
        controlColor.setFill()
        for y: CGFloat in [31.4, 38.9, 46.4] {
            NSBezierPath(ovalIn: NSRect(x: 69.8, y: y-2, width: 4, height: 4)).fill()
        }
    }
}

// Optical small-size variant, authored in a 22-point canvas. It keeps the cable
// loop and three control openings that distinguish this mark from generic buds.
func drawMenuIcon(tint: NSColor = .black, cutoutBackground: NSColor? = nil) {
    withTransform(translate: NSPoint(x: 1, y: 0)) {
        let cable = NSBezierPath()
        cable.move(to: NSPoint(x: 5.1, y: 12.9))
        cable.curve(to: NSPoint(x: 8.8, y: 2.7), controlPoint1: NSPoint(x: 4.1, y: 6.5), controlPoint2: NSPoint(x: 4.7, y: 2.5))
        cable.curve(to: NSPoint(x: 14.2, y: 4.8), controlPoint1: NSPoint(x: 12.1, y: 2.9), controlPoint2: NSPoint(x: 14.2, y: 2.8))
        stroke(cable, width: 1.05, color: tint)
        let shortCable = NSBezierPath()
        shortCable.move(to: NSPoint(x: 14.7, y: 13.3))
        shortCable.curve(to: NSPoint(x: 14.2, y: 12), controlPoint1: NSPoint(x: 14.7, y: 12.5), controlPoint2: NSPoint(x: 14.2, y: 12.8))
        stroke(shortCable, width: 1.05, color: tint)
        for (origin, angle) in [(NSPoint(x: 5.7, y: 15.6), CGFloat(-16)), (NSPoint(x: 13.9, y: 16), CGFloat(16))] {
            withTransform(translate: origin, rotate: angle) {
                tint.setFill()
                rounded(NSRect(x: -0.7, y: -3.2, width: 1.4, height: 4.2), radius: 0.7).fill()
                NSBezierPath(ovalIn: NSRect(x: -1.95, y: -0.2, width: 3.9, height: 4.6)).fill()
            }
        }
        tint.setFill()
        rounded(NSRect(x: 12.1, y: 4.5, width: 4.2, height: 7.8), radius: 2.1).fill()
        NSGraphicsContext.saveGraphicsState()
        if let cutoutBackground { cutoutBackground.setFill() }
        else { NSGraphicsContext.current?.cgContext.setBlendMode(.clear) }
        for y: CGFloat in [6.2, 8.4, 10.6] {
            NSBezierPath(ovalIn: NSRect(x: 13.65, y: y-0.55, width: 1.1, height: 1.1)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

func png(size: NSSize, scale: Int = 1, draw: () -> Void) throws -> Data {
    let width = Int(size.width) * scale
    let height = Int(size.height) * scale
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconError(message: "Could not create an icon bitmap.")
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.cgContext.setShouldAntialias(true)
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    draw()
    context.flushGraphics()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError(message: "Could not encode an icon PNG.")
    }
    return data
}

func appPNG(_ pixels: Int) throws -> Data {
    try png(size: NSSize(width: pixels, height: pixels)) {
        withTransform(scale: CGFloat(pixels)/100) { drawAppIcon(pixelSize: pixels) }
    }
}

func menuPreview() throws -> Data {
    try png(size: NSSize(width: 360, height: 132), scale: 2) {
        let light = color(0.96, 0.97, 0.98)
        let dark = color(0.13, 0.14, 0.17)
        light.setFill(); NSRect(x: 0, y: 66, width: 360, height: 66).fill()
        dark.setFill(); NSRect(x: 0, y: 0, width: 360, height: 66).fill()
        for (column, size) in [CGFloat(18), 20, 22].enumerated() {
            let x = CGFloat(57+column*113)
            for (y, tint, background) in [(CGFloat(101), NSColor.black, light), (CGFloat(35), NSColor.white, dark)] {
                withTransform(translate: NSPoint(x: x-size/2, y: y-size/2), scale: size/22) {
                    drawMenuIcon(tint: tint, cutoutBackground: background)
                }
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: tint]
                NSString(string: "\(Int(size)) pt").draw(at: NSPoint(x: x-12, y: y-28), withAttributes: attributes)
            }
        }
    }
}

func generate(to resources: URL) throws {
    let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    let previews = resources.appendingPathComponent("previews", isDirectory: true)
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: previews, withIntermediateDirectories: true)
    let slots = [("icon_16x16.png",16), ("icon_16x16@2x.png",32),
                 ("icon_32x32.png",32), ("icon_32x32@2x.png",64),
                 ("icon_128x128.png",128), ("icon_128x128@2x.png",256),
                 ("icon_256x256.png",256), ("icon_256x256@2x.png",512),
                 ("icon_512x512.png",512), ("icon_512x512@2x.png",1024)]
    for (name, pixels) in slots { try appPNG(pixels).write(to: iconset.appendingPathComponent(name), options: .atomic) }
    try png(size: NSSize(width: 22, height: 22)) { drawMenuIcon() }
        .write(to: resources.appendingPathComponent("MenuIconTemplate.png"), options: .atomic)
    try png(size: NSSize(width: 22, height: 22), scale: 2) { drawMenuIcon() }
        .write(to: resources.appendingPathComponent("MenuIconTemplate@2x.png"), options: .atomic)
    try appPNG(1024).write(to: previews.appendingPathComponent("AppIcon-1024.png"), options: .atomic)
    try menuPreview().write(to: previews.appendingPathComponent("MenuIconPreview.png"), options: .atomic)

    let tool = Process()
    let errors = Pipe()
    tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    tool.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
    tool.standardError = errors
    try tool.run()
    tool.waitUntilExit()
    guard tool.terminationStatus == 0 else {
        let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw IconError(message: "iconutil failed: " + detail)
    }
}

do {
    guard CommandLine.arguments.count == 2 else { throw IconError(message: "Usage: /usr/bin/swift app/Tools/GenerateIcons.swift <resources-directory>") }
    try generate(to: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
} catch {
    fputs(error.localizedDescription + "\n", stderr)
    exit(1)
}
