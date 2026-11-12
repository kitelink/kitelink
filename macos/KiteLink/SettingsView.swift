import SwiftUI
import KiteKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ProxySettings().tabItem { Label("Proxy", systemImage: "network") }
            CoreSettingsView().tabItem { Label("Core", systemImage: "cpu") }
            AboutView().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { m.settings.launchAtLogin }, set: { m.setLaunchAtLogin($0) }))
            Toggle("Show in Dock", isOn: Binding(get: { m.settings.showInDock }, set: { m.setShowInDock($0) }))
            Toggle("Start the proxy when KiteLink opens", isOn: $m.settings.startProxyOnLaunch)
            Toggle("Update subscriptions automatically", isOn: $m.settings.autoUpdateProfiles)
            TextField("Subscription User-Agent", text: $m.settings.subscriptionUserAgent, prompt: Text(AppSettings.defaultUserAgent))
                .help("Providers choose what to send by the start of this; leave empty for the default")
        }
        .formStyle(.grouped)
        .frame(height: 250)
    }
}

struct ProxySettings: View {
    @EnvironmentObject var m: AppModel
    @State private var port = ""
    @State private var controller = ""
    var body: some View {
        Form {
            Section("Listener") {
                TextField("Mixed port (HTTP + SOCKS)", text: $port).onSubmit(applyPorts)
                Toggle("Allow connections from the LAN", isOn: Binding(get: { m.settings.core.allowLAN }, set: { m.settings.core.allowLAN = $0; Task { await m.applyCoreSettings() } }))
                TextField("Controller port", text: $controller).onSubmit(applyPorts)
                HStack { Spacer(); Button("Apply", action: applyPorts).disabled(port == String(m.settings.core.mixedPort) && controller == String(m.settings.core.controllerPort)) }
            }
            Section("System proxy bypass") {
                TextEditor(text: $m.settings.bypass).font(.system(size: 12, design: .monospaced)).frame(height: 80)
                Text("Hosts and networks that skip the proxy, comma separated. Applied the next time System Proxy is switched on.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Latency test") {
                TextField("URL", text: $m.settings.core.latencyURL)
                TextField("Timeout (ms)", value: $m.settings.core.latencyTimeoutMs, format: .number)
            }
        }
        .formStyle(.grouped)
        .onAppear { port = String(m.settings.core.mixedPort); controller = String(m.settings.core.controllerPort) }
    }
    func applyPorts() {
        guard let p = Int(port), (1...65535).contains(p), let c = Int(controller), (1...65535).contains(c), p != c else { return }
        guard p != m.settings.core.mixedPort || c != m.settings.core.controllerPort else { return }
        m.settings.core.mixedPort = p
        m.settings.core.controllerPort = c
        Task { await m.applyCoreSettings() }
    }
}

struct CoreSettingsView: View {
    @EnvironmentObject var m: AppModel
    @State private var showOverride = false
    var body: some View {
        Form {
            Section {
                LabeledContent("Core", value: m.coreState.label)
                LabeledContent("Controller", value: "127.0.0.1:\(m.settings.core.controllerPort)")
                Picker("Log level", selection: Binding(get: { m.settings.core.logLevel }, set: { m.settings.core.logLevel = $0; Task { await m.reload() } })) {
                    ForEach(["silent", "error", "warning", "info", "debug"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("IPv6", isOn: Binding(get: { m.settings.core.ipv6 }, set: { m.settings.core.ipv6 = $0; Task { await m.reload() } }))
                Toggle("Unified delay", isOn: Binding(get: { m.settings.core.unifiedDelay }, set: { m.settings.core.unifiedDelay = $0; Task { await m.reload() } }))
                    .help("Latency without the handshake, so nodes compare fairly")
                Toggle("TCP concurrent", isOn: Binding(get: { m.settings.core.tcpConcurrent }, set: { m.settings.core.tcpConcurrent = $0; Task { await m.reload() } }))
            }
            Section {
                HStack {
                    Button("Global Override…") { showOverride = true }
                    Button("Update Geo Data") { Task { try? await m.api?.updateGeo() } }.disabled(!m.coreState.isRunning)
                    Button("Open Data Folder") { NSWorkspace.shared.open(m.store.root) }
                }
                Text("TUN mode is not in this version: it needs a privileged helper, which is planned.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showOverride) { OverrideEditor(target: .global).environmentObject(m) }
    }
}

struct AboutView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(spacing: 12) {
            KiteMark(size: 96, zoom: 1.3)
            Text("KiteLink").font(.title2.weight(.semibold))
            Text("Version \(m.version) · \(m.coreState.label)").foregroundStyle(.secondary).font(.callout)
            Text("A native proxy client for Clash and mihomo profiles. Paste a link, pick a node, fly.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).font(.callout).frame(maxWidth: 360)
            HStack(spacing: 16) {
                Link("github.com/kitelink/kitelink", destination: URL(string: "https://github.com/kitelink/kitelink")!)
                Link("MIT License", destination: URL(string: "https://github.com/kitelink/kitelink/blob/main/LICENSE")!)
            }.font(.callout)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
