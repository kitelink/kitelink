// Renders the KiteLink mark: the app icon set, the menu bar template image and a 1024 PNG for the README.
//   swift brand/render.swift macos/KiteLink/Assets.xcassets brand
// No dependencies beyond AppKit: the mark is geometry, so every size is drawn fresh rather than scaled.
import AppKit

let args = CommandLine.arguments.dropFirst()
let assets = args.first ?? "macos/KiteLink/Assets.xcassets"
let brandDir = args.dropFirst().first ?? "brand"
let fm = FileManager.default

// ------------------------------------------------------------------------------------------- palette
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let skyTop = rgb(0x2C3C7E), skyBottom = rgb(0x0F1433)
let kiteA = rgb(0xFFC857), kiteB = rgb(0xFF6B4A)
let line = rgb(0xFFF3DC)

// ------------------------------------------------------------------------------------------- geometry (1024 canvas, y down)
func superellipse(_ r: CGRect, n: CGFloat = 4.6) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

struct Kite {
    /// Points in canvas space: top, right, bottom, left of the diamond, after the tilt.
    let top, right, bottom, left: CGPoint
    let center: CGPoint
    init(center c: CGPoint, scale k: CGFloat, tilt deg: CGFloat) {
        center = c
        let t = deg * .pi / 180
        func r(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: c.x + (x * cos(t) - y * sin(t)) * k, y: c.y + (x * sin(t) + y * cos(t)) * k)
        }
        top = r(0, -210); right = r(150, -30); bottom = r(0, 230); left = r(-150, -30)
    }
    var path: CGPath {
        let p = CGMutablePath()
        p.move(to: top); p.addLine(to: right); p.addLine(to: bottom); p.addLine(to: left); p.closeSubpath()
        return p
    }
    var rightHalf: CGPath {
        let p = CGMutablePath()
        p.move(to: top); p.addLine(to: right); p.addLine(to: bottom); p.closeSubpath()
        return p
    }
    /// The line: leaves the bottom vertex, swings down-left, and ends in the link loop.
    func tail(_ k: CGFloat) -> (CGPath, CGPoint) {
        let p = CGMutablePath()
        let b = bottom
        let end = CGPoint(x: center.x - 190 * k, y: center.y + 380 * k)
        p.move(to: b)
        p.addCurve(to: end, control1: CGPoint(x: b.x - 10 * k, y: b.y + 130 * k), control2: CGPoint(x: end.x + 150 * k, y: end.y - 10 * k))
        return (p, end)
    }
}

func drawMark(_ ctx: CGContext, canvas: CGFloat, background: Bool) {
    let u = canvas / 1024
    if background {
        let box = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14 * u), blur: 30 * u, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.38))
        ctx.addPath(superellipse(box)); ctx.setFillColor(skyBottom); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(superellipse(box)); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [skyTop, skyBottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
        // A warm glow behind the kite.
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0xFF8A5B, 0.28), rgb(0xFF8A5B, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 560 * u, y: 430 * u), startRadius: 0, endCenter: CGPoint(x: 560 * u, y: 430 * u), endRadius: 420 * u, options: [])
        ctx.restoreGState()
    }
    let kite = Kite(center: CGPoint(x: 548 * u, y: 428 * u), scale: u, tilt: -16)
    let (tail, end) = kite.tail(u)
    // The line, under the kite.
    ctx.saveGState()
    ctx.setStrokeColor(line); ctx.setLineWidth(24 * u); ctx.setLineCap(.round)
    ctx.addPath(tail); ctx.strokePath()
    ctx.addEllipse(in: CGRect(x: end.x - 62 * u, y: end.y - 31 * u, width: 62 * u, height: 62 * u)); ctx.strokePath()
    ctx.restoreGState()
    // The kite: a warm gradient along the long diagonal, the right face a step darker for the fold.
    ctx.saveGState()
    ctx.addPath(kite.path); ctx.clip()
    let kg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [kiteA, kiteB] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(kg, start: kite.top, end: kite.bottom, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.addPath(kite.rightHalf); ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.05, blue: 0.1, alpha: 0.18)); ctx.fillPath()
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35)); ctx.setLineWidth(5 * u)
    ctx.move(to: kite.top); ctx.addLine(to: kite.bottom); ctx.move(to: kite.left); ctx.addLine(to: kite.right); ctx.strokePath()
    ctx.restoreGState()
}

/// Monochrome version for the menu bar, drawn bolder than the icon: a wider kite, a short line and a dot for the
/// link. `hollow` draws the kite as an outline (proxy off).
func drawTemplate(_ ctx: CGContext, canvas: CGFloat, hollow: Bool = false) {
    let u = canvas / 1024
    ctx.setFillColor(CGColor.black); ctx.setStrokeColor(CGColor.black)
    let c = CGPoint(x: 590 * u, y: 380 * u)
    let t: CGFloat = -16 * .pi / 180
    func r(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: c.x + (x * cos(t) - y * sin(t)) * u, y: c.y + (x * sin(t) + y * cos(t)) * u)
    }
    let top = r(0, -300), right = r(230, -60), bottom = r(0, 300), left = r(-230, -60)
    let kite = CGMutablePath()
    kite.move(to: top); kite.addLine(to: right); kite.addLine(to: bottom); kite.addLine(to: left); kite.closeSubpath()
    let end = CGPoint(x: c.x - 300 * u, y: c.y + 520 * u)
    let tail = CGMutablePath()
    tail.move(to: bottom)
    tail.addCurve(to: end, control1: CGPoint(x: bottom.x - 20 * u, y: bottom.y + 160 * u), control2: CGPoint(x: end.x + 200 * u, y: end.y - 20 * u))
    ctx.setLineWidth(96 * u); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addPath(tail); ctx.strokePath()
    ctx.addEllipse(in: CGRect(x: end.x - 90 * u, y: end.y - 90 * u, width: 180 * u, height: 180 * u)); ctx.fillPath()
    if hollow { ctx.addPath(kite); ctx.strokePath() } else { ctx.addPath(kite); ctx.fillPath() }
}

func render(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
    draw(ctx, CGFloat(size))
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])!
}

// ------------------------------------------------------------------------------------------- outputs
let iconset = "\(assets)/AppIcon.appiconset"
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = pt * scale
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try render(px) { drawMark($0, canvas: $1, background: true) }.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(iconset)/Contents.json"))

let statusSet = "\(assets)/StatusIcon.imageset"
try fm.createDirectory(atPath: statusSet, withIntermediateDirectories: true)
try render(18) { drawTemplate($0, canvas: $1) }.write(to: URL(fileURLWithPath: "\(statusSet)/status.png"))
try render(36) { drawTemplate($0, canvas: $1) }.write(to: URL(fileURLWithPath: "\(statusSet)/status@2x.png"))
try render(54) { drawTemplate($0, canvas: $1) }.write(to: URL(fileURLWithPath: "\(statusSet)/status@3x.png"))
let statusContents: [String: Any] = [
    "images": [["idiom": "universal", "scale": "1x", "filename": "status.png"], ["idiom": "universal", "scale": "2x", "filename": "status@2x.png"], ["idiom": "universal", "scale": "3x", "filename": "status@3x.png"]],
    "info": ["version": 1, "author": "xcode"], "properties": ["template-rendering-intent": "template"],
]
try JSONSerialization.data(withJSONObject: statusContents, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(statusSet)/Contents.json"))
let offSet = "\(assets)/StatusIconOff.imageset"
try fm.createDirectory(atPath: offSet, withIntermediateDirectories: true)
try render(18) { drawTemplate($0, canvas: $1, hollow: true) }.write(to: URL(fileURLWithPath: "\(offSet)/status.png"))
try render(36) { drawTemplate($0, canvas: $1, hollow: true) }.write(to: URL(fileURLWithPath: "\(offSet)/status@2x.png"))
try render(54) { drawTemplate($0, canvas: $1, hollow: true) }.write(to: URL(fileURLWithPath: "\(offSet)/status@3x.png"))
try JSONSerialization.data(withJSONObject: statusContents, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(offSet)/Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted]).write(to: URL(fileURLWithPath: "\(assets)/Contents.json"))

try fm.createDirectory(atPath: brandDir, withIntermediateDirectories: true)
try render(1024) { drawMark($0, canvas: $1, background: true) }.write(to: URL(fileURLWithPath: "\(brandDir)/icon-1024.png"))
try render(512) { drawMark($0, canvas: $1, background: false) }.write(to: URL(fileURLWithPath: "\(brandDir)/mark-512.png"))
try render(256) { drawTemplate($0, canvas: $1) }.write(to: URL(fileURLWithPath: "\(brandDir)/mark-mono-256.png"))

// ------------------------------------------------------------------------------------------- SVG (same geometry)
func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
func pt(_ p: CGPoint) -> String { "\(f(p.x)) \(f(p.y))" }
func svg(background: Bool) -> String {
    let kite = Kite(center: CGPoint(x: 548, y: 428), scale: 1, tilt: -16)
    let end = CGPoint(x: kite.center.x - 190, y: kite.center.y + 380)
    let b = kite.bottom
    var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">\n"
    out += "  <defs>\n"
    out += "    <linearGradient id=\"sky\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#2C3C7E\"/><stop offset=\"1\" stop-color=\"#0F1433\"/></linearGradient>\n"
    out += "    <radialGradient id=\"glow\" cx=\"560\" cy=\"430\" r=\"420\" gradientUnits=\"userSpaceOnUse\"><stop offset=\"0\" stop-color=\"#FF8A5B\" stop-opacity=\"0.28\"/><stop offset=\"1\" stop-color=\"#FF8A5B\" stop-opacity=\"0\"/></radialGradient>\n"
    out += "    <linearGradient id=\"kite\" gradientUnits=\"userSpaceOnUse\" x1=\"\(f(kite.top.x))\" y1=\"\(f(kite.top.y))\" x2=\"\(f(kite.bottom.x))\" y2=\"\(f(kite.bottom.y))\"><stop offset=\"0\" stop-color=\"#FFC857\"/><stop offset=\"1\" stop-color=\"#FF6B4A\"/></linearGradient>\n"
    out += "  </defs>\n"
    if background {
        var d = ""
        let n: CGFloat = 4.6
        for i in 0..<180 {
            let t = CGFloat(i) / 180 * 2 * .pi
            let c = cos(t), sn = sin(t)
            let x = 512 + 412 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n), y = 512 + 412 * (sn < 0 ? -1 : 1) * pow(abs(sn), 2 / n)
            d += (i == 0 ? "M" : "L") + "\(f(x)) \(f(y))"
        }
        out += "  <path d=\"\(d)Z\" fill=\"url(#sky)\"/>\n  <path d=\"\(d)Z\" fill=\"url(#glow)\"/>\n"
    }
    out += "  <g fill=\"none\" stroke=\"#FFF3DC\" stroke-width=\"24\" stroke-linecap=\"round\">\n"
    out += "    <path d=\"M\(pt(b)) C\(f(b.x - 10)) \(f(b.y + 130)) \(f(end.x + 150)) \(f(end.y - 10)) \(pt(end))\"/>\n"
    out += "    <circle cx=\"\(f(end.x - 31))\" cy=\"\(f(end.y))\" r=\"31\"/>\n  </g>\n"
    out += "  <path d=\"M\(pt(kite.top)) L\(pt(kite.right)) L\(pt(kite.bottom)) L\(pt(kite.left))Z\" fill=\"url(#kite)\"/>\n"
    out += "  <path d=\"M\(pt(kite.top)) L\(pt(kite.right)) L\(pt(kite.bottom))Z\" fill=\"#1A0D1A\" fill-opacity=\"0.18\"/>\n"
    out += "  <path d=\"M\(pt(kite.top)) L\(pt(kite.bottom)) M\(pt(kite.left)) L\(pt(kite.right))\" stroke=\"#FFFFFF\" stroke-opacity=\"0.35\" stroke-width=\"5\" fill=\"none\"/>\n"
    out += "</svg>\n"
    return out
}
try svg(background: true).write(toFile: "\(brandDir)/icon.svg", atomically: true, encoding: .utf8)
try svg(background: false).write(toFile: "\(brandDir)/mark.svg", atomically: true, encoding: .utf8)
print("rendered \(iconset), \(statusSet), \(brandDir)/icon-1024.png, icon.svg, mark.svg")
