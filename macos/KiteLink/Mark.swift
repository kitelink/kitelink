import SwiftUI

/// The mark as SwiftUI drawing: a kite's sail full of wind, folded down the spine into a warm windward half and a
/// cool leeward half. Same numbers as brand/render.swift.
struct KiteMark: View {
    var size: CGFloat = 24
    var mono: Bool = false

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 1024 * 1.5
            let t = CGAffineTransform(translationX: sz.width / 2, y: sz.height / 2)
                .rotated(by: 16 * .pi / 180).scaledBy(x: k, y: k).translatedBy(x: 0, y: -18)
            func half(_ s: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: -265))
                p.addQuadCurve(to: CGPoint(x: s * 212, y: -52), control: CGPoint(x: s * 118, y: -196))
                p.addQuadCurve(to: CGPoint(x: 0, y: 300), control: CGPoint(x: s * 92, y: 78))
                p.closeSubpath()
                return p.applying(t)
            }
            let top = CGPoint(x: 0, y: -265).applying(t), bottom = CGPoint(x: 0, y: 300).applying(t)
            if mono {
                ctx.fill(half(-1), with: .color(.primary))
                ctx.fill(half(1), with: .color(.primary.opacity(0.62)))
            } else {
                ctx.fill(half(-1), with: .linearGradient(Gradient(colors: [Kite.peach, Kite.rose]), startPoint: top, endPoint: bottom))
                ctx.fill(half(1), with: .linearGradient(Gradient(colors: [Kite.lilac, Kite.blue]), startPoint: top, endPoint: bottom))
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
