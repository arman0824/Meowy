import AppKit
import ImageIO

/// Decode and crop once. Animation only selects a cached, original-resolution frame.
final class SpriteSheet {
    static let spriteSize: CGFloat = 32
    private var images: [CatAnimation: [CGImage]] = [:]

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width == 256, atlas.height == 128 else { return nil }

        for animation in CatAnimation.allCases {
            var frames: [CGImage] = []
            for (column, row) in animation.frames {
                let rect = CGRect(x: CGFloat(column) * Self.spriteSize,
                                  y: CGFloat(row) * Self.spriteSize,
                                  width: Self.spriteSize, height: Self.spriteSize)
                guard let image = atlas.cropping(to: rect) else { return nil }
                frames.append(image)
            }
            images[animation] = frames
        }
    }

    func frame(_ animation: CatAnimation, index: Int) -> CGImage {
        let frames = images[animation]!
        return frames[max(0, index) % frames.count]
    }
}

@MainActor
final class SpriteView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let image else { return }
        context.clear(bounds)
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(image, in: bounds)
    }
}
