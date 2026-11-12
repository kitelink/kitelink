import SwiftUI
import KiteKit
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Rectangle().fill(Kite.hairline).frame(height: 1)
            if m.profiles.isEmpty {
                Onboarding()
            } else {
                HStack(spacing: 0) {
                    GroupSidebar().frame(width: 232)
                    Rectangle().fill(Kite.hairline).frame(width: 1)
                    NodeList()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Kite.bg)
        .background(WindowSetup())
        .overlay(alignment: .bottom) { NoticeView() }
        .frame(minWidth: 760, minHeight: 480)
        .sheet(isPresented: $m.showProfiles) { ProfilesSheet().environmentObject(m) }
        .sheet(isPresented: $m.showImport) { ImportSheet(prefill: m.importPrefill, prefillName: m.importPrefillName).environmentObject(m) }
        .onOpenURL { m.handle(url: $0) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, ["yaml", "yml"].contains(url.pathExtension.lowercased()) else { return }
                    Task { @MainActor in m.handle(url: url) }
                }
            }
            return true
        }
    }
}

// ---------------------------------------------------------------------------------------------- the bar

struct TopBar: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 78)
            Lockup()
            if !m.profiles.isEmpty { ProfileMenu() }
            Spacer()
            if !m.profiles.isEmpty {
                ModePicker()
                SystemProxyToggle()
            }
        }
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Kite.bar)
    }
}

struct ProfileMenu: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Menu {
            ForEach(m.profiles) { p in
                Button { Task { await m.activate(p.id) } } label: {
                    if p.id == m.settings.activeProfileID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
            Divider()
            Button("Add Subscription…") { m.importPrefill = ""; m.importPrefillName = ""; m.showImport = true }
            Button("Manage Profiles…") { m.showProfiles = true }
        } label: {
            (Text(m.activeProfile?.name ?? "No profile").font(.system(size: 13, weight: .medium))
                + Text("  ") + Text(Image(systemName: "chevron.down")).font(.system(size: 8, weight: .bold)).foregroundColor(.secondary))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch profile")
    }
}

struct ModePicker: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Picker("Mode", selection: Binding(get: { m.settings.core.mode }, set: { v in Task { await m.setMode(v) } })) {
            ForEach(ProxyMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 200)
        .help("Rule follows the profile's rules; Global sends everything through the selected node; Direct bypasses the proxy")
    }
}

struct SystemProxyToggle: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Toggle("System Proxy", isOn: Binding(get: { m.settings.systemProxy }, set: { v in Task { await m.setSystemProxy(v) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Kite.accent)
        }
        .help(m.coreState.label)
    }
    var dot: Color {
        switch m.coreState {
        case .running: return m.settings.systemProxy ? Kite.good : Kite.fair
        case .starting: return Kite.fair
        case .stopped: return .secondary.opacity(0.4)
        case .failed: return Kite.poor
        }
    }
}

// ---------------------------------------------------------------------------------------------- groups

struct GroupSidebar: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(m.groups) { g in GroupRow(group: g, selected: g.name == m.currentGroup?.name) { m.selectedGroup = g.name } }
                }
                .padding(8)
            }
            if case .failed(let why) = m.coreState {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Core failed", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(Kite.poor)
                    Text(why).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                    Button("Retry") { Task { await m.start() } }.controlSize(.small)
                }
                .padding(10)
            } else if m.groups.isEmpty {
                VStack(spacing: 8) {
                    if m.coreState == .starting { ProgressView().controlSize(.small) }
                    Text(m.coreState == .stopped ? "Proxy is off" : m.coreState.label).font(.caption).foregroundStyle(.secondary)
                    if m.coreState == .stopped { Button("Start") { Task { await m.start() } }.controlSize(.small) }
                }
                .frame(maxHeight: .infinity)
            }
            Rectangle().fill(Kite.hairline).frame(height: 1)
            Footer()
        }
        .background(Kite.side)
    }
}

struct GroupRow: View {
    var group: ProxyInfo
    var selected: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let now = group.now {
                        Text(NodeName(now).display).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if group.isAutomatic { Tag(text: group.typeLabel, tint: group.fixed != nil ? Kite.accent : .secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Kite.rowSelected : hover ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct Footer: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold))
                Text(m.traffic.down.bytesText + "/s")
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.up").font(.system(size: 8, weight: .bold))
                Text(m.traffic.up.bytesText + "/s")
            }
            Spacer()
            Button { m.copyShellExport() } label: { Text(verbatim: ":\(m.settings.core.mixedPort)") }
                .buttonStyle(.plain)
                .help("127.0.0.1:\(m.settings.core.mixedPort) (HTTP + SOCKS) · \(m.coreState.label) — click to copy the shell proxy command")
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

// ---------------------------------------------------------------------------------------------- nodes

struct NodeList: View {
    @EnvironmentObject var m: AppModel
    @State private var filter = ""
    @State private var sortByLatency = false

    var nodes: [ProxyInfo] {
        guard let g = m.currentGroup, let names = g.all else { return [] }
        var list = names.compactMap { m.proxies[$0] }
        if !filter.isEmpty {
            let f = filter.lowercased()
            list = list.filter { $0.name.lowercased().contains(f) || $0.typeLabel.contains(f) || (NodeName($0.name).region?.lowercased() == f) }
        }
        if sortByLatency {
            list.sort { a, b in
                switch (m.delay(of: a).flatMap { $0 > 0 ? $0 : nil }, m.delay(of: b).flatMap { $0 > 0 ? $0 : nil }) {
                case let (x?, y?): return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return false
                }
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            if let g = m.currentGroup {
                HStack(spacing: 10) {
                    Text(g.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Tag(text: g.typeLabel)
                    Text("\(g.all?.count ?? 0)").font(.caption).foregroundStyle(.secondary)
                    if g.isAutomatic && g.fixed != nil {
                        Button("Let it choose") { Task { await m.unfix(group: g.name) } }.controlSize(.small).help("Clear the manual pick so the group tests and chooses again")
                    }
                    Spacer()
                    TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 150)
                    Toggle(isOn: $sortByLatency) { Image(systemName: "arrow.up.arrow.down") }.toggleStyle(.button).controlSize(.small).help("Sort by latency")
                    Button {
                        Task { await m.test(group: g.name) }
                    } label: {
                        if m.testing.contains(g.name) { ProgressView().controlSize(.small).frame(width: 14) } else { Image(systemName: "bolt.fill") }
                    }
                    .controlSize(.small)
                    .disabled(m.testing.contains(g.name))
                    .help("Test latency of every node in this group")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                ScrollViewReader { scroller in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(nodes) { n in
                                NodeRow(node: n, delay: m.delay(of: n), selected: g.now == n.name, testing: m.testing.contains(n.name)) {
                                    Task { await m.select(group: g.name, node: n.name) }
                                } test: {
                                    Task { await m.test(node: n.name) }
                                }
                                .id(n.name)
                            }
                        }
                        .padding(.horizontal, 8).padding(.bottom, 12)
                    }
                    // Open a group on the node it is using, not at the top of a hundred rows.
                    .onChange(of: g.name, initial: true) { _, _ in
                        if let now = g.now { DispatchQueue.main.async { scroller.scrollTo(now, anchor: .center) } }
                    }
                }
            } else {
                Spacer()
            }
        }
    }
}

struct NodeRow: View {
    var node: ProxyInfo
    var delay: Int?
    var selected: Bool
    var testing: Bool
    var action: () -> Void
    var test: () -> Void
    @State private var hover = false

    var body: some View {
        let n = NodeName(node.name)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Kite.accent).frame(width: 14).opacity(selected ? 1 : 0)
                FlagView(name: n, isGroup: node.isGroup)
                Text(n.title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 8)
                Tag(text: node.typeLabel)
                Group {
                    if testing { ProgressView().controlSize(.mini) }
                    else if let d = delay { Text(d > 0 ? "\(d) ms" : "timeout").foregroundStyle(Kite.latency(d)) }
                    else { Text("—").foregroundStyle(Kite.latency(nil)) }
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 62, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Kite.rowSelected : hover ? Color.primary.opacity(0.04) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Test Latency") { test() }
            Button("Copy Name") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(node.name, forType: .string) }
        }
    }
}

// ---------------------------------------------------------------------------------------------- first run

struct Onboarding: View {
    @EnvironmentObject var m: AppModel
    @State private var link = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showVerge = false

    var body: some View {
        VStack(spacing: 18) {
            KiteMark(size: 104)
            VStack(spacing: 6) {
                Text("Add your subscription").font(.system(size: 22, weight: .semibold))
                Text("Paste the link your provider gave you. KiteLink keeps it fresh and puts your nodes in the menu bar.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            HStack(spacing: 8) {
                TextField("https://…", text: $link).textFieldStyle(.roundedBorder).frame(width: 340).onSubmit { submit() }
                Button(action: submit) {
                    if busy { ProgressView().controlSize(.small).frame(width: 40) } else { Text("Import").frame(width: 40) }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Kite.accent).disabled(busy || link.isEmpty)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Kite.poor).frame(maxWidth: 400) }
            HStack(spacing: 18) {
                if VergeImport.isInstalled() { Button("Import from Clash Verge Rev…") { showVerge = true } }
                Button("Open a profile file…") { openFile() }
            }
            .buttonStyle(.link).font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showVerge) { VergeImportSheet().environmentObject(m) }
    }

    func submit() {
        guard !link.isEmpty, !busy else { return }
        busy = true; error = nil
        Task {
            do { _ = try await m.add(subscription: link, name: nil) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    func openFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType.yaml, UTType(filenameExtension: "yml") ?? .yaml]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { m.handle(url: u) }
    }
}

struct NoticeView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        if let n = m.notice {
            HStack(spacing: 8) {
                Image(systemName: n.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill").foregroundStyle(n.isError ? Kite.poor : Kite.good)
                Text(n.text).font(.callout).lineLimit(3)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { m.notice = nil }
        }
    }
}
