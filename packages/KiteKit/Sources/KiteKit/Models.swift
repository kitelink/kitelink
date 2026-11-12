import Foundation

/// A profile is one Clash/mihomo configuration the user can run: a subscription (remote) or a file they brought.
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// The subscription link; nil for a profile imported from a file.
    public var url: String?
    /// Overrides the User-Agent sent to the provider (some only answer Clash clients).
    public var userAgent: String?
    public var updatedAt: Date?
    /// Hours between automatic refreshes; from the provider's `profile-update-interval` unless the user set one.
    public var updateIntervalHours: Int?
    public var autoUpdate: Bool
    /// The provider's panel, from `profile-web-page-url`.
    public var homeURL: String?
    public var usage: SubscriptionUsage?
    /// Group name → node name, replayed into the core when the profile becomes active.
    public var selections: [String: String]
    /// Fetch the subscription through the running proxy (for links only reachable from abroad).
    public var updateThroughProxy: Bool
    public var lastError: String?

    public init(id: String = Profile.newID(), name: String, url: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.autoUpdate = url != nil
        self.selections = [:]
        self.updateThroughProxy = false
    }

    public var isRemote: Bool { url != nil }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Profile"
        url = try c.decodeIfPresent(String.self, forKey: .url)
        userAgent = try c.decodeIfPresent(String.self, forKey: .userAgent)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        updateIntervalHours = try c.decodeIfPresent(Int.self, forKey: .updateIntervalHours)
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? (url != nil)
        homeURL = try c.decodeIfPresent(String.self, forKey: .homeURL)
        usage = try c.decodeIfPresent(SubscriptionUsage.self, forKey: .usage)
        selections = try c.decodeIfPresent([String: String].self, forKey: .selections) ?? [:]
        updateThroughProxy = try c.decodeIfPresent(Bool.self, forKey: .updateThroughProxy) ?? false
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
    }

    public static func newID() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<10).map { _ in chars.randomElement()! })
    }
}

/// `subscription-userinfo: upload=…; download=…; total=…; expire=…` (bytes and a unix time).
public struct SubscriptionUsage: Codable, Equatable, Sendable {
    public var upload: Int64
    public var download: Int64
    public var total: Int64?
    public var expire: Date?

    public init(upload: Int64 = 0, download: Int64 = 0, total: Int64? = nil, expire: Date? = nil) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expire = expire
    }

    public var used: Int64 { upload + download }
    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(used) / Double(total))
    }
    public var remaining: Int64? { total.map { max(0, $0 - used) } }

    public static func parse(_ header: String) -> SubscriptionUsage? {
        var u = SubscriptionUsage()
        var any = false
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, let n = Int64(kv[1].split(separator: ".").first ?? "") else { continue }
            any = true
            switch kv[0].lowercased() {
            case "upload": u.upload = n
            case "download": u.download = n
            case "total": u.total = n
            case "expire": u.expire = n > 0 ? Date(timeIntervalSince1970: TimeInterval(n)) : nil
            default: break
            }
        }
        return any ? u : nil
    }
}

/// How traffic reaches the core: the three mihomo modes.
public enum ProxyMode: String, Codable, CaseIterable, Sendable {
    case rule, global, direct

    public var title: String {
        switch self {
        case .rule: return "Rule"
        case .global: return "Global"
        case .direct: return "Direct"
        }
    }
}

/// Settings the app owns; written into every runtime config over whatever the profile says.
public struct CoreSettings: Codable, Equatable, Sendable {
    public var mixedPort: Int = 7890
    public var allowLAN: Bool = false
    public var controllerPort: Int = 9090
    public var logLevel: String = "info"
    public var mode: ProxyMode = .rule
    public var ipv6: Bool = false
    public var unifiedDelay: Bool = true
    public var tcpConcurrent: Bool = true
    /// Test URL for latency checks.
    public var latencyURL: String = "https://www.gstatic.com/generate_204"
    public var latencyTimeoutMs: Int = 5000

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CoreSettings()
        mixedPort = try c.decodeIfPresent(Int.self, forKey: .mixedPort) ?? d.mixedPort
        allowLAN = try c.decodeIfPresent(Bool.self, forKey: .allowLAN) ?? d.allowLAN
        controllerPort = try c.decodeIfPresent(Int.self, forKey: .controllerPort) ?? d.controllerPort
        logLevel = try c.decodeIfPresent(String.self, forKey: .logLevel) ?? d.logLevel
        mode = try c.decodeIfPresent(ProxyMode.self, forKey: .mode) ?? d.mode
        ipv6 = try c.decodeIfPresent(Bool.self, forKey: .ipv6) ?? d.ipv6
        unifiedDelay = try c.decodeIfPresent(Bool.self, forKey: .unifiedDelay) ?? d.unifiedDelay
        tcpConcurrent = try c.decodeIfPresent(Bool.self, forKey: .tcpConcurrent) ?? d.tcpConcurrent
        latencyURL = try c.decodeIfPresent(String.self, forKey: .latencyURL) ?? d.latencyURL
        latencyTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .latencyTimeoutMs) ?? d.latencyTimeoutMs
    }
}

/// Settings for the app shell (not the core).
public struct AppSettings: Codable, Equatable, Sendable {
    public var core = CoreSettings()
    public var activeProfileID: String?
    public var systemProxy: Bool = false
    public var bypass: String = "127.0.0.1,localhost,*.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,<local>"
    public var launchAtLogin: Bool = false
    public var showInDock: Bool = true
    public var startProxyOnLaunch: Bool = true
    /// Empty means `AppSettings.defaultUserAgent`.
    public var subscriptionUserAgent: String = ""
    public var autoUpdateProfiles: Bool = true

    public init() {}

    /// Providers decide what to send by the start of the User-Agent: "ClashMeta" first gets a mihomo profile with every
    /// protocol the core supports; the app's own name follows.
    public static let defaultUserAgent = "ClashMeta/1.19.34 KiteLink/0.1.0"
    public var effectiveUserAgent: String {
        let t = subscriptionUserAgent.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? AppSettings.defaultUserAgent : t
    }

    // Decoding tolerates missing keys, so a settings file from an older version keeps what it has.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        core = try c.decodeIfPresent(CoreSettings.self, forKey: .core) ?? d.core
        activeProfileID = try c.decodeIfPresent(String.self, forKey: .activeProfileID)
        systemProxy = try c.decodeIfPresent(Bool.self, forKey: .systemProxy) ?? d.systemProxy
        bypass = try c.decodeIfPresent(String.self, forKey: .bypass) ?? d.bypass
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        startProxyOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .startProxyOnLaunch) ?? d.startProxyOnLaunch
        subscriptionUserAgent = try c.decodeIfPresent(String.self, forKey: .subscriptionUserAgent) ?? d.subscriptionUserAgent
        autoUpdateProfiles = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateProfiles) ?? d.autoUpdateProfiles
    }
}
