import Foundation
import SwiftUI
import KiteKit
import ServiceManagement

enum CoreState: Equatable {
    case stopped, starting, running(String), failed(String)
    var isRunning: Bool { if case .running = self { return true } else { return false } }
    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .running(let v): return "mihomo \(v)"
        case .failed: return "Failed"
        }
    }
}

/// Everything the windows and the menu bar show, and every action they take.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    /// KITELINK_HOME points the app at another data folder (development and tests).
    let store = Store(root: ProcessInfo.processInfo.environment["KITELINK_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) })
    @Published var settings: AppSettings { didSet { store.save(settings) } }
    @Published var profiles: [Profile] { didSet { store.save(profiles) } }
    @Published var coreState: CoreState = .stopped
    @Published var proxies: [String: ProxyInfo] = [:]
    @Published var groups: [ProxyInfo] = []
    @Published var selectedGroup: String? { didSet { autoTestIfNeeded() } }
    @Published var traffic = Traffic(up: 0, down: 0)
    @Published var testing: Set<String> = []
    @Published var updating: Set<String> = []
    @Published var notice: Notice?
    @Published var showProfiles = false
    @Published var showImport = false
    @Published var importPrefill: String = ""
    @Published var importPrefillName: String = ""

    struct Notice: Identifiable, Equatable { let id = UUID(); var text: String; var isError: Bool }
    enum OverrideTarget: Identifiable, Equatable { case global, profile(String); var id: String { if case .profile(let p) = self { return p } else { return "global" } } }

    let core = CoreProcess()
    private(set) var api: ClashAPI?
    private let secret: String = {
        var b = [UInt8](repeating: 0, count: 16); _ = SecRandomCopyBytes(kSecRandomDefault, 16, &b)
        return b.map { String(format: "%02x", $0) }.joined()
    }()
    private var trafficTask: Task<Void, Never>?
    private var updateTimer: Timer?
    private var refreshTimer: Timer?
    /// Groups already latency-tested on their own this run.
    private var autoTested: Set<String> = []

    init() {
        settings = store.loadSettings()
        profiles = store.loadProfiles()
        core.onExit = { [weak self] code in
            Task { @MainActor in self?.coreExited(code) }
        }
    }

    /// What the network services had before System Proxy went on (see SystemProxy).
    var proxyBackup: URL { store.root.appendingPathComponent("system-proxy-before.json") }

    var activeProfile: Profile? { profiles.first { $0.id == settings.activeProfileID } }
    var primaryGroup: ProxyInfo? { groups.first }
    var currentGroup: ProxyInfo? { groups.first { $0.name == selectedGroup } ?? primaryGroup }
    var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev" }

    /// What the menu bar says in one line.
    var statusLine: String {
        guard coreState.isRunning, let g = primaryGroup, let now = g.now else { return coreState.label }
        return NodeName(now).display
    }

    // MARK: - Lifecycle

    func boot() async {
        installGeoIfNeeded()
        if settings.activeProfileID == nil, let first = profiles.first { settings.activeProfileID = first.id }
        if activeProfile != nil, settings.startProxyOnLaunch { await start() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.autoUpdateTick() }
        }
        // Automatic groups move on their own and health checks fill in latency; keep the lists current.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.coreState.isRunning, NSApp.isActive || NSApp.windows.contains(where: { $0.isVisible && $0.level == .normal }) else { return }
                await self.refreshProxies()
            }
        }
        await autoUpdateTick()
    }

    func shutdown() {
        if settings.systemProxy { SystemProxy.disable(backup: proxyBackup) }
        core.stop()
    }

    /// Geo databases ship in the bundle; the core wants them next to its config.
    private func installGeoIfNeeded() {
        for (name, ext) in [("geoip", "metadb"), ("geosite", "dat"), ("country", "mmdb")] {
            let dst = store.coreDirectory.appendingPathComponent("\(name).\(ext)")
            guard !FileManager.default.fileExists(atPath: dst.path),
                  let src = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "geo") else { continue }
            try? FileManager.default.copyItem(at: src, to: dst)
        }
    }

    // MARK: - Core

    func start() async {
        guard let profile = activeProfile else { return }
        if core.isRunning { await restartCore(); return }
        coreState = .starting
        do {
            try writeRuntimeConfig(for: profile)
            try core.start(directory: store.coreDirectory, config: store.runtimeConfig, log: store.coreLog)
            let api = ClashAPI(port: settings.core.controllerPort, secret: secret)
            self.api = api
            var up = false
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !core.isRunning { break }
                if await api.ping() { up = true; break }
            }
            guard up else {
                let why = core.errors.first ?? clean(core.recentOutput.split(separator: "\n").last.map(String.init) ?? "")
                core.stop()
                coreState = .failed(explain(why))
                return
            }
            let v = (try? await api.version().version) ?? "?"
            coreState = .running(v)
            await replaySelections(profile)
            await refreshProxies()
            streamTraffic()
            // The core keeps running when a listener cannot bind; without the mixed port nothing can use it.
            if let e = core.errors.first(where: { $0.contains("Mixed") && $0.contains("listen") }) {
                notify(explain(e), error: true)
            } else if settings.systemProxy {
                await SystemProxy.enableAsync(port: settings.core.mixedPort, bypass: settings.bypass, backup: proxyBackup)
            }
        } catch {
            coreState = .failed(error.localizedDescription)
        }
    }

    /// `keepSystemProxy` is for a restart, where the proxy comes straight back on the same port.
    func stop(keepSystemProxy: Bool = false) {
        trafficTask?.cancel()
        trafficTask = nil
        core.stop()
        api = nil
        coreState = .stopped
        proxies = [:]
        groups = []
        traffic = Traffic(up: 0, down: 0)
        if settings.systemProxy, !keepSystemProxy { let b = proxyBackup; Task { await SystemProxy.disableAsync(backup: b) } }
    }

    /// Stop asked for by the user: the switch goes off with it, so the window never claims a proxy that is not there.
    func userStop() {
        let wasOn = settings.systemProxy
        stop(keepSystemProxy: true)
        if wasOn {
            settings.systemProxy = false
            let b = proxyBackup
            Task { await SystemProxy.disableAsync(backup: b) }
        }
    }

    func restartCore() async {
        stop(keepSystemProxy: true)
        await start()
    }

    private func coreExited(_ code: Int32) {
        guard coreState.isRunning || coreState == .starting else { return }
        trafficTask?.cancel()
        api = nil
        coreState = .failed("The core exited (\(code)). \(clean(core.recentOutput.split(separator: "\n").last.map(String.init) ?? ""))")
        proxies = [:]
        groups = []
        // Do not leave the Mac pointing at a port nobody listens on.
        if settings.systemProxy { let b = proxyBackup; Task { await SystemProxy.disableAsync(backup: b) } }
    }

    /// Turns the core's bind error into what to do about it.
    private func explain(_ s: String) -> String {
        guard s.contains("address already in use") else { return s }
        if let r = s.range(of: #":(\d+): bind"#, options: .regularExpression) {
            let port = s[r].dropFirst().prefix(while: { $0.isNumber })
            return "Port \(port) is in use by another app. Quit it, or change the port in Settings › Proxy."
        }
        return s
    }

    private func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"time="[^"]*" level=\w+ msg="#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
    }

    private func writeRuntimeConfig(for profile: Profile) throws {
        guard let yaml = store.profileYAML(profile.id) else { throw CoreProcess.CoreError.didNotStart("The profile file is missing; update the profile.") }
        let r = try ConfigBuilder.build(profileYAML: yaml, globalOverride: store.override(nil), profileOverride: store.override(profile.id), core: settings.core, secret: secret)
        try r.yaml.write(to: store.runtimeConfig, atomically: true, encoding: .utf8)
    }

    /// Rebuilds the runtime config and hot-reloads it (or starts the core if it is not running).
    func reload() async {
        guard let profile = activeProfile else { userStop(); return }
        guard let api, coreState.isRunning else { await start(); return }
        do {
            try writeRuntimeConfig(for: profile)
            if let why = CoreProcess.check(config: store.runtimeConfig, directory: store.coreDirectory) { throw CoreProcess.CoreError.didNotStart(why) }
            try await api.reload(path: store.runtimeConfig.path)
            autoTested = []
            await replaySelections(profile)
            await refreshProxies()
        } catch {
            notify("Reload failed: \(error.localizedDescription)", error: true)
        }
    }

    /// Settings that change listeners need a fresh process.
    func applyCoreSettings() async {
        if coreState.isRunning { await restartCore() }
    }

    // MARK: - Proxies

    func refreshProxies() async {
        guard let api else { return }
        if let all = try? await api.proxies() {
            // Only publish a change: this also runs on a timer, and an unchanged list must not redraw the window.
            if all != proxies { proxies = all }
            let ordered = ClashAPI.orderedGroups(all)
            if ordered != groups { groups = ordered }
            if selectedGroup == nil || !groups.contains(where: { $0.name == selectedGroup }) { selectedGroup = groups.first?.name }
            autoTestIfNeeded()
        }
    }

    /// Latency to show for a row: a node's own, or for a group the node it currently resolves to.
    func delay(of p: ProxyInfo) -> Int? {
        var cur = p
        var hops = 0
        while cur.isGroup, let now = cur.now, let next = proxies[now], hops < 8 { cur = next; hops += 1 }
        return cur.isGroup ? nil : cur.lastDelay
    }

    /// The first time a group is shown with no latency on any node, test it, so the list is never a column of dashes.
    private func autoTestIfNeeded() {
        guard coreState.isRunning, let g = currentGroup, !autoTested.contains(g.name), let names = g.all else { return }
        let nodes = names.compactMap { proxies[$0] }.filter { !$0.isBuiltin }
        guard !nodes.isEmpty, !nodes.contains(where: { $0.lastDelay != nil }) else { return }
        autoTested.insert(g.name)
        Task { await test(group: g.name) }
    }

    private func replaySelections(_ profile: Profile) async {
        guard let api, !profile.selections.isEmpty else { return }
        for (g, n) in profile.selections { try? await api.select(group: g, node: n) }
    }

    func select(group: String, node: String) async {
        guard let api else { return }
        do {
            try await api.select(group: group, node: node)
            if let i = profiles.firstIndex(where: { $0.id == settings.activeProfileID }) { profiles[i].selections[group] = node }
            await refreshProxies()
        } catch { notify(error.localizedDescription, error: true) }
    }

    func unfix(group: String) async {
        guard let api else { return }
        try? await api.unfix(group: group)
        if let i = profiles.firstIndex(where: { $0.id == settings.activeProfileID }) { profiles[i].selections[group] = nil }
        await refreshProxies()
    }

    func test(group: String) async {
        guard let api, !testing.contains(group) else { return }
        testing.insert(group)
        defer { testing.remove(group) }
        _ = try? await api.delay(group: group, url: settings.core.latencyURL, timeoutMs: settings.core.latencyTimeoutMs)
        await refreshProxies()
    }

    func test(node: String) async {
        guard let api else { return }
        testing.insert(node)
        defer { testing.remove(node) }
        _ = try? await api.delay(node: node, url: settings.core.latencyURL, timeoutMs: settings.core.latencyTimeoutMs)
        await refreshProxies()
    }

    func setMode(_ mode: ProxyMode) async {
        settings.core.mode = mode
        try? await api?.patch(mode: mode)
    }

    func setSystemProxy(_ on: Bool) async {
        settings.systemProxy = on
        if on {
            if !coreState.isRunning { await start() }
            else { await SystemProxy.enableAsync(port: settings.core.mixedPort, bypass: settings.bypass, backup: proxyBackup) }
        } else {
            await SystemProxy.disableAsync(backup: proxyBackup)
        }
        // The switch may have moved again while the network settings were being written.
        if settings.systemProxy != on { await setSystemProxy(settings.systemProxy) }
    }

    private func streamTraffic() {
        trafficTask?.cancel()
        guard let api else { return }
        trafficTask = Task { [weak self] in
            do {
                for try await t in api.traffic() {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.traffic = t }
                }
            } catch {}
        }
    }

    // MARK: - Profiles

    func add(subscription url: String, name: String?) async throws -> Profile {
        var p = Profile(name: name?.isEmpty == false ? name! : "Subscription", url: url.trimmingCharacters(in: .whitespacesAndNewlines))
        let r = try await Subscription.fetch(p.url!, userAgent: settings.effectiveUserAgent, proxyPort: nil)
        try store.writeProfileYAML(p.id, r.text)
        if name?.isEmpty != false, let n = r.name { p.name = n } else if name?.isEmpty != false { p.name = URL(string: p.url!)?.host ?? "Subscription" }
        p.usage = r.usage
        p.updateIntervalHours = r.updateIntervalHours ?? 24
        p.homeURL = r.homeURL
        p.updatedAt = Date()
        profiles.append(p)
        if profiles.count == 1 || settings.activeProfileID == nil { await activate(p.id) }
        return p
    }

    func add(file: URL) throws {
        let text = try String(contentsOf: file, encoding: .utf8)
        try Subscription.validate(text)
        let p = Profile(name: file.deletingPathExtension().lastPathComponent)
        try store.writeProfileYAML(p.id, text)
        var q = p; q.updatedAt = Date()
        profiles.append(q)
        if profiles.count == 1 || settings.activeProfileID == nil { Task { await activate(p.id) } }
    }

    func importFromVerge(_ items: [VergeImport.Item]) async {
        var added = 0
        var current: String?
        for it in items where !profiles.contains(where: { $0.url == it.url }) {
            var p = Profile(name: it.name, url: it.url)
            p.selections = it.selections
            p.usage = it.usage
            p.homeURL = it.homeURL
            p.updateIntervalHours = it.updateIntervalHours ?? 24
            p.updatedAt = it.updatedAt
            if let f = it.file, let text = try? String(contentsOf: f, encoding: .utf8), (try? Subscription.validate(text)) != nil {
                try? store.writeProfileYAML(p.id, text)
            } else {
                do {
                    let r = try await Subscription.fetch(it.url, userAgent: settings.effectiveUserAgent)
                    try store.writeProfileYAML(p.id, r.text)
                    p.usage = r.usage ?? p.usage
                    p.updatedAt = Date()
                } catch { p.lastError = error.localizedDescription }
            }
            profiles.append(p)
            if it.isCurrent { current = p.id }
            added += 1
        }
        // Carry on with the profile Verge was running.
        if settings.activeProfileID == nil, let id = current ?? profiles.first?.id { await activate(id) }
        notify(added == 0 ? "Nothing new to import." : "Imported \(added) profile\(added == 1 ? "" : "s") from Clash Verge Rev.", error: false)
    }

    /// `quiet` is for background refreshes: a failure is kept on the profile, not announced.
    func update(_ id: String, quiet: Bool = false) async {
        guard let i = profiles.firstIndex(where: { $0.id == id }), let url = profiles[i].url, !updating.contains(id) else { return }
        updating.insert(id)
        defer { updating.remove(id) }
        do {
            let p = profiles[i]
            let port = p.updateThroughProxy && coreState.isRunning ? settings.core.mixedPort : nil
            let r = try await Subscription.fetch(url, userAgent: p.userAgent ?? settings.effectiveUserAgent, proxyPort: port)
            try store.writeProfileYAML(id, r.text)
            profiles[i].usage = r.usage ?? profiles[i].usage
            profiles[i].homeURL = r.homeURL ?? profiles[i].homeURL
            if profiles[i].updateIntervalHours == nil { profiles[i].updateIntervalHours = r.updateIntervalHours ?? 24 }
            profiles[i].updatedAt = Date()
            profiles[i].lastError = nil
            if id == settings.activeProfileID { await reload() }
        } catch {
            guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
            profiles[i].lastError = error.localizedDescription
            if !quiet { notify("\(profiles[i].name): \(error.localizedDescription)", error: true) }
        }
    }

    func updateAll() async {
        for p in profiles where p.isRemote { await update(p.id) }
    }

    private func autoUpdateTick() async {
        guard settings.autoUpdateProfiles else { return }
        for p in profiles where p.isRemote && p.autoUpdate {
            let hours = p.updateIntervalHours ?? 24
            let due = (p.updatedAt ?? .distantPast).addingTimeInterval(TimeInterval(hours) * 3600)
            if due < Date() { await update(p.id, quiet: true) }
        }
    }

    func activate(_ id: String) async {
        guard profiles.contains(where: { $0.id == id }) else { return }
        settings.activeProfileID = id
        selectedGroup = nil
        if coreState.isRunning { await reload() } else { await start() }
    }

    func remove(_ id: String) {
        profiles.removeAll { $0.id == id }
        store.removeProfileFiles(id)
        if settings.activeProfileID == id {
            settings.activeProfileID = profiles.first?.id
            Task { if activeProfile != nil { await reload() } else { userStop() } }
        }
    }

    func edit(_ p: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p }
    }

    /// Saves an override only if the profile it applies to still makes a config the core accepts.
    func saveOverride(_ target: OverrideTarget, text: String) async throws {
        try ConfigBuilder.check(override: text)
        let profileID: String?
        switch target {
        case .global: profileID = settings.activeProfileID
        case .profile(let id): profileID = id
        }
        if let id = profileID, let yaml = store.profileYAML(id) {
            let global: String
            let own: String
            switch target {
            case .global: global = text; own = store.override(id)
            case .profile: global = store.override(nil); own = text
            }
            let trial = try ConfigBuilder.build(profileYAML: yaml, globalOverride: global, profileOverride: own, core: settings.core, secret: "check")
            let file = store.coreDirectory.appendingPathComponent("config.check.yaml")
            try trial.yaml.write(to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }
            let dir = store.coreDirectory
            let complaint = await Task.detached { CoreProcess.check(config: file, directory: dir) }.value
            if let complaint { throw CoreProcess.CoreError.didNotStart(complaint) }
        }
        switch target {
        case .global: try store.writeOverride(nil, text)
        case .profile(let id): try store.writeOverride(id, text)
        }
        if target == .global || target == .profile(settings.activeProfileID ?? "") { await reload() }
    }

    func overrideText(_ target: OverrideTarget) -> String {
        switch target {
        case .global: return store.override(nil)
        case .profile(let id): return store.override(id)
        }
    }

    // MARK: - URLs and files

    /// `clash://install-config?url=…&name=…` and `kitelink://install?url=…`.
    func handle(url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if url.isFileURL {
            do { try add(file: url) } catch { notify(error.localizedDescription, error: true) }
            return
        }
        guard let link = comps.queryItems?.first(where: { $0.name == "url" })?.value, !link.isEmpty else { return }
        importPrefill = link
        importPrefillName = comps.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
        showImport = true
    }

    /// What a terminal needs to use the proxy.
    var shellExport: String {
        let p = settings.core.mixedPort
        return "export https_proxy=http://127.0.0.1:\(p) http_proxy=http://127.0.0.1:\(p) all_proxy=socks5://127.0.0.1:\(p)"
    }

    func copyShellExport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shellExport, forType: .string)
        notify("Copied the shell proxy command.", error: false)
    }

    func notify(_ text: String, error: Bool) {
        notice = Notice(text: text, isError: error)
        let id = notice?.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(error ? 6 : 3) * 1_000_000_000)
            if self.notice?.id == id { self.notice = nil }
        }
    }

    // MARK: - App settings

    func setLaunchAtLogin(_ on: Bool) {
        settings.launchAtLogin = on
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { notify(error.localizedDescription, error: true) }
    }

    func setShowInDock(_ on: Bool) {
        settings.showInDock = on
        NSApp.setActivationPolicy(on ? .regular : .accessory)
        if on { NSApp.activate(ignoringOtherApps: true) }
    }
}
