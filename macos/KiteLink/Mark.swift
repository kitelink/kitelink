import SwiftUI

/// The kite mark as SwiftUI shapes: a tilted diamond with a line that ends in a loop. Same geometry as brand/render.swift.
struct KiteMark: View {
    var size: CGFloat = 24
    var mono: Bool = false
    /// Above 1 crops in on the mark, for small sizes where the icon's margins would waste the frame.
    var zoom: CGFloat = 1

    private func pt(_ x: CGFloat, _ y: CGFloat, _ c: CGPoint, _ k: CGFloat) -> CGPoint {
        let t: CGFloat = -16 * .pi / 180
        return CGPoint(x: c.x + (x * cos(t) - y * sin(t)) * k, y: c.y + (x * sin(t) + y * cos(t)) * k)
    }

    var body: some View {
        Canvas { ctx, sz in
            let u = sz.width / 1024 * zoom
            // The mark's own centre (kite and line together) stays in the middle of the frame as it zooms.
            let c = CGPoint(x: sz.width / 2 + (548 - 488) * u, y: sz.height / 2 + (428 - 520) * u)
            let top = pt(0, -210, c, u), right = pt(150, -30, c, u), bottom = pt(0, 230, c, u), left = pt(-150, -30, c, u)
            var diamond = Path()
            diamond.move(to: top); diamond.addLine(to: right); diamond.addLine(to: bottom); diamond.addLine(to: left); diamond.closeSubpath()
            let end = CGPoint(x: c.x - 190 * u, y: c.y + 380 * u)
            var tail = Path()
            tail.move(to: bottom)
            tail.addCurve(to: end, control1: CGPoint(x: bottom.x - 10 * u, y: bottom.y + 130 * u), control2: CGPoint(x: end.x + 150 * u, y: end.y - 10 * u))
            tail.addEllipse(in: CGRect(x: end.x - 62 * u, y: end.y - 31 * u, width: 62 * u, height: 62 * u))
            let lineColor: Color = mono ? .primary : Color(red: 1, green: 0.95, blue: 0.86)
            ctx.stroke(tail, with: .color(mono ? .primary : lineColor), style: StrokeStyle(lineWidth: max(1.5, 24 * u), lineCap: .round))
            if mono {
                ctx.fill(diamond, with: .color(.primary))
            } else {
                ctx.fill(diamond, with: .linearGradient(Gradient(colors: [Kite.amber, Kite.coral]), startPoint: top, endPoint: bottom))
                var half = Path(); half.move(to: top); half.addLine(to: right); half.addLine(to: bottom); half.closeSubpath()
                ctx.fill(half, with: .color(.black.opacity(0.16)))
                var frame = Path(); frame.move(to: top); frame.addLine(to: bottom); frame.move(to: left); frame.addLine(to: right)
                ctx.stroke(frame, with: .color(.white.opacity(0.35)), lineWidth: max(0.5, 5 * u))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Mark + wordmark, for the window bar and About.
struct Lockup: View {
    var body: some View {
        HStack(spacing: 7) {
            KiteMark(size: 24, zoom: 1.5)
            Text("KiteLink").font(.system(size: 14, weight: .semibold)).tracking(-0.2)
        }
    }
}
