#!/usr/bin/env swift
// swift tools/MakeIcon.swift                  → writes 3 preview PNGs to build/
// swift tools/MakeIcon.swift rings|pulse|bars → builds full iconset for the chosen variant
//
// Designs three macOS app icons that follow Apple HIG (squircle, front-facing, simple
// subject, recognizable at 16px, layered light shadow). All use the Claude orange brand
// palette. Outputs Resources/AppIcon.icns when a final variant is chosen.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Brand palette

let cream        = NSColor(srgbRed: 0.96, green: 0.93, blue: 0.86, alpha: 1.0)   // Anthropic-ish cream
let creamDeep    = NSColor(srgbRed: 0.92, green: 0.87, blue: 0.78, alpha: 1.0)   // gradient end
let charcoal     = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
let charcoalEnd  = NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1.0)

let burntOrange  = NSColor(srgbRed: 0.78, green: 0.42, blue: 0.27, alpha: 1.0)   // ~#C66B45
let claudeOrange = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1.0)   // ~#D97757 — canonical
let warmAmber    = NSColor(srgbRed: 0.95, green: 0.65, blue: 0.32, alpha: 1.0)   // ~#F2A652
let burntGlow    = NSColor(srgbRed: 0.92, green: 0.58, blue: 0.42, alpha: 1.0)
let claudeGlow   = NSColor(srgbRed: 0.96, green: 0.65, blue: 0.50, alpha: 1.0)
let amberGlow    = NSColor(srgbRed: 1.00, green: 0.82, blue: 0.50, alpha: 1.0)

// MARK: - Variants

enum Variant: String { case rings, pulse, bars }

// MARK: - Common helpers

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let buildDir = cwd.appendingPathComponent("build", isDirectory: true)
try? fm.createDirectory(at: buildDir, withIntermediateDirectories: true)

func makeBitmap(_ size: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!
}

func clipSquircle(in ctx: CGContext, side s: CGFloat) {
    let radius = s * 0.225           // Apple's squircle corner radius
    let bounds = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()
}

func render(variant: Variant, size: Int) -> Data? {
    let s = CGFloat(size)
    let bitmap = makeBitmap(size)
    let prev = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.current = prev }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
    ctx.saveGState()
    clipSquircle(in: ctx, side: s)

    switch variant {
    case .rings:  drawRings(ctx: ctx, s: s)
    case .pulse:  drawPulse(ctx: ctx, s: s)
    case .bars:   drawBars(ctx: ctx, s: s)
    }

    ctx.restoreGState()
    return bitmap.representation(using: .png, properties: [:])
}

// MARK: - Variant: Rings (Apple Fitness style, Claude orange)

func drawRings(ctx: CGContext, s: CGFloat) {
    // Background: charcoal gradient
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [charcoal.cgColor, charcoalEnd.cgColor] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])

    let ringWidth = s * 0.085
    let gap       = s * 0.026
    let outerR    = s * 0.385
    let center    = CGPoint(x: s/2, y: s/2)

    struct Ring { let radius: CGFloat; let progress: CGFloat; let color: NSColor; let glow: NSColor }
    let rings: [Ring] = [
        Ring(radius: outerR,                          progress: 0.92, color: claudeOrange, glow: claudeGlow),
        Ring(radius: outerR - ringWidth - gap,        progress: 0.78, color: warmAmber,    glow: amberGlow),
        Ring(radius: outerR - 2 * (ringWidth + gap),  progress: 0.55, color: burntOrange,  glow: burntGlow)
    ]

    for r in rings {
        ctx.setLineCap(.round)
        ctx.setLineWidth(ringWidth)
        ctx.setStrokeColor(r.color.withAlphaComponent(0.12).cgColor)
        ctx.beginPath()
        ctx.addArc(center: center, radius: r.radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()

        let startA: CGFloat = .pi / 2
        let endA: CGFloat = startA - 2 * .pi * r.progress
        let arcPath = CGMutablePath()
        arcPath.addArc(center: center, radius: r.radius, startAngle: startA, endAngle: endA, clockwise: true)

        ctx.saveGState()
        let stroked = arcPath.copy(strokingWithWidth: ringWidth, lineCap: .round, lineJoin: .round, miterLimit: 4)
        ctx.addPath(stroked)
        ctx.clip()
        let arcGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [r.color.cgColor, r.glow.cgColor] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            arcGrad,
            start: CGPoint(x: center.x - r.radius, y: center.y - r.radius),
            end:   CGPoint(x: center.x + r.radius, y: center.y + r.radius),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()

        if Int(s) >= 64 {
            ctx.saveGState()
            ctx.setStrokeColor(r.glow.withAlphaComponent(0.22).cgColor)
            ctx.setLineWidth(ringWidth * 1.18)
            ctx.setLineCap(.round)
            ctx.setShadow(offset: .zero, blur: ringWidth * 0.5, color: r.glow.withAlphaComponent(0.5).cgColor)
            ctx.addPath(arcPath)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // Tiny center dot
    if Int(s) >= 64 {
        let dotR = s * 0.018
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: s/2 - dotR, y: s/2 - dotR, width: dotR * 2, height: dotR * 2))
    }
}

// MARK: - Variant: Pulse (waveform on cream, Activity Monitor style)

func drawPulse(ctx: CGContext, s: CGFloat) {
    // Background: cream gradient (subtle warm tint)
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [cream.cgColor, creamDeep.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])

    // Faint horizontal baseline grid (Activity Monitor cue)
    ctx.setStrokeColor(claudeOrange.withAlphaComponent(0.10).cgColor)
    ctx.setLineWidth(max(1, s * 0.004))
    for f in [0.25, 0.5, 0.75] {
        let y = s * CGFloat(f)
        ctx.move(to: CGPoint(x: s * 0.10, y: y))
        ctx.addLine(to: CGPoint(x: s * 0.90, y: y))
    }
    ctx.strokePath()

    // Bold ECG/pulse line. Coordinates in Y-up (CG): center baseline at s/2.
    let line = CGMutablePath()
    let y0 = s * 0.50
    let leftPad = s * 0.10
    let rightPad = s * 0.90
    let span = rightPad - leftPad
    // Anchor points (relative x 0..1 across span, relative y offset from baseline)
    let pts: [(CGFloat, CGFloat)] = [
        (0.00,  0.00),
        (0.18,  0.00),
        (0.24,  0.05),
        (0.30, -0.03),
        (0.35,  0.32),       // peak up (looks like top in CG since Y-up)
        (0.40, -0.20),       // dip down
        (0.46,  0.06),
        (0.52,  0.00),
        (0.62,  0.00),
        (0.70,  0.18),
        (0.78, -0.04),
        (0.86,  0.00),
        (1.00,  0.00)
    ]
    line.move(to: CGPoint(x: leftPad + pts[0].0 * span, y: y0 + pts[0].1 * s))
    for p in pts.dropFirst() {
        line.addLine(to: CGPoint(x: leftPad + p.0 * span, y: y0 + p.1 * s))
    }

    // Stroke with gradient via clip
    let stroked = line.copy(strokingWithWidth: s * 0.085, lineCap: .round, lineJoin: .round, miterLimit: 4)
    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    let pulseGrad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [warmAmber.cgColor, claudeOrange.cgColor, burntOrange.cgColor] as CFArray,
        locations: [0, 0.45, 1.0]
    )!
    ctx.drawLinearGradient(pulseGrad,
                           start: CGPoint(x: leftPad, y: y0),
                           end:   CGPoint(x: rightPad, y: y0),
                           options: [])
    ctx.restoreGState()

    // Subtle drop shadow under the line
    if Int(s) >= 64 {
        ctx.saveGState()
        ctx.setStrokeColor(claudeOrange.withAlphaComponent(0.30).cgColor)
        ctx.setLineWidth(s * 0.085)
        ctx.setLineCap(.round)
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                      blur: s * 0.04,
                      color: NSColor.black.withAlphaComponent(0.18).cgColor)
        ctx.addPath(line)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - Variant: Bars (chart on cream, Numbers style)

func drawBars(ctx: CGContext, s: CGFloat) {
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [cream.cgColor, creamDeep.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])

    // Five ascending bars centered horizontally, Claude-orange gradient bottom→top
    let barCount = 5
    let plotLeft   = s * 0.18
    let plotRight  = s * 0.82
    let plotBottom = s * 0.22
    let plotTop    = s * 0.78
    let plotW = plotRight - plotLeft
    let plotH = plotTop - plotBottom
    let barGap = plotW * 0.10
    let totalGap = barGap * CGFloat(barCount - 1)
    let barW = (plotW - totalGap) / CGFloat(barCount)
    let heights: [CGFloat] = [0.30, 0.45, 0.62, 0.80, 1.00]
    let cornerRadius = barW * 0.30

    for i in 0..<barCount {
        let x = plotLeft + CGFloat(i) * (barW + barGap)
        let h = heights[i] * plotH
        let rect = CGRect(x: x, y: plotBottom, width: barW, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Gradient fill
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [burntOrange.cgColor, claudeOrange.cgColor, warmAmber.cgColor] as CFArray,
            locations: [0, 0.6, 1.0]
        )!
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: rect.midX, y: plotBottom),
                               end:   CGPoint(x: rect.midX, y: plotBottom + h),
                               options: [])
        ctx.restoreGState()

        if Int(s) >= 64 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.025,
                          color: NSColor.black.withAlphaComponent(0.18).cgColor)
            ctx.addPath(path)
            ctx.setFillColor(claudeOrange.withAlphaComponent(0.001).cgColor)   // shadow only
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    // Baseline accent under bars
    ctx.setStrokeColor(burntOrange.withAlphaComponent(0.55).cgColor)
    ctx.setLineWidth(max(1, s * 0.012))
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: plotLeft - barGap * 0.4, y: plotBottom - s * 0.02))
    ctx.addLine(to: CGPoint(x: plotRight + barGap * 0.4, y: plotBottom - s * 0.02))
    ctx.strokePath()
}

// MARK: - Iconset / preview output

let iconsetSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),     ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),     ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),  ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),  ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),  ("icon_512x512@2x.png", 1024)
]

func writeIconset(variant: Variant, asDefault: Bool) throws {
    let dir = buildDir.appendingPathComponent("AppIcon-\(variant.rawValue).iconset", isDirectory: true)
    try? fm.removeItem(at: dir)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, px) in iconsetSizes {
        guard let png = render(variant: variant, size: px) else {
            throw NSError(domain: "MakeIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed for \(name)"])
        }
        try png.write(to: dir.appendingPathComponent(name))
    }
    let variantIcns = cwd.appendingPathComponent("Resources/AppIcon-\(variant.rawValue).icns")
    try runIconutil(iconsetDir: dir, output: variantIcns)
    print("✓ Wrote \(variantIcns.lastPathComponent)")
    if asDefault {
        let defaultIcns = cwd.appendingPathComponent("Resources/AppIcon.icns")
        try? fm.removeItem(at: defaultIcns)
        try fm.copyItem(at: variantIcns, to: defaultIcns)
        print("✓ Wrote AppIcon.icns  (default = \(variant.rawValue))")
    }
}

func runIconutil(iconsetDir: URL, output: URL) throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", iconsetDir.path, "-o", output.path]
    let pipe = Pipe()
    proc.standardOutput = pipe; proc.standardError = pipe
    try proc.run(); proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        throw NSError(domain: "MakeIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "iconutil failed"])
    }
}

func writeAllVariants(defaultVariant: Variant) throws {
    for v in [Variant.rings, .pulse, .bars] {
        try writeIconset(variant: v, asDefault: v == defaultVariant)
    }
}

func writePreviews() throws {
    for v in [Variant.rings, .pulse, .bars] {
        guard let png = render(variant: v, size: 512) else {
            throw NSError(domain: "MakeIcon", code: 1)
        }
        let url = buildDir.appendingPathComponent("preview-\(v.rawValue).png")
        try png.write(to: url)
        print("✓ \(url.path)")
    }
}

// MARK: - Entry

let args = CommandLine.arguments.dropFirst()
do {
    if args.isEmpty {
        try writePreviews()
        print("\nPick one and run:  swift tools/MakeIcon.swift rings|pulse|bars")
        print("Or build all three (with chosen default):  swift tools/MakeIcon.swift all [rings|pulse|bars]")
    } else if args.first == "all" {
        let def = (args.count > 1 ? Variant(rawValue: args[args.index(args.startIndex, offsetBy: 1)]) : nil) ?? .pulse
        try writeAllVariants(defaultVariant: def)
    } else if let v = Variant(rawValue: args.first!) {
        try writeIconset(variant: v, asDefault: true)
    } else {
        print("Unknown variant. Use: rings | pulse | bars  (or 'all')")
        exit(2)
    }
} catch {
    print("✗ \(error.localizedDescription)")
    exit(1)
}
