#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let margin = s * 0.06
    let corner = s * 0.22
    let rect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colors = [
        CGColor(srgbRed: 0.10, green: 0.08, blue: 0.06, alpha: 1),
        CGColor(srgbRed: 0.22, green: 0.16, blue: 0.10, alpha: 1),
        CGColor(srgbRed: 0.16, green: 0.12, blue: 0.08, alpha: 1),
        CGColor(srgbRed: 0.08, green: 0.06, blue: 0.05, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.35, 0.7, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    if let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.90, green: 0.72, blue: 0.38, alpha: 0.18),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            highlight,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.midY),
            options: []
        )
    }

    drawKeys(in: ctx, size: s, bounds: rect)
    if size >= 32 {
        drawPlayMark(in: ctx, size: s, bounds: rect)
    }
    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.68, blue: 0.36, alpha: 0.55))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.addPath(path)
    ctx.strokePath()

    return ctx.makeImage()
}

func drawKeys(in ctx: CGContext, size s: CGFloat, bounds: CGRect) {
    let keyCount = s >= 128 ? 7 : (s >= 32 ? 5 : 4)
    let insetX = bounds.width * 0.16
    let keyTop = bounds.minY + bounds.height * 0.18
    let keyHeight = bounds.height * 0.42
    let totalW = bounds.width - insetX * 2
    let gap = max(1, s * 0.008)
    let whiteW = (totalW - gap * CGFloat(keyCount - 1)) / CGFloat(keyCount)
    let originX = bounds.minX + insetX

    // Shadow plate
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.fill(CGRect(x: originX - s * 0.01, y: keyTop - s * 0.015, width: totalW + s * 0.02, height: keyHeight + s * 0.03))

    for i in 0..<keyCount {
        let x = originX + CGFloat(i) * (whiteW + gap)
        let lit = i == (keyCount == 7 ? 3 : 2)
        let white = CGRect(x: x, y: keyTop, width: whiteW, height: keyHeight)
        let path = CGPath(roundedRect: white, cornerWidth: s * 0.018, cornerHeight: s * 0.018, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let cols: [CGColor] = lit
            ? [
                CGColor(srgbRed: 0.98, green: 0.82, blue: 0.40, alpha: 1),
                CGColor(srgbRed: 0.86, green: 0.58, blue: 0.18, alpha: 1),
            ]
            : [
                CGColor(srgbRed: 0.99, green: 0.98, blue: 0.94, alpha: 1),
                CGColor(srgbRed: 0.88, green: 0.86, blue: 0.80, alpha: 1),
            ]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: x, y: keyTop + keyHeight), end: CGPoint(x: x, y: keyTop), options: [])
        }
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25))
        ctx.setLineWidth(max(0.6, s * 0.006))
        ctx.addPath(path)
        ctx.strokePath()
    }

    if s >= 32 {
        let blacks: [Int] = keyCount >= 7 ? [0, 1, 3, 4, 5] : (keyCount >= 5 ? [0, 1, 3] : [0, 2])
        let blackW = whiteW * 0.58
        let blackH = keyHeight * 0.62
        for i in blacks {
            let x = originX + CGFloat(i + 1) * (whiteW + gap) - blackW / 2 - gap / 2
            let y = keyTop + keyHeight - blackH
            let br = CGRect(x: x, y: y, width: blackW, height: blackH)
            let path = CGPath(roundedRect: br, cornerWidth: s * 0.012, cornerHeight: s * 0.012, transform: nil)
            ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.07, blue: 0.06, alpha: 1))
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12))
            ctx.setLineWidth(max(0.5, s * 0.004))
            ctx.addPath(path)
            ctx.strokePath()
        }
    }
}

func drawPlayMark(in ctx: CGContext, size s: CGFloat, bounds: CGRect) {
    let cy = bounds.maxY - bounds.height * 0.22
    let cx = bounds.midX
    let r = s * 0.09
    ctx.setFillColor(CGColor(srgbRed: 0.90, green: 0.62, blue: 0.22, alpha: 0.95))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))

    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.beginPath()
    let ox = cx - r * 0.22
    ctx.move(to: CGPoint(x: ox, y: cy + r * 0.42))
    ctx.addLine(to: CGPoint(x: ox, y: cy - r * 0.42))
    ctx.addLine(to: CGPoint(x: cx + r * 0.48, y: cy))
    ctx.closePath()
    ctx.fillPath()
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizes {
    guard let image = renderIcon(size: size) else {
        fputs("Failed to render \(size)px\n", stderr)
        exit(1)
    }
    let url = iconset.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fputs("Failed to write \(name)\n", stderr)
        exit(1)
    }
}

if let master = renderIcon(size: 1024) {
    let url = assets.appendingPathComponent("AppIcon-1024.png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, master, nil)
    CGImageDestinationFinalize(dest)
}

let icns = assets.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

print("Wrote \(icns.path)")
