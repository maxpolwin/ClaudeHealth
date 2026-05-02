import SwiftUI

/// Full-screen confetti overlay. Rendered into a borderless transparent NSPanel
/// by ConfettiWindowController. Uses TimelineView(.animation) for a continuous
/// frame-driven update, and SwiftUI Canvas for performant particle drawing.
struct ConfettiView: View {
    let duration: TimeInterval
    @State private var startTime = Date()
    private let particles: [Particle] = (0..<160).map { _ in Particle.random() }

    init(duration: TimeInterval = 5.0) {
        self.duration = duration
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(startTime)
            Canvas { ctx, size in
                draw(into: &ctx, size: size, t: t)
            }
            .opacity(opacity(at: t))
        }
        .ignoresSafeArea()
    }

    private func opacity(at t: TimeInterval) -> Double {
        // Stay opaque most of the run, fade out in the last 0.8s.
        let fadeStart = max(0, duration - 0.8)
        if t < fadeStart { return 1.0 }
        let f = (t - fadeStart) / 0.8
        return max(0, 1.0 - f)
    }

    private func draw(into ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        for p in particles {
            let burstDelay = p.burstDelay
            let localT = max(0, t - burstDelay)
            let baseX = p.startX * size.width
            let baseY = p.startY * size.height

            let x = baseX + p.dx * localT
            let y = baseY + p.dy0 * localT + 0.5 * p.gravity * localT * localT
            // skip if off-screen
            if y > size.height + 60 { continue }

            let rotation = p.rot0 + p.rotSpeed * localT
            let transform = CGAffineTransform(translationX: x, y: y)
                .rotated(by: .pi * rotation / 180)
            let path = Path(p.shape.path(size: p.size)).applying(transform)
            ctx.fill(path, with: .color(p.color))
        }
    }

    // MARK: - Particle

    struct Particle {
        let startX: Double         // 0..1 of width
        let startY: Double         // 0..1 of height
        let dx: Double             // horizontal drift (px/s)
        let dy0: Double            // initial vertical velocity (px/s); negative = up
        let gravity: Double        // px/s²
        let rot0: Double           // initial rotation (deg)
        let rotSpeed: Double       // deg/s
        let color: Color
        let size: Double
        let shape: Shape
        let burstDelay: TimeInterval

        enum Shape: CaseIterable {
            case circle, square, triangle, ribbon

            func path(size: Double) -> CGPath {
                let s = size
                switch self {
                case .circle:
                    return CGPath(ellipseIn: CGRect(x: -s/2, y: -s/2, width: s, height: s), transform: nil)
                case .square:
                    return CGPath(rect: CGRect(x: -s/2, y: -s/2, width: s, height: s), transform: nil)
                case .triangle:
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: 0, y: -s/2))
                    p.addLine(to: CGPoint(x: s/2, y: s/2))
                    p.addLine(to: CGPoint(x: -s/2, y: s/2))
                    p.closeSubpath()
                    return p
                case .ribbon:
                    return CGPath(rect: CGRect(x: -s/2, y: -s/4, width: s, height: s/2), transform: nil)
                }
            }
        }

        static func random() -> Particle {
            let palette: [Color] = [
                Color(red: 1.00, green: 0.30, blue: 0.30),
                Color(red: 1.00, green: 0.65, blue: 0.20),
                Color(red: 0.95, green: 0.85, blue: 0.20),
                Color(red: 0.20, green: 0.85, blue: 0.45),
                Color(red: 0.20, green: 0.55, blue: 1.00),
                Color(red: 0.65, green: 0.35, blue: 0.95),
                Color(red: 1.00, green: 0.45, blue: 0.85)
            ]
            return Particle(
                startX: .random(in: 0.10...0.90),
                startY: .random(in: 0.85...0.95),
                dx: .random(in: -180...180),
                dy0: .random(in: -640 ... -380),
                gravity: .random(in: 380...620),
                rot0: .random(in: 0...360),
                rotSpeed: .random(in: -540...540),
                color: palette.randomElement()!,
                size: .random(in: 7...14),
                shape: Shape.allCases.randomElement()!,
                burstDelay: .random(in: 0...0.6)
            )
        }
    }
}
