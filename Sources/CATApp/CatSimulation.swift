import Foundation

enum CatAnimation: String, Codable, CaseIterable {
    case idle, alert, scratchSelf, scratchWallN, scratchWallS, scratchWallE, scratchWallW
    case tired, sleeping
    case north = "N", northeast = "NE", east = "E", southeast = "SE"
    case south = "S", southwest = "SW", west = "W", northwest = "NW"

    // Positive, top-left atlas coordinates corresponding to the website's CSS offsets.
    var frames: [(Int, Int)] {
        switch self {
        case .idle: return [(3, 3)]
        case .alert: return [(7, 3)]
        case .scratchSelf: return [(5, 0), (6, 0), (7, 0)]
        case .scratchWallN: return [(0, 0), (0, 1)]
        case .scratchWallS: return [(7, 1), (6, 2)]
        case .scratchWallE: return [(2, 2), (2, 3)]
        case .scratchWallW: return [(4, 0), (4, 1)]
        case .tired: return [(3, 2)]
        case .sleeping: return [(2, 0), (2, 1)]
        case .north: return [(1, 2), (1, 3)]
        case .northeast: return [(0, 2), (0, 3)]
        case .east: return [(3, 0), (3, 1)]
        case .southeast: return [(5, 1), (5, 2)]
        case .south: return [(6, 3), (7, 2)]
        case .southwest: return [(5, 3), (6, 1)]
        case .west: return [(4, 2), (4, 3)]
        case .northwest: return [(1, 0), (1, 1)]
        }
    }
}

struct CatState: Codable {
    var position = CGPoint(x: 32, y: 32)
    var frameCount = 0
    var idleTime = 0
    var idleAnimation: CatAnimation?
    var idleAnimationFrame = 0
    var displayedAnimation: CatAnimation = .idle
    var displayedFrame = 0
}

enum DesktopGeometry {
    static func nearestScreen(to point: CGPoint, screens: [CGRect]) -> CGRect {
        screens.min { distanceSquared(point, to: $0) < distanceSquared(point, to: $1) }
            ?? CGRect(x: 0, y: 0, width: 800, height: 600)
    }

    static func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                y: min(max(point.y, rect.minY), rect.maxY))
    }

    static func constrain(_ point: CGPoint, screens: [CGRect], inset: CGFloat = 16) -> CGPoint {
        let screen = nearestScreen(to: point, screens: screens)
        // Leave shared display edges open so crossing a monitor seam never teleports the cat.
        func hasNeighbor(at probe: CGPoint) -> Bool {
            screens.contains { $0 != screen && $0.contains(probe) }
        }
        let local = clamped(point, to: screen)
        let left: CGFloat = hasNeighbor(at: CGPoint(x: screen.minX - 1, y: local.y)) ? 0 : inset
        let right: CGFloat = hasNeighbor(at: CGPoint(x: screen.maxX + 1, y: local.y)) ? 0 : inset
        let bottom: CGFloat = hasNeighbor(at: CGPoint(x: local.x, y: screen.minY - 1)) ? 0 : inset
        let top: CGFloat = hasNeighbor(at: CGPoint(x: local.x, y: screen.maxY + 1)) ? 0 : inset
        return clamped(point, to: CGRect(x: screen.minX + left, y: screen.minY + bottom,
                                        width: screen.width - left - right,
                                        height: screen.height - bottom - top))
    }

    private static func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let nearest = clamped(point, to: rect)
        return pow(point.x - nearest.x, 2) + pow(point.y - nearest.y, 2)
    }
}

/// One step is the reference's ~100ms animation update, in macOS's bottom-left coordinates.
struct CatSimulation {
    var state: CatState
    var randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }

    mutating func step(toward target: CGPoint, screens: [CGRect], inset: CGFloat = 16) {
        state.frameCount += 1
        let dx = state.position.x - target.x
        let dy = target.y - state.position.y
        let distance = hypot(dx, dy)

        if distance < 48 {
            idle(on: DesktopGeometry.nearestScreen(to: state.position, screens: screens))
            return
        }

        resetIdleAnimation()
        if state.idleTime > 1 {
            show(.alert, frame: 0)
            state.idleTime = min(state.idleTime, 7) - 1
            return
        }

        var direction = ""
        if dy / distance > 0.5 { direction += "N" }
        if dy / distance < -0.5 { direction += "S" }
        if dx / distance > 0.5 { direction += "W" }
        if dx / distance < -0.5 { direction += "E" }
        show(CatAnimation(rawValue: direction) ?? .idle, frame: state.frameCount)

        let next = CGPoint(x: state.position.x - dx / distance * 10,
                           y: state.position.y + dy / distance * 10)
        state.position = DesktopGeometry.constrain(next, screens: screens, inset: inset)
    }

    private mutating func idle(on screen: CGRect) {
        state.idleTime += 1
        if state.idleTime > 10 && randomIndex(200) == 0 && state.idleAnimation == nil {
            var animations: [CatAnimation] = [.sleeping, .scratchSelf]
            if state.position.x < screen.minX + 32 { animations.append(.scratchWallW) }
            if state.position.y < screen.minY + 32 { animations.append(.scratchWallS) }
            if state.position.x > screen.maxX - 32 { animations.append(.scratchWallE) }
            if state.position.y > screen.maxY - 32 { animations.append(.scratchWallN) }
            state.idleAnimation = animations[randomIndex(animations.count)]
        }

        switch state.idleAnimation {
        case .sleeping:
            if state.idleAnimationFrame < 8 {
                show(.tired, frame: 0)
            } else {
                show(.sleeping, frame: state.idleAnimationFrame / 4)
                if state.idleAnimationFrame > 192 { resetIdleAnimation() }
            }
        case .scratchSelf?, .scratchWallN?, .scratchWallS?, .scratchWallE?, .scratchWallW?:
            show(state.idleAnimation ?? .idle, frame: state.idleAnimationFrame)
            if state.idleAnimationFrame > 9 { resetIdleAnimation() }
        default:
            show(.idle, frame: 0)
            return
        }
        state.idleAnimationFrame += 1
    }

    private mutating func resetIdleAnimation() {
        state.idleAnimation = nil
        state.idleAnimationFrame = 0
    }

    private mutating func show(_ animation: CatAnimation, frame: Int) {
        state.displayedAnimation = animation
        state.displayedFrame = frame
    }
}
