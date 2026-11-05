import AppKit
import CoreGraphics
import ImageIO
import Foundation

let spriteURL = URL(fileURLWithPath: "Resources/Meowy.gif")
guard let source = CGImageSourceCreateWithURL(spriteURL as CFURL, nil),
      let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("cannot load sprite atlas")
}

// Idle frame is at grid column 3, row 3 (32x32).
let spriteSize: CGFloat = 32
let cropRect = CGRect(x: 3 * spriteSize, y: 3 * spriteSize, width: spriteSize, height: spriteSize)
guard let catFrame = atlas.cropping(to: cropRect) else { fatalError("crop failed") }

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Color helpers
func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

let pairs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in pairs {
    let scale = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(true)

    // Rounded-rect clip (macOS icon shape ~22% corner radius)
    let corner = scale * 0.223
    let rect = CGRect(x: 0, y: 0, width: scale, height: scale)
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Background gradient
    let gradColors = [cgColor(0.98, 0.84, 0.62), cgColor(0.95, 0.62, 0.45)] as CFArray
    if let gradient = CGGradient(colorsSpace: cs, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: scale), end: CGPoint(x: scale, y: 0), options: [])
    }

    // Subtle warm highlight
    ctx.saveGState()
    let hiColors = [cgColor(1, 1, 1, 0.35), cgColor(1, 1, 1, 0.0)] as CFArray
    if let hi = CGGradient(colorsSpace: cs, colors: hiColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(hi, startCenter: CGPoint(x: scale*0.3, y: scale*0.75), startRadius: 0, endCenter: CGPoint(x: scale*0.3, y: scale*0.75), endRadius: scale*0.6, options: [])
    }
    ctx.restoreGState()

    // Soft shadow under cat
    ctx.saveGState()
    ctx.setFillColor(cgColor(0, 0, 0, 0.18))
    let shadowOval = CGRect(x: scale*0.30, y: scale*0.18, width: scale*0.40, height: scale*0.06)
    ctx.fillEllipse(in: shadowOval)
    ctx.restoreGState()

    // Cat sprite scaled up, crisp nearest-neighbor
    let catScale = scale * 0.58
    let catRect = CGRect(x: (scale - catScale)/2, y: (scale - catScale)/2 + scale*0.02, width: catScale, height: catScale)
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    ctx.draw(catFrame, in: catRect)

    guard let image = ctx.makeImage() else { continue }
    let url = outDir.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", url.path)
}
