#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate_icon.swift <output_icns_path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let colorSpace = CGColorSpaceCreateDeviceRGB()

func renderPNGData(size px: Int) throws -> Data {
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "IconGen", code: 1)
    }

    let s = CGFloat(px)
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.22

    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colors = [
        CGColor(colorSpace: colorSpace, components: [0.14, 0.18, 0.28, 1.0])!,
        CGColor(colorSpace: colorSpace, components: [0.05, 0.06, 0.10, 1.0])!
    ] as CFArray
    let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )

    // Subtle top menu bar strip
    let barH = rect.height * 0.16
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.16])!)
    ctx.fill(CGRect(x: rect.minX, y: rect.maxY - barH, width: rect.width, height: barH))

    // Iconic black notch silhouette
    let notchW = rect.width * 0.48
    let notchH = rect.height * 0.24
    let notchRect = CGRect(
        x: rect.midX - notchW / 2,
        y: rect.maxY - notchH,
        width: notchW,
        height: notchH + radius
    )
    let notchPath = CGPath(
        roundedRect: notchRect,
        cornerWidth: notchH * 0.44,
        cornerHeight: notchH * 0.44,
        transform: nil
    )
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!)
    ctx.addPath(notchPath)
    ctx.fillPath()

    // Subtle camera lens glint
    let camR = notchH * 0.16
    let camRect = CGRect(
        x: rect.midX - camR,
        y: rect.maxY - notchH * 0.56 - camR,
        width: camR * 2,
        height: camR * 2
    )
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.22, 0.46, 0.96, 0.85])!)
    ctx.fillEllipse(in: camRect)

    // Subtle widget pill below notch
    let pillW = rect.width * 0.52
    let pillH = rect.height * 0.13
    let pillRect = CGRect(
        x: rect.midX - pillW / 2,
        y: rect.minY + rect.height * 0.28,
        width: pillW,
        height: pillH
    )
    let pillPath = CGPath(
        roundedRect: pillRect,
        cornerWidth: pillH / 2,
        cornerHeight: pillH / 2,
        transform: nil
    )
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.13])!)
    ctx.addPath(pillPath)
    ctx.fillPath()

    ctx.restoreGState()

    // Crisp rim border
    ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.2])!)
    ctx.setLineWidth(max(1, s * 0.012))
    ctx.addPath(bgPath)
    ctx.strokePath()

    let data = NSMutableData()
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconGen", code: 2)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "IconGen", code: 3)
    }
    return data as Data
}

func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    var be = value.bigEndian
    withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
}

let chunks: [(osType: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("ic11", 32),
    ("icp6", 64),
    ("ic12", 64),
    ("ic07", 128),
    ("ic13", 256),
    ("ic08", 256),
    ("ic14", 512),
    ("ic09", 512),
    ("ic10", 1024)
]

var body = Data()
for item in chunks {
    let png = try renderPNGData(size: item.pixels)
    body.append(contentsOf: item.osType.utf8)
    appendUInt32BE(UInt32(8 + png.count), to: &body)
    body.append(png)
}

var icns = Data()
icns.append(contentsOf: "icns".utf8)
appendUInt32BE(UInt32(8 + body.count), to: &icns)
icns.append(body)

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try icns.write(to: outputURL)
