import SwiftUI
import KiteKit

@main
struct KiteLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("KiteLink", id: "main") {
            MainView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Subscription…") { model.importPrefill = ""; model.importPrefillName = ""; model.showImport = true }.keyboardShortcut("n")
                Button("Manage Profiles…") { model.showProfiles = true }.keyboardShortcut("p")
                Button("Update All Profiles") { Task { await model.updateAll() } }.keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandMenu("Proxy") {
                Toggle("System Proxy", isOn: Binding(get: { model.settings.systemProxy }, set: { v in Task { await model.setSystemProxy(v) } })).keyboardShortcut("t")
                Divider()
                ForEach(Array(ProxyMode.allCases.enumerated()), id: \.element) { i, mode in
                    Toggle(mode.title, isOn: Binding(get: { model.settings.core.mode == mode }, set: { _ in Task { await model.setMode(mode) } }))
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
                }
                Divider()
                Button("Test Latency of Group") { if let g = model.currentGroup { Task { await model.test(group: g.name) } } }.keyboardShortcut("l")
                Button(model.coreState.isRunning ? "Restart Core" : "Start Core") { Task { await model.restartCore() } }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Stop Core") { model.userStop() }.disabled(!model.coreState.isRunning)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Console") { openWindow(id: "console") }.keyboardShortcut("c", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Button("KiteLink on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/kitelink/kitelink")!) }
            }
        }

        Window("Console", id: "console") {
            ConsoleView().environmentObject(model)
        }
        .defaultSize(width: 820, height: 480)

        Settings {
            SettingsView().environmentObject(model)
        }

        MenuBarExtra {
            StatusMenu().environmentObject(model)
        } label: {
            Image(model.settings.systemProxy && model.coreState.isRunning ? "StatusIcon" : "StatusIconOff")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The menu bar menu: the one place a light user needs. Status, the switch, the mode and the nodes.
struct StatusMenu: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(m.statusLine)
        Toggle("System Proxy", isOn: Binding(get: { m.settings.systemProxy }, set: { v in Task { await m.setSystemProxy(v) } }))
        Divider()
        Picker("Mode", selection: Binding(get: { m.settings.core.mode }, set: { v in Task { await m.setMode(v) } })) {
            ForEach(ProxyMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.inline)
        Divider()
        ForEach(m.groups.prefix(12)) { g in
            Menu {
                ForEach((g.all ?? []).compactMap { m.proxies[$0] }) { n in
                    Button {
                        Task { await m.select(group: g.name, node: n.name) }
                    } label: {
                        let name = NodeName(n.name)
                        let delay = n.lastDelay.map { $0 > 0 ? "  \($0) ms" : "  timeout" } ?? ""
                        if g.now == n.name {
                            Label(name.display + delay, systemImage: "checkmark")
                        } else {
                            Text(name.display + delay)
                        }
                    }
                }
                Divider()
                Button("Test Latency") { Task { await m.test(group: g.name) } }
            } label: {
                Text(g.name + (g.now.map { " — " + NodeName($0).display } ?? ""))
            }
        }
        if m.profiles.count > 1 {
            Divider()
            Picker("Profile", selection: Binding(get: { m.settings.activeProfileID ?? "" }, set: { id in Task { await m.activate(id) } })) {
                ForEach(m.profiles) { Text($0.name).tag($0.id) }
            }
        }
        Divider()
        Button("Copy Shell Proxy Command") { m.copyShellExport() }.keyboardShortcut("c")
        Button("Open KiteLink") { openMain() }.keyboardShortcut("o")
        Button("Settings…") { NSApp.activate(ignoringOtherApps: true); openSettings() }.keyboardShortcut(",")
        Divider()
        Button("Quit KiteLink") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true || $0.title == "KiteLink" }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signals: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let m = AppModel.shared
        if !m.settings.showInDock { NSApp.setActivationPolicy(.accessory) }
        // `kill`, logout and Ctrl-C end the app without applicationWillTerminate; stop the core and the system proxy first.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { MainActor.assumeIsolated { AppModel.shared.shutdown() }; exit(0) }
            src.resume()
            signals.append(src)
        }
        #if DEBUG
        DebugServer.startIfRequested()
        #endif
        Task { @MainActor in await m.boot() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { MainActor.assumeIsolated { AppModel.shared.handle(url: u) } }
    }
}
