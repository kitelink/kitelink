import Foundation

/// Where KiteLink keeps everything, and the JSON files in it.
///
///     KiteLink/
///       settings.json      app + core settings
///       profiles.json      the profile list
///       profiles/<id>.yaml the profile as the provider sent it
///       overrides/global.yaml, overrides/<id>.yaml
///       core/              the core's working directory: config.yaml (generated), cache.db, geo data
///       logs/
public struct Store: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        if let root { self.root = root } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.root = base.appendingPathComponent("KiteLink", isDirectory: true)
        }
        for d in ["profiles", "overrides", "core", "logs"] {
            try? FileManager.default.createDirectory(at: self.root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
    }

    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    public var profilesFile: URL { root.appendingPathComponent("profiles.json") }
    public var coreDirectory: URL { root.appendingPathComponent("core", isDirectory: true) }
    public var runtimeConfig: URL { coreDirectory.appendingPathComponent("config.yaml") }
    public var logsDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public var coreLog: URL { logsDirectory.appendingPathComponent("core.log") }
    public func profileFile(_ id: String) -> URL { root.appendingPathComponent("profiles/\(id).yaml") }
    public func overrideFile(_ id: String?) -> URL { root.appendingPathComponent("overrides/\(id ?? "global").yaml") }

    public func loadSettings() -> AppSettings {
        (try? JSONDecoder.store.decode(AppSettings.self, from: Data(contentsOf: settingsFile))) ?? AppSettings()
    }
    public func save(_ s: AppSettings) {
        try? JSONEncoder.store.encode(s).write(to: settingsFile, options: .atomic)
    }

    public func loadProfiles() -> [Profile] {
        (try? JSONDecoder.store.decode([Profile].self, from: Data(contentsOf: profilesFile))) ?? []
    }
    public func save(_ p: [Profile]) {
        try? JSONEncoder.store.encode(p).write(to: profilesFile, options: .atomic)
    }

    public func profileYAML(_ id: String) -> String? { try? String(contentsOf: profileFile(id), encoding: .utf8) }
    public func writeProfileYAML(_ id: String, _ text: String) throws { try text.write(to: profileFile(id), atomically: true, encoding: .utf8) }
    public func removeProfileFiles(_ id: String) {
        try? FileManager.default.removeItem(at: profileFile(id))
        try? FileManager.default.removeItem(at: overrideFile(id))
    }

    public func override(_ id: String?) -> String { (try? String(contentsOf: overrideFile(id), encoding: .utf8)) ?? "" }
    public func writeOverride(_ id: String?, _ text: String) throws {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? FileManager.default.removeItem(at: overrideFile(id))
        } else {
            try text.write(to: overrideFile(id), atomically: true, encoding: .utf8)
        }
    }
}

extension JSONEncoder {
    static var store: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
extension JSONDecoder {
    static var store: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

public extension Int64 {
    /// "1.2 GB" style, for quotas and traffic.
    var bytesText: String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(self)
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(self) B" : String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, units[i])
    }
}
