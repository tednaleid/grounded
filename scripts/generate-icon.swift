#!/usr/bin/env swift
// ABOUTME: Renders the bolt.car.circle SF Symbol tinted systemGreen into
// ABOUTME: every macOS AppIcon slot and rewrites Contents.json. Run via `just icon`.
import AppKit
import Foundation

let projectDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outDir = projectDir.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct Slot {
    let label: String
    let scale: Int
    let pixels: Int
    let filename: String
}

let slots: [Slot] = [
    .init(label: "16x16",   scale: 1, pixels: 16,   filename: "icon_16x16.png"),
    .init(label: "16x16",   scale: 2, pixels: 32,   filename: "icon_16x16@2x.png"),
    .init(label: "32x32",   scale: 1, pixels: 32,   filename: "icon_32x32.png"),
    .init(label: "32x32",   scale: 2, pixels: 64,   filename: "icon_32x32@2x.png"),
    .init(label: "128x128", scale: 1, pixels: 128,  filename: "icon_128x128.png"),
    .init(label: "128x128", scale: 2, pixels: 256,  filename: "icon_128x128@2x.png"),
    .init(label: "256x256", scale: 1, pixels: 256,  filename: "icon_256x256.png"),
    .init(label: "256x256", scale: 2, pixels: 512,  filename: "icon_256x256@2x.png"),
    .init(label: "512x512", scale: 1, pixels: 512,  filename: "icon_512x512.png"),
    .init(label: "512x512", scale: 2, pixels: 1024, filename: "icon_512x512@2x.png"),
]

func renderPNG(pixels: Int) -> Data {
    let dim = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(
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
        fputs("failed to create bitmap at \(pixels)px\n", stderr)
        exit(1)
    }
    bitmap.size = NSSize(width: dim, height: dim)

    guard let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("failed to create context at \(pixels)px\n", stderr)
        exit(1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let squircleRadius = dim * 0.2237
    let squirclePath = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: dim, height: dim),
        xRadius: squircleRadius,
        yRadius: squircleRadius
    )
    NSColor.white.setFill()
    squirclePath.fill()
    squirclePath.addClip()

    let pointSize = dim * 0.72
    let sizing = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let palette = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
    let config = sizing.applying(palette)

    guard let symbol = NSImage(
        systemSymbolName: "bolt.car.circle",
        accessibilityDescription: "grounded"
    )?.withSymbolConfiguration(config) else {
        fputs("failed to load bolt.car.circle\n", stderr)
        exit(1)
    }

    let symbolSize = symbol.size
    let origin = NSPoint(
        x: (dim - symbolSize.width) / 2,
        y: (dim - symbolSize.height) / 2
    )
    symbol.draw(
        in: NSRect(origin: origin, size: symbolSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fputs("failed to encode PNG at \(pixels)px\n", stderr)
        exit(1)
    }
    return data
}

for slot in slots {
    let data = renderPNG(pixels: slot.pixels)
    let outURL = outDir.appendingPathComponent(slot.filename)
    try data.write(to: outURL)
    print("wrote \(slot.filename) (\(slot.pixels)×\(slot.pixels))")
}

struct ImageEntry: Encodable {
    let filename: String
    let idiom: String
    let scale: String
    let size: String
}
struct Info: Encodable {
    let author: String
    let version: Int
}
struct Contents: Encodable {
    let images: [ImageEntry]
    let info: Info
}

let contents = Contents(
    images: slots.map {
        ImageEntry(filename: $0.filename, idiom: "mac", scale: "\($0.scale)x", size: $0.label)
    },
    info: Info(author: "xcode", version: 1)
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted]
var json = String(data: try encoder.encode(contents), encoding: .utf8)!
if !json.hasSuffix("\n") { json += "\n" }
try json.write(
    to: outDir.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)
print("wrote Contents.json")
print("done: \(slots.count) icons generated")
