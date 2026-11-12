import Foundation
import Yams

/// Reads Clash Verge Rev's profile list so its subscriptions can be brought over in one step, offline.
public enum VergeImport {
    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var url: String
        public var file: URL?
        public var selections: [String: String]
        public var usage: SubscriptionUsage?
        public var homeURL: String?
        public var updateIntervalHours: Int?
        public var updatedAt: Date?
        /// The profile Clash Verge Rev is running.
        public var isCurrent = false
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev")
    }

    public static func isInstalled(at dir: URL = defaultDirectory) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("profiles.yaml").path)
    }

    public static func load(from dir: URL = defaultDirectory) throws -> [Item] {
        let text = try String(contentsOf: dir.appendingPathComponent("profiles.yaml"), encoding: .utf8)
        guard let root = try Yams.compose(yaml: text), let items = root["items"]?.sequence else { return [] }
        let current = root["current"]?.string
        var out: [Item] = []
        for it in items {
            guard it["type"]?.string == "remote", let url = it["url"]?.string, !url.isEmpty else { continue }
            let uid = it["uid"]?.string ?? Profile.newID()
            var item = Item(id: uid, name: it["name"]?.string ?? "Imported", url: url, selections: [:])
            item.isCurrent = uid == current
            if let f = it["file"]?.string {
                let u = dir.appendingPathComponent("profiles").appendingPathComponent(f)
                if FileManager.default.fileExists(atPath: u.path) { item.file = u }
            }
            if let sel = it["selected"]?.sequence {
                for s in sel {
                    if let g = s["name"]?.string, let n = s["now"]?.string { item.selections[g] = n }
                }
            }
            if let extra = it["extra"]?.mapping {
                var u = SubscriptionUsage()
                u.upload = extra["upload"]?.int.map(Int64.init) ?? 0
                u.download = extra["download"]?.int.map(Int64.init) ?? 0
                u.total = extra["total"]?.int.map(Int64.init)
                if let e = extra["expire"]?.int, e > 0 { u.expire = Date(timeIntervalSince1970: TimeInterval(e)) }
                item.usage = u
            }
            item.homeURL = it["home"]?.string
            if let m = it["option"]?["update_interval"]?.int, m > 0 { item.updateIntervalHours = max(1, m / 60) }
            if let t = it["updated"]?.int { item.updatedAt = Date(timeIntervalSince1970: TimeInterval(t)) }
            out.append(item)
        }
        return out
    }
}
