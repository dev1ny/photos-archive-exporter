#!/usr/bin/env swift
import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("PhotosArchiveExporter.icns", isDirectory: false)

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct IconOutput {
    let filename: String
    let pixels: Int
}

let outputs = [
    IconOutput(filename: "icon_16x16.png", pixels: 16),
    IconOutput(filename: "icon_16x16@2x.png", pixels: 32),
    IconOutput(filename: "icon_32x32.png", pixels: 32),
    IconOutput(filename: "icon_32x32@2x.png", pixels: 64),
    IconOutput(filename: "icon_128x128.png", pixels: 128),
    IconOutput(filename: "icon_128x128@2x.png", pixels: 256),
    IconOutput(filename: "icon_256x256.png", pixels: 256),
    IconOutput(filename: "icon_256x256@2x.png", pixels: 512),
    IconOutput(filename: "icon_512x512.png", pixels: 512),
    IconOutput(filename: "icon_512x512@2x.png", pixels: 1024)
]

for output in outputs {
    let representation = drawIcon(size: output.pixels)
    guard let png = representation.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode \(output.filename)"])
    }
    try png.write(to: iconsetURL.appendingPathComponent(output.filename, isDirectory: false), options: [.atomic])
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print(icnsURL.path)

func drawIcon(size: Int) -> NSBitmapImageRep {
    let canvas = CGFloat(size)
    let scale = canvas / 1024.0
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not allocate icon bitmap.")
    }
    representation.size = NSSize(width: canvas, height: canvas)

    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        fatalError("Could not create icon graphics context.")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    func radius(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

    let baseRect = rect(58, 58, 908, 908)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: radius(212), yRadius: radius(212))
    NSGraphicsContext.saveGraphicsState()
    let baseShadow = NSShadow()
    baseShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    baseShadow.shadowBlurRadius = radius(32)
    baseShadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    baseShadow.set()
    NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.13, alpha: 1).setFill()
    basePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.09, green: 0.19, blue: 0.27, alpha: 1),
            NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.12, alpha: 1)
        ]
    )?.draw(in: basePath, angle: 90)

    let glowPath = NSBezierPath(ovalIn: rect(145, 610, 740, 300))
    NSColor(calibratedRed: 0.06, green: 0.73, blue: 0.84, alpha: 0.16).setFill()
    glowPath.fill()

    drawPhoto(rect: rect(252, 354, 456, 356), rotationDegrees: -9, scale: scale, imageColor: NSColor(calibratedRed: 0.26, green: 0.48, blue: 0.58, alpha: 1))
    drawPhoto(rect: rect(326, 390, 456, 356), rotationDegrees: 8, scale: scale, imageColor: NSColor(calibratedRed: 0.26, green: 0.55, blue: 0.68, alpha: 1))
    drawMainPhoto(rect: rect(284, 424, 456, 356), scale: scale)
    drawArchiveBox(scale: scale)
    return representation
}

func drawPhoto(rect: NSRect, rotationDegrees: CGFloat, scale: CGFloat, imageColor: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: rect.midX, yBy: rect.midY)
    transform.rotate(byDegrees: rotationDegrees)
    transform.translateX(by: -rect.midX, yBy: -rect.midY)
    transform.concat()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = 20 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    shadow.set()

    let paper = NSBezierPath(roundedRect: rect, xRadius: 44 * scale, yRadius: 44 * scale)
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    paper.fill()

    let inner = rect.insetBy(dx: 38 * scale, dy: 42 * scale)
    let innerPath = NSBezierPath(roundedRect: inner, xRadius: 32 * scale, yRadius: 32 * scale)
    imageColor.setFill()
    innerPath.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawMainPhoto(rect: NSRect, scale: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 26 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.set()

    let paper = NSBezierPath(roundedRect: rect, xRadius: 46 * scale, yRadius: 46 * scale)
    NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.00, alpha: 1).setFill()
    paper.fill()
    NSGraphicsContext.restoreGraphicsState()

    let imageRect = rect.insetBy(dx: 38 * scale, dy: 42 * scale)
    let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: 32 * scale, yRadius: 32 * scale)
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.25, green: 0.79, blue: 0.86, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.53, alpha: 1)
        ]
    )?.draw(in: imagePath, angle: 90)

    drawMountains(in: imageRect, scale: scale)
    drawFaceScan(in: imageRect, scale: scale)
}

func drawMountains(in rect: NSRect, scale: CGFloat) {
    let back = NSBezierPath()
    back.move(to: NSPoint(x: rect.minX + 44 * scale, y: rect.minY + 58 * scale))
    back.line(to: NSPoint(x: rect.minX + 156 * scale, y: rect.minY + 182 * scale))
    back.line(to: NSPoint(x: rect.minX + 270 * scale, y: rect.minY + 58 * scale))
    back.close()
    NSColor(calibratedRed: 0.91, green: 0.97, blue: 0.79, alpha: 0.75).setFill()
    back.fill()

    let front = NSBezierPath()
    front.move(to: NSPoint(x: rect.minX + 148 * scale, y: rect.minY + 58 * scale))
    front.line(to: NSPoint(x: rect.minX + 282 * scale, y: rect.minY + 216 * scale))
    front.line(to: NSPoint(x: rect.maxX - 42 * scale, y: rect.minY + 58 * scale))
    front.close()
    NSColor(calibratedRed: 0.72, green: 0.94, blue: 0.65, alpha: 0.78).setFill()
    front.fill()
}

func drawFaceScan(in rect: NSRect, scale: CGFloat) {
    let faceRect = NSRect(x: rect.midX - 92 * scale, y: rect.midY - 66 * scale, width: 184 * scale, height: 184 * scale)
    let scanColor = NSColor(calibratedRed: 0.90, green: 1.00, blue: 0.62, alpha: 1)
    scanColor.setStroke()

    let lineWidth = max(2, 15 * scale)
    let corner = 54 * scale
    let inset: CGFloat = 10 * scale
    let x0 = faceRect.minX - inset
    let x1 = faceRect.maxX + inset
    let y0 = faceRect.minY - inset
    let y1 = faceRect.maxY + inset

    func strokeLine(_ start: NSPoint, _ end: NSPoint) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()
    }

    strokeLine(NSPoint(x: x0, y: y1 - corner), NSPoint(x: x0, y: y1))
    strokeLine(NSPoint(x: x0, y: y1), NSPoint(x: x0 + corner, y: y1))
    strokeLine(NSPoint(x: x1 - corner, y: y1), NSPoint(x: x1, y: y1))
    strokeLine(NSPoint(x: x1, y: y1), NSPoint(x: x1, y: y1 - corner))
    strokeLine(NSPoint(x: x0, y: y0 + corner), NSPoint(x: x0, y: y0))
    strokeLine(NSPoint(x: x0, y: y0), NSPoint(x: x0 + corner, y: y0))
    strokeLine(NSPoint(x: x1 - corner, y: y0), NSPoint(x: x1, y: y0))
    strokeLine(NSPoint(x: x1, y: y0), NSPoint(x: x1, y: y0 + corner))

    let face = NSBezierPath(ovalIn: faceRect)
    NSColor(calibratedRed: 0.97, green: 0.84, blue: 0.55, alpha: 0.96).setFill()
    face.fill()

    NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.26, alpha: 0.82).setFill()
    NSBezierPath(ovalIn: NSRect(x: faceRect.minX + 52 * scale, y: faceRect.midY + 20 * scale, width: 18 * scale, height: 22 * scale)).fill()
    NSBezierPath(ovalIn: NSRect(x: faceRect.maxX - 70 * scale, y: faceRect.midY + 20 * scale, width: 18 * scale, height: 22 * scale)).fill()

    let smile = NSBezierPath()
    smile.lineWidth = max(2, 12 * scale)
    smile.lineCapStyle = .round
    smile.move(to: NSPoint(x: faceRect.minX + 58 * scale, y: faceRect.midY - 42 * scale))
    smile.curve(
        to: NSPoint(x: faceRect.maxX - 58 * scale, y: faceRect.midY - 42 * scale),
        controlPoint1: NSPoint(x: faceRect.midX - 34 * scale, y: faceRect.midY - 78 * scale),
        controlPoint2: NSPoint(x: faceRect.midX + 34 * scale, y: faceRect.midY - 78 * scale)
    )
    NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.26, alpha: 0.72).setStroke()
    smile.stroke()
}

func drawArchiveBox(scale: CGFloat) {
    let back = NSBezierPath(roundedRect: NSRect(x: 210 * scale, y: 210 * scale, width: 604 * scale, height: 270 * scale), xRadius: 56 * scale, yRadius: 56 * scale)
    NSColor(calibratedRed: 0.95, green: 0.69, blue: 0.25, alpha: 1).setFill()
    back.fill()

    let lid = NSBezierPath(roundedRect: NSRect(x: 254 * scale, y: 454 * scale, width: 324 * scale, height: 92 * scale), xRadius: 38 * scale, yRadius: 38 * scale)
    NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.35, alpha: 1).setFill()
    lid.fill()

    let front = NSBezierPath(roundedRect: NSRect(x: 190 * scale, y: 180 * scale, width: 644 * scale, height: 238 * scale), xRadius: 64 * scale, yRadius: 64 * scale)
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.97, green: 0.61, blue: 0.21, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.35, blue: 0.12, alpha: 1)
        ]
    )?.draw(in: front, angle: 90)

    let slot = NSBezierPath(roundedRect: NSRect(x: 388 * scale, y: 304 * scale, width: 248 * scale, height: 42 * scale), xRadius: 21 * scale, yRadius: 21 * scale)
    NSColor(calibratedRed: 0.45, green: 0.20, blue: 0.11, alpha: 0.42).setFill()
    slot.fill()
}
