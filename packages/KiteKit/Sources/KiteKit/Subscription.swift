import Foundation

/// What a provider answered: the YAML plus the headers Clash clients agree on.
public struct SubscriptionResponse: Sendable {
    public var body: Data
    /// From `content-disposition`, when the provider names the profile.
    public var name: String?
    public var usage: SubscriptionUsage?
    public var updateIntervalHours: Int?
    public var homeURL: String?

    public var text: String { String(decoding: body, as: UTF8.self) }
}

public enum SubscriptionError: Error, LocalizedError {
    case badURL
    case http(Int)
    case notClashProfile(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .badURL: return "That is not a link."
        case .http(let c): return "The provider answered HTTP \(c)."
        case .notClashProfile(let hint): return "The link did not return a Clash profile\(hint.isEmpty ? "." : ": \(hint)")"
        case .empty: return "The provider returned nothing."
        }
    }
}

public enum Subscription {
    /// Fetches a subscription. `proxyPort` routes the request through the local mixed port.
    public static func fetch(_ urlString: String, userAgent: String, proxyPort: Int? = nil, timeout: TimeInterval = 30) async throws -> SubscriptionResponse {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else {
            throw SubscriptionError.badURL
        }
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        if let proxyPort {
            c.connectionProxyDictionary = [
                "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": proxyPort,
                "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": proxyPort,
            ]
        } else {
            c.connectionProxyDictionary = [:]
        }
        let session = URLSession(configuration: c)
        let (data, resp) = try await session.data(from: url)
        let http = resp as? HTTPURLResponse
        if let code = http?.statusCode, code >= 400 { throw SubscriptionError.http(code) }
        guard !data.isEmpty else { throw SubscriptionError.empty }
        var r = SubscriptionResponse(body: data)
        if let cd = http?.value(forHTTPHeaderField: "content-disposition") { r.name = parseFilename(cd) }
        if let ui = http?.value(forHTTPHeaderField: "subscription-userinfo") { r.usage = SubscriptionUsage.parse(ui) }
        if let iv = http?.value(forHTTPHeaderField: "profile-update-interval"), let h = Int(iv.trimmingCharacters(in: .whitespaces)), h > 0 { r.updateIntervalHours = h }
        if let home = http?.value(forHTTPHeaderField: "profile-web-page-url"), !home.isEmpty { r.homeURL = home.trimmingCharacters(in: .whitespaces) }
        try validate(r.text)
        return r
    }

    /// A profile must at least declare proxies or proxy providers; anything else is a web page or a share-link list.
    public static func validate(_ text: String) throws {
        let head = text.prefix(4096).lowercased()
        if head.contains("<html") || head.contains("<!doctype") { throw SubscriptionError.notClashProfile("it is a web page") }
        let hasKey = text.range(of: #"(?m)^(proxies|proxy-providers|proxy-groups):"#, options: .regularExpression) != nil
        if !hasKey {
            let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if compact.range(of: #"^[A-Za-z0-9+/=\s_-]+$"#, options: .regularExpression) != nil, compact.count > 32 {
                throw SubscriptionError.notClashProfile("it is a base64 share-link list; ask the provider for a Clash link")
            }
            throw SubscriptionError.notClashProfile("no proxies in it")
        }
    }

    /// `attachment; filename="a.yaml"` or `attachment;filename*=UTF-8''%E7%8B%97.yaml`.
    public static func parseFilename(_ header: String) -> String? {
        var name: String?
        for part in header.split(separator: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.lowercased().hasPrefix("filename*=") {
                var v = String(p.dropFirst("filename*=".count))
                if let q = v.range(of: "''") { v = String(v[q.upperBound...]) }
                name = v.removingPercentEncoding ?? v
                break
            } else if p.lowercased().hasPrefix("filename="), name == nil {
                var v = String(p.dropFirst("filename=".count))
                v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                name = v.removingPercentEncoding ?? v
            }
        }
        guard var n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        for ext in [".yaml", ".yml", ".txt"] where n.lowercased().hasSuffix(ext) { n = String(n.dropLast(ext.count)) }
        return n.isEmpty ? nil : n
    }
}
