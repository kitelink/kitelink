import Foundation
import Yams

/// Turns a profile into the config the core runs: profile YAML, then the global override, then the profile's own
/// override, then the keys the app owns. Overrides use the Clash Verge "Merge" convention so a Verge user's file
/// drops in unchanged: a top-level key replaces the profile's, and `prepend-rules` / `append-rules`,
/// `prepend-proxies` / `append-proxies`, `prepend-proxy-groups` / `append-proxy-groups` splice into those lists.
public enum ConfigBuilder {
    public struct Runtime: Sendable {
        public var yaml: String
        public var secret: String
    }

    public static func build(profileYAML: String, globalOverride: String?, profileOverride: String?, core: CoreSettings, secret: String) throws -> Runtime {
        var root = try parse(profileYAML, what: "profile")
        if let g = globalOverride, !g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try apply(override: try parse(g, what: "global override"), to: &root)
        }
        if let p = profileOverride, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try apply(override: try parse(p, what: "profile override"), to: &root)
        }
        force(core: core, secret: secret, into: &root)
        let yaml = try Yams.serialize(node: root, width: -1, allowUnicode: true)
        return Runtime(yaml: yaml, secret: secret)
    }

    /// Only checks that an override parses as a YAML mapping.
    public static func check(override text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = try parse(text, what: "override")
    }

    static func parse(_ text: String, what: String) throws -> Node {
        let node: Node?
        do { node = try Yams.compose(yaml: text) } catch { throw BuildError.yaml(what, "\(error)") }
        guard let n = node else { return Node.mapping([:]) }
        guard n.mapping != nil else { throw BuildError.yaml(what, "the top level must be a mapping") }
        return n
    }

    public enum BuildError: Error, LocalizedError {
        case yaml(String, String)
        public var errorDescription: String? {
            switch self { case .yaml(let what, let msg): return "Cannot read the \(what): \(msg)" }
        }
    }

    static let splices: [(key: String, list: String, prepend: Bool)] = [
        ("prepend-rules", "rules", true), ("append-rules", "rules", false),
        ("prepend-proxies", "proxies", true), ("append-proxies", "proxies", false),
        ("prepend-proxy-groups", "proxy-groups", true), ("append-proxy-groups", "proxy-groups", false),
    ]

    static func apply(override: Node, to root: inout Node) throws {
        guard let m = override.mapping else { return }
        for (k, v) in m {
            guard let key = k.string else { continue }
            if let s = splices.first(where: { $0.key == key }) {
                guard let items = v.sequence else { continue }
                var list = root[s.list]?.sequence ?? Node.Sequence()
                if s.prepend { list.insert(contentsOf: items, at: 0) } else { list.append(contentsOf: items) }
                root[s.list] = Node.sequence(list)
            } else {
                root[key] = v
            }
        }
    }

    /// Keys the app decides. The profile's listeners go away so only the mixed port is open.
    static func force(core: CoreSettings, secret: String, into root: inout Node) {
        remove(["port", "socks-port", "redir-port", "tproxy-port", "external-controller-unix", "external-controller-pipe", "external-controller-cors", "external-ui", "external-ui-url", "external-ui-name", "external-controller-tls", "secret"], from: &root)
        root["mixed-port"] = Node(String(core.mixedPort), .implicit, .plain)
        root["allow-lan"] = Node(core.allowLAN ? "true" : "false", .implicit, .plain)
        if core.allowLAN { root["bind-address"] = Node("*") } else { remove(["bind-address"], from: &root) }
        root["mode"] = Node(core.mode.rawValue)
        root["log-level"] = Node(core.logLevel)
        root["ipv6"] = Node(core.ipv6 ? "true" : "false", .implicit, .plain)
        root["unified-delay"] = Node(core.unifiedDelay ? "true" : "false", .implicit, .plain)
        root["tcp-concurrent"] = Node(core.tcpConcurrent ? "true" : "false", .implicit, .plain)
        root["external-controller"] = Node("127.0.0.1:\(core.controllerPort)")
        root["secret"] = Node(secret)
        // Selections are replayed by the app and remembered by the core across restarts.
        var profile = root["profile"]?.mapping ?? Node.Mapping()
        profile["store-selected"] = Node("true", .implicit, .plain)
        root["profile"] = Node.mapping(profile)
        // TUN needs a privileged helper, which this version does not ship.
        if var tun = root["tun"]?.mapping {
            tun["enable"] = Node("false", .implicit, .plain)
            root["tun"] = Node.mapping(tun)
        }
    }

    /// Assigning nil through Yams' subscript keeps the key; this drops it.
    static func remove(_ keys: [String], from root: inout Node) {
        guard let m = root.mapping else { return }
        root = Node.mapping(Node.Mapping(m.filter { pair in !keys.contains(pair.key.string ?? "") }))
    }

    /// Node names and the groups they belong to, read from the profile itself (for the UI before the core is up).
    public static func groups(in profileYAML: String) -> [(name: String, type: String, members: [String])] {
        guard let root = try? Yams.compose(yaml: profileYAML), let groups = root["proxy-groups"]?.sequence else { return [] }
        return groups.compactMap { g in
            guard let name = g["name"]?.string else { return nil }
            return (name, g["type"]?.string ?? "select", g["proxies"]?.sequence?.compactMap { $0.string } ?? [])
        }
    }
}
