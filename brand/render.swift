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
/// The mark: a diamond kite's sail full of wind, its two spars, and a ring where the spars cross (the node, the link).
/// Local coordinates, y down, spine on x = 0.
enum Sail {
    static let tilt: CGFloat = 16          // degrees, leaning into the wind
    static let top = CGPoint(x: 0, y: -265), bottom = CGPoint(x: 0, y: 300)
    static let left = CGPoint(x: -212, y: -52), right = CGPoint(x: 212, y: -52)
    static let offset = CGPoint(x: 0, y: -18)   // centres the sail on its own middle
    /// The node: where the bowed cross spar meets the spine.
    static let node = CGPoint(x: 0, y: -78)

    /// Leading edges bowed out by the wind, trailing edges full.
    static var outline: CGPath {
        let p = CGMutablePath()
        p.move(to: top)
        p.addQuadCurve(to: right, control: CGPoint(x: 118, y: -196))
        p.addQuadCurve(to: bottom, control: CGPoint(x: 118, y: 132))
        p.addQuadCurve(to: left, control: CGPoint(x: -118, y: 132))
        p.addQuadCurve(to: top, control: CGPoint(x: -118, y: -196))
        p.closeSubpath()
        return p
    }
    /// The spine and the cross spar (bowed, like a real bowed kite), stopping `gap` short of the node.
    static func spars(gap: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: top); p.addLine(to: CGPoint(x: 0, y: node.y - gap))
        p.move(to: CGPoint(x: 0, y: node.y + gap)); p.addLine(to: bottom)
        // the cross spar is the quadratic left → (0, -104) → right; its halves are the quadratics below
        p.move(to: left); p.addQuadCurve(to: CGPoint(x: -gap, y: node.y), control: CGPoint(x: -106, y: -78))
        p.move(to: CGPoint(x: gap, y: node.y)); p.addQuadCurve(to: right, control: CGPoint(x: 106, y: -78))
        return p
    }
    static func circle(_ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: node.x - r, y: node.y - r, width: 2 * r, height: 2 * r), transform: nil) }
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

/// The sweep across the sail, nose to tail: peach, rose, lilac, sky.
let sweepStops: [(UInt32, CGFloat)] = [(hexPeach, 0), (hexRose, 0.38), (hexLilac, 0.68), (hexBlue, 1)]
let sweepFrom = CGPoint(x: -212, y: -265), sweepTo = CGPoint(x: 212, y: 300)

func drawSail(_ ctx: CGContext, _ t: CGAffineTransform) {
    ctx.saveGState()
    ctx.concatenate(t)
    ctx.addPath(Sail.outline); ctx.clip()
    let g = CGGradient(colorsSpace: srgb, colors: sweepStops.map { rgb($0.0) } as CFArray, locations: sweepStops.map { $0.1 })!
    ctx.drawLinearGradient(g, start: sweepFrom, end: sweepTo, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(16); ctx.setLineCap(.round)
    ctx.addPath(Sail.spars(gap: 62)); ctx.strokePath()
    ctx.setFillColor(rgb(0xFFFFFF)); ctx.addPath(Sail.circle(56)); ctx.fillPath()
    ctx.setFillColor(rgb(hexRose)); ctx.addPath(Sail.circle(22)); ctx.fillPath()
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
    drawSail(ctx, Sail.transform(center: CGPoint(x: 512 * u, y: 512 * u), scale: (background ? markInIcon : markAlone) * u))
}
let markInIcon: CGFloat = 1.0, markAlone: CGFloat = 1.36

/// One colour, for the menu bar: the kite's outline with the node in the middle. Off: the node is a ring. On: it fills in.
/// Drawn on a 20 pt square so the glyph carries about as much ink as its neighbours.
let glyphScale: CGFloat = 1.35
func drawTemplate(_ ctx: CGContext, canvas: CGFloat, hollow: Bool = false) {
    let u = canvas / 1024
    ctx.saveGState()
    ctx.concatenate(Sail.transform(center: CGPoint(x: 512 * u, y: 512 * u), scale: glyphScale * u))
    ctx.setFillColor(CGColor.black); ctx.setStrokeColor(CGColor.black); ctx.setLineJoin(.round)
    ctx.addPath(Sail.outline); ctx.setLineWidth(68); ctx.strokePath()
    if hollow {
        ctx.addPath(Sail.circle(56)); ctx.setLineWidth(48); ctx.strokePath()
    } else {
        ctx.addPath(Sail.circle(80)); ctx.fillPath()
    }
    ctx.restoreGState()
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
    for (file, px) in [("status.png", 20), ("status@2x.png", 40), ("status@3x.png", 60)] {
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
let outlineD = "M0 -265 Q118 -196 212 -52 Q118 132 0 300 Q-118 132 -212 -52 Q-118 -196 0 -265 Z"
let sparsD = "M0 -265 L0 -140 M0 -16 L0 300 M-212 -52 Q-106 -78 -62 -78 M62 -78 Q106 -78 212 -52"
func svg(background: Bool) -> String {
    var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">\n  <defs>\n"
    out += "    <linearGradient id=\"bg\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(hex(hexBgTop))\"/><stop offset=\"1\" stop-color=\"\(hex(hexBgBottom))\"/></linearGradient>\n"
    out += "    <linearGradient id=\"sweep\" gradientUnits=\"userSpaceOnUse\" x1=\"\(f(sweepFrom.x))\" y1=\"\(f(sweepFrom.y))\" x2=\"\(f(sweepTo.x))\" y2=\"\(f(sweepTo.y))\">"
    out += sweepStops.map { "<stop offset=\"\(f($0.1 * 100) )%\" stop-color=\"\(hex($0.0))\"/>" }.joined() + "</linearGradient>\n"
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
    out += "  <g transform=\"translate(512 512) rotate(\(f(Sail.tilt))) scale(\(f(background ? markInIcon : markAlone))) translate(\(f(Sail.offset.x)) \(f(Sail.offset.y)))\">\n"
    out += "    <path d=\"\(outlineD)\" fill=\"url(#sweep)\"/>\n"
    out += "    <path d=\"\(sparsD)\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"16\" stroke-linecap=\"round\"/>\n"
    out += "    <circle cx=\"0\" cy=\"-78\" r=\"56\" fill=\"#FFFFFF\"/><circle cx=\"0\" cy=\"-78\" r=\"22\" fill=\"\(hex(hexRose))\"/>\n  </g>\n</svg>\n"
    return out
}
try svg(background: true).write(toFile: "\(brandDir)/icon.svg", atomically: true, encoding: .utf8)
try svg(background: false).write(toFile: "\(brandDir)/mark.svg", atomically: true, encoding: .utf8)
print("rendered \(iconset), status icons, \(brandDir)/icon-1024.png, icon.svg, mark.svg")
