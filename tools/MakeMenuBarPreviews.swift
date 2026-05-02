#!/usr/bin/env swift
// swift tools/MakeMenuBarPreviews.swift
// Renders three SF Symbol candidates for the menu bar icon at preview size.

import AppKit

let candidates: [(file: String, symbol: String)] = [
    ("menubar-gauge.png",    "gauge.with.dots.needle.bottom.50percent"),
    ("menubar-waveform.png", "waveform.path.ecg"),
    ("menubar-chartbar.png", "chart.bar.fill")
]

let fm = FileManager.default
let outDir = URL(fileURLWithPath: fm.currentDirectoryPath)
    .appendingPathComponent("build", isDirectory: true)
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

let pointSize: CGFloat = 80   // scaled up so you can see detail
let canvasSide = 128

for c in candidates {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasSide, pixelsHigh: canvasSide,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!
    let prev = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.current = prev }
    guard let ctx = NSGraphicsContext.current?.cgContext else { continue }

    // Light gray "menu bar" rectangle background so the dark glyph reads.
    ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))

    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
    if let symbol = NSImage(systemSymbolName: c.symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let imgSize = symbol.size
        let drawRect = CGRect(
            x: (CGFloat(canvasSide) - imgSize.width) / 2,
            y: (CGFloat(canvasSide) - imgSize.height) / 2,
            width: imgSize.width, height: imgSize.height
        )
        symbol.draw(in: drawRect)
    }

    let url = outDir.appendingPathComponent(c.file)
    let png = bitmap.representation(using: .png, properties: [:])!
    try? png.write(to: url)
    print("✓ \(c.file)  (\(c.symbol))")
}
