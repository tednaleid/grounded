#!/usr/bin/env swift
// ABOUTME: Renders bolt.car.circle SF Symbol in each charger state color
// ABOUTME: as PNGs for the README status table. Run via `just readme-icons`.
import AppKit
import Foundation

let projectDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outDir = projectDir.appendingPathComponent("docs/images")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct StateIcon {
    let name: String
    let color: NSColor
}

let states: [StateIcon] = [
    .init(name: "signed-out", color: .gray),
    .init(name: "idle", color: .systemGreen),
    .init(name: "plugged-in", color: .systemBlue),
    .init(name: "charging", color: NSColor(red: 1.0, green: 0.95, blue: 0.1, alpha: 1.0)),
    .init(name: "error", color: .systemRed),
]

let pixels = 32

func renderPNG(color: NSColor) -> Data {
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
        fputs("failed to create bitmap\n", stderr)
        exit(1)
    }
    bitmap.size = NSSize(width: dim, height: dim)

    guard let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("failed to create context\n", stderr)
        exit(1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let pointSize = dim * 0.85
    let sizing = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let palette = NSImage.SymbolConfiguration(paletteColors: [color])
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
        fputs("failed to encode PNG\n", stderr)
        exit(1)
    }
    return data
}

for state in states {
    let data = renderPNG(color: state.color)
    let outURL = outDir.appendingPathComponent("state-\(state.name).png")
    try data.write(to: outURL)
    print("wrote state-\(state.name).png")
}
print("done: \(states.count) state icons generated")
