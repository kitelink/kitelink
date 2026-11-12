import Foundation

/// A proxy or group as the core reports it.
public struct ProxyInfo: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var type: String
    /// For groups: the node currently in use.
    public var now: String?
    /// For groups: members in config order.
    public var all: [String]?
    public var history: [DelayPoint]?
    public var alive: Bool?
    public var udp: Bool?
    public var hidden: Bool?
    public var icon: String?
    public var fixed: String?
    public var testUrl: String?

    public var id: String { name }
    public var isGroup: Bool { all != nil }
    public var lastDelay: Int? {
        guard let d = history?.last?.delay else { return nil }
        return d
    }

    public struct DelayPoint: Codable, Equatable, Sendable {
        public var time: String?
        public var delay: Int
    }

    /// Group kinds the user can pick a node in directly.
    public var isSelector: Bool { type == "Selector" }
    public var isAutomatic: Bool { ["URLTest", "Fallback", "LoadBalance"].contains(type) }
    public var isBuiltin: Bool { ["Direct", "Reject", "RejectDrop", "Compatible", "Pass"].contains(type) }

    /// Short protocol label for a node row.
    public var typeLabel: String {
        switch type {
        case "Shadowsocks": return "ss"
        case "ShadowsocksR": return "ssr"
        case "Vmess": return "vmess"
        case "Vless": return "vless"
        case "Trojan": return "trojan"
        case "Hysteria": return "hy"
        case "Hysteria2": return "hy2"
        case "AnyTLS": return "anytls"
        case "Mieru": return "mieru"
        case "Tuic": return "tuic"
        case "WireGuard": return "wg"
        case "Socks5": return "socks"
        case "Http": return "http"
        case "Ssh": return "ssh"
        case "Snell": return "snell"
        case "Direct": return "direct"
        case "Reject", "RejectDrop": return "reject"
        case "Selector": return "select"
        case "URLTest": return "auto"
        case "Fallback": return "fallback"
        case "LoadBalance": return "balance"
        case "Relay": return "relay"
        default: return type.lowercased()
        }
    }
}

public struct ConnectionInfo: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var upload: Int64
    public var download: Int64
    public var start: String
    public var chains: [String]
    public var rule: String
    public var rulePayload: String
    public var metadata: Metadata

    public struct Metadata: Codable, Equatable, Sendable {
        public var network: String
        public var type: String
        public var host: String
        public var destinationIP: String
        public var destinationPort: String
        public var sourceIP: String
        public var sourcePort: String
        public var process: String?
        public var processPath: String?
    }

    public var target: String {
        let h = metadata.host.isEmpty ? metadata.destinationIP : metadata.host
        return "\(h):\(metadata.destinationPort)"
    }
}

public struct ConnectionsSnapshot: Codable, Sendable {
    public var downloadTotal: Int64
    public var uploadTotal: Int64
    public var connections: [ConnectionInfo]?
    public var memory: Int64?
}

public struct Traffic: Codable, Equatable, Sendable {
    public var up: Int64
    public var down: Int64
    public init(up: Int64, down: Int64) { self.up = up; self.down = down }
}

public struct LogLine: Codable, Identifiable, Equatable, Sendable {
    public var type: String
    public var payload: String
    public var id = UUID()
    enum CodingKeys: String, CodingKey { case type, payload }
}

public enum ClashAPIError: Error, LocalizedError {
    case http(Int, String)
    case notRunning
    case decode(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return msg.isEmpty ? "HTTP \(code)" : msg
        case .notRunning: return "The core is not running."
        case .decode(let s): return "Unexpected reply from the core: \(s)"
        }
    }
}

/// The mihomo external controller (REST + websocket streams). One instance per running core.
public final class ClashAPI: @unchecked Sendable {
    public let host: String
    public let port: Int
    public let secret: String
    private let session: URLSession

    public init(host: String = "127.0.0.1", port: Int, secret: String) {
        self.host = host
        self.port = port
        self.secret = secret
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.connectionProxyDictionary = [:]  // never through the proxy we are controlling
        session = URLSession(configuration: c)
    }

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: Encodable? = nil, timeout: TimeInterval? = nil) async throws -> (Data, Int) {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = host
        comps.port = port
        comps.path = path
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code >= 400 {
                let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["message"] ?? String(data: data, encoding: .utf8) ?? ""
                throw ClashAPIError.http(code, msg)
            }
            return (data, code)
        } catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
            throw ClashAPIError.notRunning
        }
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], timeout: TimeInterval? = nil) async throws -> T {
        let (data, _) = try await request("GET", path, query: query, timeout: timeout)
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ClashAPIError.decode(String(data: data.prefix(200), encoding: .utf8) ?? "") }
    }

    // MARK: - Status

    public struct Version: Codable, Sendable { public var version: String; public var meta: Bool? }
    public func version() async throws -> Version { try await get("/version") }

    public func ping() async -> Bool { (try? await version()) != nil }

    // MARK: - Proxies

    public struct ProxiesReply: Codable, Sendable { public var proxies: [String: ProxyInfo] }
    public func proxies() async throws -> [String: ProxyInfo] { try await (get("/proxies") as ProxiesReply).proxies }

    /// Groups in config order, with GLOBAL last. mihomo's GLOBAL group lists groups before nodes in config order.
    public static func orderedGroups(_ all: [String: ProxyInfo]) -> [ProxyInfo] {
        guard let global = all["GLOBAL"], let names = global.all else {
            return all.values.filter { $0.isGroup && $0.name != "GLOBAL" }.sorted { $0.name < $1.name }
        }
        var out: [ProxyInfo] = []
        for n in names {
            if let p = all[n], p.isGroup, p.hidden != true { out.append(p) }
        }
        return out
    }

    public func select(group: String, node: String) async throws {
        _ = try await request("PUT", "/proxies/\(encode(group))", body: ["name": node])
    }

    /// Lets an automatic group pick again after a manual selection fixed it.
    public func unfix(group: String) async throws {
        _ = try await request("DELETE", "/proxies/\(encode(group))")
    }

    public struct DelayReply: Codable, Sendable { public var delay: Int }
    public func delay(node: String, url: String, timeoutMs: Int) async throws -> Int {
        try await (get("/proxies/\(encode(node))/delay", query: ["url": url, "timeout": String(timeoutMs)], timeout: TimeInterval(timeoutMs) / 1000 + 5) as DelayReply).delay
    }

    /// Tests every node in a group; nodes that time out are absent from the result.
    public func delay(group: String, url: String, timeoutMs: Int) async throws -> [String: Int] {
        try await get("/group/\(encode(group))/delay", query: ["url": url, "timeout": String(timeoutMs)], timeout: TimeInterval(timeoutMs) / 1000 * 3 + 10)
    }

    // MARK: - Config

    public struct Configs: Codable, Sendable {
        public var mode: String
        public var mixedPort: Int?
        public var allowLan: Bool?
        public var logLevel: String?
        enum CodingKeys: String, CodingKey { case mode, mixedPort = "mixed-port", allowLan = "allow-lan", logLevel = "log-level" }
    }
    public func configs() async throws -> Configs { try await get("/configs") }

    public func patch(mode: ProxyMode) async throws {
        _ = try await request("PATCH", "/configs", body: ["mode": mode.rawValue])
    }

    /// Reloads the config file at `path` without restarting the process.
    public func reload(path: String) async throws {
        _ = try await request("PUT", "/configs", query: ["force": "true"], body: ["path": path], timeout: 60)
    }

    public func restart() async throws { _ = try await request("POST", "/restart") }

    public func updateGeo() async throws { _ = try await request("POST", "/configs/geo") }

    // MARK: - Connections

    public func connections() async throws -> ConnectionsSnapshot { try await get("/connections") }
    public func closeAllConnections() async throws { _ = try await request("DELETE", "/connections") }
    public func close(connection id: String) async throws { _ = try await request("DELETE", "/connections/\(encode(id))") }

    // MARK: - Streams

    /// A websocket that yields decoded JSON messages until cancelled.
    public func stream<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:], as: T.Type) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            var comps = URLComponents()
            comps.scheme = "ws"
            comps.host = host
            comps.port = port
            comps.path = path
            var q = query
            q["token"] = secret
            comps.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
            let task = session.webSocketTask(with: comps.url!)
            task.resume()
            let reader = Task {
                do {
                    while !Task.isCancelled {
                        let msg = try await task.receive()
                        let data: Data
                        switch msg {
                        case .data(let d): data = d
                        case .string(let s): data = Data(s.utf8)
                        @unknown default: continue
                        }
                        if let v = try? JSONDecoder().decode(T.self, from: data) { continuation.yield(v) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    public func traffic() -> AsyncThrowingStream<Traffic, Error> { stream("/traffic", as: Traffic.self) }
    public func logs(level: String = "info") -> AsyncThrowingStream<LogLine, Error> { stream("/logs", query: ["level": level], as: LogLine.self) }
    public func connectionsStream() -> AsyncThrowingStream<ConnectionsSnapshot, Error> { stream("/connections", as: ConnectionsSnapshot.self) }

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? s
    }
}

struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
