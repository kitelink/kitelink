import Foundation

/// Reads a region out of a node name. Providers put a flag or a place name in front of each node; the UI shows the flag
/// in its own column and the rest of the name next to it.
public struct NodeName: Equatable, Sendable {
    public let raw: String
    /// ISO 3166-1 alpha-2, when a flag or a known place name is in the raw name.
    public let region: String?
    /// The name without its leading flag.
    public let title: String

    public init(_ raw: String) {
        self.raw = raw
        var rest = raw
        var region: String?
        if let (code, range) = NodeName.leadingFlag(in: raw) {
            region = code
            rest.removeSubrange(range)
        } else if let code = NodeName.regionByKeyword(raw) {
            region = code
        }
        self.region = region
        self.title = rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var flag: String? { region.flatMap(NodeName.flag(for:)) }

    public static func flag(for region: String) -> String? {
        let base: UInt32 = 0x1F1E6
        let scalars = region.uppercased().unicodeScalars
        guard scalars.count == 2 else { return nil }
        var s = ""
        for u in scalars {
            guard u.value >= 65, u.value <= 90, let v = Unicode.Scalar(base + u.value - 65) else { return nil }
            s.unicodeScalars.append(v)
        }
        return s
    }

    /// A regional-indicator pair anywhere in the name (providers write "🇯🇵 Tokyo", "Tokyo 🇯🇵" or "[🇯🇵] 01").
    static func leadingFlag(in s: String) -> (String, Range<String.Index>)? {
        var i = s.unicodeScalars.startIndex
        let scalars = s.unicodeScalars
        while i < scalars.endIndex {
            let a = scalars[i]
            if (0x1F1E6...0x1F1FF).contains(a.value) {
                let j = scalars.index(after: i)
                if j < scalars.endIndex, (0x1F1E6...0x1F1FF).contains(scalars[j].value) {
                    let code = String(UnicodeScalar(scalars[i].value - 0x1F1E6 + 65)!) + String(UnicodeScalar(scalars[j].value - 0x1F1E6 + 65)!)
                    let end = scalars.index(after: j)
                    // Only strip a flag that leads the name; one in the middle stays.
                    let lead = s[s.startIndex..<i].allSatisfy { $0 == " " || $0 == "[" }
                    if lead {
                        var endIdx = end
                        if endIdx < scalars.endIndex, scalars[endIdx] == "]" { endIdx = scalars.index(after: endIdx) }
                        return (code, s.startIndex..<endIdx)
                    }
                    return (code, i..<i)
                }
            }
            i = scalars.index(after: i)
        }
        return nil
    }

    static let keywords: [(String, String)] = [
        ("香港", "HK"), ("Hong Kong", "HK"), ("HongKong", "HK"), ("HK", "HK"), ("港", "HK"),
        ("台湾", "TW"), ("台灣", "TW"), ("Taiwan", "TW"), ("TW", "TW"), ("台", "TW"),
        ("日本", "JP"), ("Japan", "JP"), ("Tokyo", "JP"), ("Osaka", "JP"), ("JP", "JP"), ("日", "JP"),
        ("新加坡", "SG"), ("狮城", "SG"), ("Singapore", "SG"), ("SG", "SG"), ("新", "SG"),
        ("美国", "US"), ("美國", "US"), ("United States", "US"), ("USA", "US"), ("US", "US"), ("美", "US"),
        ("韩国", "KR"), ("韓國", "KR"), ("Korea", "KR"), ("Seoul", "KR"), ("KR", "KR"), ("韩", "KR"),
        ("英国", "GB"), ("英國", "GB"), ("United Kingdom", "GB"), ("London", "GB"), ("UK", "GB"),
        ("德国", "DE"), ("德國", "DE"), ("Germany", "DE"), ("Frankfurt", "DE"), ("DE", "DE"),
        ("法国", "FR"), ("法國", "FR"), ("France", "FR"), ("Paris", "FR"), ("FR", "FR"),
        ("加拿大", "CA"), ("Canada", "CA"), ("CA", "CA"),
        ("澳洲", "AU"), ("澳大利亚", "AU"), ("Australia", "AU"), ("Sydney", "AU"), ("AU", "AU"),
        ("荷兰", "NL"), ("Netherlands", "NL"), ("Amsterdam", "NL"), ("NL", "NL"),
        ("俄罗斯", "RU"), ("Russia", "RU"), ("Moscow", "RU"), ("RU", "RU"),
        ("印度", "IN"), ("India", "IN"), ("Mumbai", "IN"),
        ("巴西", "BR"), ("Brazil", "BR"), ("BR", "BR"),
        ("迪拜", "AE"), ("阿联酋", "AE"), ("Dubai", "AE"), ("UAE", "AE"), ("AE", "AE"),
        ("土耳其", "TR"), ("Turkey", "TR"), ("Türkiye", "TR"), ("TR", "TR"),
        ("阿根廷", "AR"), ("Argentina", "AR"), ("AR", "AR"),
        ("墨西哥", "MX"), ("Mexico", "MX"), ("MX", "MX"),
        ("智利", "CL"), ("Chile", "CL"), ("CL", "CL"),
        ("越南", "VN"), ("Vietnam", "VN"), ("VN", "VN"),
        ("泰国", "TH"), ("Thailand", "TH"), ("TH", "TH"),
        ("菲律宾", "PH"), ("Philippines", "PH"), ("PH", "PH"),
        ("马来西亚", "MY"), ("Malaysia", "MY"), ("MY", "MY"),
        ("印尼", "ID"), ("Indonesia", "ID"),
        ("瑞士", "CH"), ("Switzerland", "CH"), ("CH", "CH"),
        ("瑞典", "SE"), ("Sweden", "SE"), ("SE", "SE"),
        ("西班牙", "ES"), ("Spain", "ES"), ("ES", "ES"),
        ("意大利", "IT"), ("Italy", "IT"),
        ("波兰", "PL"), ("Poland", "PL"), ("PL", "PL"),
        ("爱尔兰", "IE"), ("Ireland", "IE"), ("IE", "IE"),
        ("南非", "ZA"), ("South Africa", "ZA"), ("ZA", "ZA"),
        ("以色列", "IL"), ("Israel", "IL"), ("IL", "IL"),
        ("芬兰", "FI"), ("Finland", "FI"), ("FI", "FI"),
        ("中国", "CN"), ("China", "CN"), ("CN", "CN"),
    ]

    static let isoRegions: Set<String> = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 })

    static func regionByKeyword(_ s: String) -> String? {
        // "ID-A", "IN 02": a name that opens with an upper-case ISO code and a separator.
        let lead = s.prefix(while: { $0.isLetter && $0.isASCII })
        if lead.count == 2, lead == lead.uppercased(), s.count > 2, isoRegions.contains(String(lead)) {
            let next = s[s.index(s.startIndex, offsetBy: 2)]
            if !next.isLetter { return lead == "UK" ? "GB" : String(lead) }
        }
        if s.hasPrefix("UK"), s.count > 2, !s[s.index(s.startIndex, offsetBy: 2)].isLetter { return "GB" }
        // Longer, more specific keywords first; two-letter codes only match as upper-case whole words.
        for (k, code) in keywords where k.count > 2 || k.unicodeScalars.first!.value > 0x2E7F {
            if k.unicodeScalars.first!.value > 0x2E7F {
                if k.count > 1, s.contains(k) { return code }
            } else if s.range(of: k, options: .caseInsensitive) != nil { return code }
        }
        let words = s.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for (k, code) in keywords where k.count == 2 && k.unicodeScalars.first!.value < 0x80 {
            if words.contains(k) { return code }
        }
        // Single-character Chinese abbreviations last ("港", "日"), only when the name is short.
        if s.count <= 6 {
            for (k, code) in keywords where k.count == 1 { if s.contains(k) { return code } }
        }
        return nil
    }
}
