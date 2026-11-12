import SwiftUI
import AppKit
import KiteKit

/// The few colours the app uses beyond the system's. The mark's Dawn palette, with its violet as the accent for
/// selection and controls; everything else follows the system appearance so the window feels like a native utility
/// in light and dark.
enum Kite {
    static let peach = Color(red: 1, green: 0.761, blue: 0.69)
    static let rose = Color(red: 1, green: 0.561, blue: 0.659)
    static let lilac = Color(red: 0.718, green: 0.612, blue: 1)
    static let blue = Color(red: 0.435, green: 0.58, blue: 1)
    /// Dawn Violet, between the leeward half's two ends; a step deeper in light mode so white labels read on it.
    static let accent = dynamic(light: NSColor(red: 0.427, green: 0.455, blue: 0.957, alpha: 1), dark: NSColor(red: 0.51, green: 0.541, blue: 0.988, alpha: 1))
    /// Rose into violet, for the few places that are drawn rather than system controls (the quota bar).
    static let sweep = LinearGradient(colors: [rose, Color(red: 0.6, green: 0.58, blue: 1)], startPoint: .leading, endPoint: .trailing)

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let bar = dynamic(light: NSColor(white: 0.975, alpha: 1), dark: NSColor(white: 0.115, alpha: 1))
    static let side = dynamic(light: NSColor(white: 0.955, alpha: 1), dark: NSColor(white: 0.135, alpha: 1))
    static let bg = dynamic(light: NSColor(white: 1, alpha: 1), dark: NSColor(white: 0.16, alpha: 1))
    static let rowSelected = dynamic(light: NSColor(red: 0.427, green: 0.455, blue: 0.957, alpha: 0.13), dark: NSColor(red: 0.56, green: 0.58, blue: 1, alpha: 0.24))
    static let hairline = Color.primary.opacity(0.09)
    static let good = Color(nsColor: .systemGreen)
    static let fair = Color(nsColor: .systemOrange)
    static let poor = Color(nsColor: .systemRed)

    static func latency(_ ms: Int?) -> Color {
        guard let ms else { return .secondary.opacity(0.5) }
        if ms <= 0 { return poor }
        if ms < 250 { return good }
        if ms < 600 { return fair }
        return poor
    }
}

extension Font {
    static let mono = Font.system(.caption, design: .monospaced)
    static let tag = Font.system(size: 10, weight: .medium, design: .monospaced)
}

/// Small bordered label for protocol / group kind.
struct Tag: View {
    var text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text)
            .font(.tag)
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

extension Date {
    var relative: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: self, relativeTo: Date())
    }
    var short: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }
}

/// Flags. A Mac sold for some regions does not draw every flag emoji (it shows a crossed box), so each flag is drawn
/// once off screen and only used when it comes out in colour; otherwise the region code stands in.
enum Flag {
    private static var cache: [String: Bool] = [:]

    static func renders(_ region: String) -> Bool {
        if let c = cache[region] { return c }
        guard let f = NodeName.flag(for: region),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        (f as NSString).draw(at: NSPoint(x: 1, y: 1), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.gray])
        NSGraphicsContext.restoreGraphicsState()
        var colourful = 0
        for y in 0..<20 {
            for x in 0..<20 {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                if max(c.redComponent, c.greenComponent, c.blueComponent) - min(c.redComponent, c.greenComponent, c.blueComponent) > 0.25 { colourful += 1 }
            }
        }
        let ok = colourful > 8
        cache[region] = ok
        return ok
    }
}

extension NodeName {
    /// The flag when this Mac can draw it.
    var shownFlag: String? { region.flatMap { Flag.renders($0) ? NodeName.flag(for: $0) : nil } }
    /// One line for menus and subtitles.
    var display: String { [shownFlag, title].compactMap { $0 }.joined(separator: " ") }
}

/// The flag column of a node row: the flag, the region code when the flag cannot be drawn, or a dot.
struct FlagView: View {
    var name: NodeName
    var isGroup: Bool = false
    var body: some View {
        Group {
            if let f = name.shownFlag { Text(f).font(.system(size: 15)) }
            else if let r = name.region { Text(r).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).padding(.horizontal, 3).padding(.vertical, 1.5).background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))) }
            else { Text("·").font(.system(size: 15)).foregroundStyle(.tertiary) }
        }
        .frame(width: 24)
    }
}
