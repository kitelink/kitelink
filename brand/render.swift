// Renders the KiteLink mark: the app icon set, the menu bar template images, PNGs and SVGs for the README.
//   swift brand/render.swift macos/KiteLink/Assets.xcassets brand
// No dependencies beyond AppKit: the mark is geometry, so every size is drawn fresh rather than scaled.
import AppKit

let args = CommandLine.arguments.dropFirst()
let assets = args.first ?? "macos/KiteLink/Assets.xcassets"
let brandDir = args.dropFirst().first ?? "brand"
let fm = FileManager.default

// ------------------------------------------------------------------------------------------- palette (Dawn)
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let hexBgTop: UInt32 = 0xFFF8F3, hexBgBottom: UInt32 = 0xFFE3EC
let hexPeach: UInt32 = 0xFFC2B0, hexRose: UInt32 = 0xFF8FA8      // windward half, top to bottom
let hexLilac: UInt32 = 0xB79CFF, hexBlue: UInt32 = 0x6F94FF      // leeward half, top to bottom
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// ------------------------------------------------------------------------------------------- geometry
/// The sail: a kite's diamond with the leading edges bowed out by the wind and the trailing edges drawn in, folded
/// down the spine into two halves. Local coordinates, y down, spine on x = 0; `side` is -1 (left) or +1 (right).
enum Sail {
    static let tilt: CGFloat = 16          // degrees, leaning into the wind
    static let top = CGPoint(x: 0, y: -265), bottom = CGPoint(x: 0, y: 300)
    static let offset = CGPoint(x: 0, y: -18)   // centres the sail on its own middle

    static func half(_ side: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: top)
        p.addQuadCurve(to: CGPoint(x: side * 212, y: -52), control: CGPoint(x: side * 118, y: -196))
        p.addQuadCurve(to: bottom, control: CGPoint(x: side * 92, y: 78))
        p.closeSubpath()
        return p
    }
    /// The halves pulled apart along the spine, for the one-colour glyph.
    static func monoHalf(_ side: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: side * 17, y: -240))
        p.addQuadCurve(to: CGPoint(x: side * 196, y: -54), control: CGPoint(x: side * 116, y: -180))
        p.addQuadCurve(to: CGPoint(x: side * 17, y: 250), control: CGPoint(x: side * 92, y: 70))
        p.closeSubpath()
        return p
    }
    static var outline: CGPath {
        let p = CGMutablePath()
        p.move(to: top)
        p.addQuadCurve(to: CGPoint(x: 212, y: -52), control: CGPoint(x: 118, y: -196))
        p.addQuadCurve(to: bottom, control: CGPoint(x: 92, y: 78))
        p.addQuadCurve(to: CGPoint(x: -212, y: -52), control: CGPoint(x: -92, y: 78))
        p.addQuadCurve(to: top, control: CGPoint(x: -118, y: -196))
        p.closeSubpath()
        return p
    }
    /// Local → canvas: centred at `c`, tilted, scaled by `k`.
    static func transform(center c: CGPoint, scale k: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: c.x, y: c.y).rotated(by: tilt * .pi / 180).scaledBy(x: k, y: k).translatedBy(x: offset.x, y: offset.y)
    }
}

func superellipse(_ r: CGRect, n: CGFloat = 4.6) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2
    for i in 0...360 {
        let t = CGFloat(i) / 360 * 2 * .pi
        let c = cos(t), s = sin(t)
        let pt = CGPoint(x: r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n), y: r.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

func fillHalf(_ ctx: CGContext, _ side: CGFloat, _ t: CGAffineTransform, _ from: UInt32, _ to: UInt32) {
    var tt = t
    guard let path = Sail.half(side).copy(using: &tt) else { return }
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: srgb, colors: [rgb(from), rgb(to)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: Sail.top.applying(t), end: Sail.bottom.applying(t), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func drawMark(_ ctx: CGContext, canvas: CGFloat, background: Bool) {
    let u = canvas / 1024
    if background {
        let box = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
        let shape = superellipse(box)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14 * u), blur: 32 * u, color: rgb(0x0B2545, 0.22))
        ctx.addPath(shape); ctx.setFillColor(rgb(hexBgBottom)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        let g = CGGradient(colorsSpace: srgb, colors: [rgb(hexBgTop), rgb(hexBgBottom)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
        ctx.restoreGState()
        ctx.addPath(shape); ctx.setStrokeColor(rgb(0x0B2545, 0.06)); ctx.setLineWidth(2 * u); ctx.strokePath()
    }
    let t = Sail.transform(center: CGPoint(x: 512 * u, y: 512 * u), scale: (background ? 1.1 : 1.5) * u)
    fillHalf(ctx, -1, t, hexPeach, hexRose)
    fillHalf(ctx, 1, t, hexLilac, hexBlue)
}

/// One colour, for the menu bar. Filled halves = proxy on; the outline = proxy off.
func drawTemplate(_ ctx: CGContext, canvas: CGFloat, hollow: Bool = false) {
    let u = canvas / 1024
    ctx.setFillColor(CGColor.black); ctx.setStrokeColor(CGColor.black)
    if hollow {
        var t = Sail.transform(center: CGPoint(x: 512 * u, y: 512 * u), scale: 1.42 * u)
        ctx.addPath(Sail.outline.copy(using: &t)!)
        ctx.setLineWidth(90 * u); ctx.setLineJoin(.round); ctx.strokePath()
    } else {
        var t = Sail.transform(center: CGPoint(x: 512 * u, y: 512 * u), scale: 1.55 * u)
        ctx.addPath(Sail.monoHalf(-1).copy(using: &t)!); ctx.addPath(Sail.monoHalf(1).copy(using: &t)!); ctx.fillPath()
    }
}

func render(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
    draw(ctx, CGFloat(size))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws { try data.write(to: URL(fileURLWithPath: path)) }
func writeJSON(_ object: Any, _ path: String) throws {
    try write(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), path)
}

// ------------------------------------------------------------------------------------------- asset catalog
let iconset = "\(assets)/AppIcon.appiconset"
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try write(render(pt * scale) { drawMark($0, canvas: $1, background: true) }, "\(iconset)/\(name)")
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
}
try writeJSON(["images": images, "info": ["version": 1, "author": "xcode"]], "\(iconset)/Contents.json")

for (set, hollow) in [("StatusIcon", false), ("StatusIconOff", true)] {
    let dir = "\(assets)/\(set).imageset"
    try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (file, px) in [("status.png", 18), ("status@2x.png", 36), ("status@3x.png", 54)] {
        try write(render(px) { drawTemplate($0, canvas: $1, hollow: hollow) }, "\(dir)/\(file)")
    }
    try writeJSON([
        "images": [["idiom": "universal", "scale": "1x", "filename": "status.png"], ["idiom": "universal", "scale": "2x", "filename": "status@2x.png"], ["idiom": "universal", "scale": "3x", "filename": "status@3x.png"]],
        "info": ["version": 1, "author": "xcode"], "properties": ["template-rendering-intent": "template"],
    ], "\(dir)/Contents.json")
}
try writeJSON(["info": ["version": 1, "author": "xcode"]], "\(assets)/Contents.json")

// ------------------------------------------------------------------------------------------- brand files
try fm.createDirectory(atPath: brandDir, withIntermediateDirectories: true)
try write(render(1024) { drawMark($0, canvas: $1, background: true) }, "\(brandDir)/icon-1024.png")
try write(render(512) { drawMark($0, canvas: $1, background: false) }, "\(brandDir)/mark-512.png")
try write(render(256) { drawTemplate($0, canvas: $1) }, "\(brandDir)/mark-mono-256.png")
try write(render(256) { drawTemplate($0, canvas: $1, hollow: true) }, "\(brandDir)/mark-mono-off-256.png")

// SVG, from the same numbers.
func f(_ v: CGFloat) -> String { String(format: "%g", Double((v * 10).rounded() / 10)) }
func hex(_ v: UInt32) -> String { String(format: "#%06X", v) }
func halfD(_ s: CGFloat) -> String { "M0 -265 Q\(f(s * 118)) -196 \(f(s * 212)) -52 Q\(f(s * 92)) 78 0 300 Z" }
func svg(background: Bool) -> String {
    var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">\n  <defs>\n"
    out += "    <linearGradient id=\"bg\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(hex(hexBgTop))\"/><stop offset=\"1\" stop-color=\"\(hex(hexBgBottom))\"/></linearGradient>\n"
    out += "    <linearGradient id=\"windward\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(hex(hexPeach))\"/><stop offset=\"1\" stop-color=\"\(hex(hexRose))\"/></linearGradient>\n"
    out += "    <linearGradient id=\"leeward\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(hex(hexLilac))\"/><stop offset=\"1\" stop-color=\"\(hex(hexBlue))\"/></linearGradient>\n"
    out += "    <filter id=\"lift\" x=\"-20%\" y=\"-20%\" width=\"140%\" height=\"140%\"><feDropShadow dx=\"0\" dy=\"14\" stdDeviation=\"16\" flood-color=\"#0B2545\" flood-opacity=\"0.22\"/></filter>\n  </defs>\n"
    if background {
        var d = ""
        let n: CGFloat = 4.6
        for i in 0..<180 {
            let t = CGFloat(i) / 180 * 2 * .pi, c = cos(t), s = sin(t)
            d += (i == 0 ? "M" : "L") + "\(f(512 + 412 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n))) \(f(512 + 412 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)))"
        }
        out += "  <path d=\"\(d)Z\" fill=\"url(#bg)\" filter=\"url(#lift)\"/>\n"
        out += "  <path d=\"\(d)Z\" fill=\"none\" stroke=\"#0B2545\" stroke-opacity=\"0.06\" stroke-width=\"2\"/>\n"
    }
    out += "  <g transform=\"translate(512 512) rotate(\(f(Sail.tilt))) scale(\(background ? "1.1" : "1.5")) translate(\(f(Sail.offset.x)) \(f(Sail.offset.y)))\">\n"
    out += "    <path d=\"\(halfD(-1))\" fill=\"url(#windward)\"/>\n    <path d=\"\(halfD(1))\" fill=\"url(#leeward)\"/>\n  </g>\n</svg>\n"
    return out
}
try svg(background: true).write(toFile: "\(brandDir)/icon.svg", atomically: true, encoding: .utf8)
try svg(background: false).write(toFile: "\(brandDir)/mark.svg", atomically: true, encoding: .utf8)
print("rendered \(iconset), status icons, \(brandDir)/icon-1024.png, icon.svg, mark.svg")
