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

    // Plain white background
    ctx.setFillColor(cgColor(1, 1, 1, 1))
    ctx.fill(rect)

    // Cat sprite scaled up, crisp nearest-neighbor
    let catScale = scale * 0.62
    let catRect = CGRect(x: (scale - catScale)/2, y: (scale - catScale)/2, width: catScale, height: catScale)
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
