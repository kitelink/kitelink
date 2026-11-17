import SwiftUI

/// The mark as SwiftUI drawing: a diamond kite's sail full of wind, its two spars, and a ring where they cross (the
/// node, the link). Same numbers as brand/render.swift.
struct KiteMark: View {
    var size: CGFloat = 24
    var mono: Bool = false

    private static let node = CGPoint(x: 0, y: -78)
    private static var outline: Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -265))
        p.addQuadCurve(to: CGPoint(x: 212, y: -52), control: CGPoint(x: 118, y: -196))
        p.addQuadCurve(to: CGPoint(x: 0, y: 300), control: CGPoint(x: 118, y: 132))
        p.addQuadCurve(to: CGPoint(x: -212, y: -52), control: CGPoint(x: -118, y: 132))
        p.addQuadCurve(to: CGPoint(x: 0, y: -265), control: CGPoint(x: -118, y: -196))
        p.closeSubpath()
        return p
    }
    private static func spars(gap: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -265)); p.addLine(to: CGPoint(x: 0, y: node.y - gap))
        p.move(to: CGPoint(x: 0, y: node.y + gap)); p.addLine(to: CGPoint(x: 0, y: 300))
        p.move(to: CGPoint(x: -212, y: -52)); p.addQuadCurve(to: CGPoint(x: -gap, y: node.y), control: CGPoint(x: -106, y: -78))
        p.move(to: CGPoint(x: gap, y: node.y)); p.addQuadCurve(to: CGPoint(x: 212, y: -52), control: CGPoint(x: 106, y: -78))
        return p
    }
    private static func circle(_ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: node.x - r, y: node.y - r, width: 2 * r, height: 2 * r))
    }

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 1024 * 1.36
            ctx.translateBy(x: sz.width / 2, y: sz.height / 2)
            ctx.rotate(by: .degrees(16))
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: 0, y: -18)
            if mono {
                ctx.stroke(Self.outline, with: .color(.primary), style: StrokeStyle(lineWidth: 68, lineJoin: .round))
                ctx.fill(Self.circle(80), with: .color(.primary))
            } else {
                ctx.fill(Self.outline, with: .linearGradient(
                    Gradient(stops: [.init(color: Kite.peach, location: 0), .init(color: Kite.rose, location: 0.38),
                                     .init(color: Kite.lilac, location: 0.68), .init(color: Kite.blue, location: 1)]),
                    startPoint: CGPoint(x: -212, y: -265), endPoint: CGPoint(x: 212, y: 300)))
                ctx.stroke(Self.spars(gap: 62), with: .color(.white), style: StrokeStyle(lineWidth: max(16, 1.2 / k), lineCap: .round))
                ctx.fill(Self.circle(56), with: .color(.white))
                ctx.fill(Self.circle(22), with: .color(Kite.rose))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Mark + wordmark, for the window bar and About.
struct Lockup: View {
    var body: some View {
        HStack(spacing: 6) {
            KiteMark(size: 24)
            Text("KiteLink").font(.system(size: 14, weight: .semibold)).tracking(-0.2)
        }
    }
}
