import Foundation

/// macOS system proxy through `networksetup`, which an admin user can run without a prompt. Applied to every enabled
/// network service (Wi-Fi, Ethernet, …). What each service had before is saved when the proxy goes on and put back
/// when it goes off, so KiteLink can sit next to another client (or a company proxy) without wiping its settings.
enum SystemProxy {
    /// One change at a time, off the main thread: a dozen `networksetup` calls take a second or two.
    private static let queue = DispatchQueue(label: "dev.kitelink.systemproxy")

    static func enableAsync(port: Int, bypass: String, backup: URL) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { enable(port: port, bypass: bypass, backup: backup); c.resume() }
        }
    }

    static func disableAsync(backup: URL) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { disable(backup: backup); c.resume() }
        }
    }

    struct Entry: Codable, Equatable {
        var enabled: Bool
        var server: String
        var port: Int
    }
    struct Saved: Codable {
        var web: Entry
        var secure: Entry
        var socks: Entry
        var bypass: [String]
    }

    private static let kinds: [(get: String, set: String, state: String, key: WritableKeyPath<Saved, Entry>)] = [
        ("-getwebproxy", "-setwebproxy", "-setwebproxystate", \.web),
        ("-getsecurewebproxy", "-setsecurewebproxy", "-setsecurewebproxystate", \.secure),
        ("-getsocksfirewallproxy", "-setsocksfirewallproxy", "-setsocksfirewallproxystate", \.socks),
    ]

    static func services() -> [String] {
        let out = run(["-listallnetworkservices"])
        return out.split(separator: "\n").dropFirst().map(String.init).filter { !$0.hasPrefix("*") && !$0.isEmpty }
    }

    static func enable(port: Int, bypass: String, backup: URL) {
        let domains = bypass.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let all = services()
        // Keep the first snapshot: switching on twice must not save our own settings as "before".
        if !FileManager.default.fileExists(atPath: backup.path) {
            var before: [String: Saved] = [:]
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: all.count) { i in
                let s = all[i]
                let saved = Saved(web: read("-getwebproxy", s), secure: read("-getsecurewebproxy", s), socks: read("-getsocksfirewallproxy", s), bypass: readBypass(s))
                let ours = Entry(enabled: true, server: "127.0.0.1", port: port)
                if saved.web == ours && saved.secure == ours { return }  // left on by a previous run of ours
                lock.lock(); before[s] = saved; lock.unlock()
            }
            if let data = try? JSONEncoder().encode(before) { try? data.write(to: backup, options: .atomic) }
        }
        DispatchQueue.concurrentPerform(iterations: all.count) { i in
            let s = all[i]
            for k in kinds { run([k.set, s, "127.0.0.1", String(port)]) }
            run(["-setproxybypassdomains", s] + (domains.isEmpty ? ["Empty"] : domains))
        }
    }

    static func disable(backup: URL) {
        let before = (try? Data(contentsOf: backup)).flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:]
        try? FileManager.default.removeItem(at: backup)
        let all = services()
        DispatchQueue.concurrentPerform(iterations: all.count) { i in
            let s = all[i]
            if let saved = before[s] {
                for k in kinds {
                    let e = saved[keyPath: k.key]
                    if e.enabled, !e.server.isEmpty, e.port > 0 { run([k.set, s, e.server, String(e.port)]) } else { run([k.state, s, "off"]) }
                }
                run(["-setproxybypassdomains", s] + (saved.bypass.isEmpty ? ["Empty"] : saved.bypass))
            } else {
                for k in kinds { run([k.state, s, "off"]) }
            }
        }
    }

    /// Whether the first enabled service already points its web proxy at this port.
    static func isEnabled(port: Int) -> Bool {
        guard let s = services().first(where: { read("-getwebproxy", $0).enabled }) else { return false }
        return read("-getwebproxy", s) == Entry(enabled: true, server: "127.0.0.1", port: port)
    }

    private static func read(_ flag: String, _ service: String) -> Entry {
        var e = Entry(enabled: false, server: "", port: 0)
        for line in run([flag, service]).split(separator: "\n") {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "Enabled": e.enabled = kv[1] == "Yes"
            case "Server": e.server = kv[1]
            case "Port": e.port = Int(kv[1]) ?? 0
            default: break
            }
        }
        return e
    }

    private static func readBypass(_ service: String) -> [String] {
        let out = run(["-getproxybypassdomains", service])
        if out.contains("There aren't any") { return [] }
        return out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    @discardableResult
    private static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
