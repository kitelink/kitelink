import SwiftUI
import KiteKit
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var m: AppModel
    /// Follows the drag; written to the settings when the drag ends.
    @State private var sidebarWidth = CGFloat(AppModel.shared.settings.sidebarWidth)

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Rectangle().fill(Kite.hairline).frame(height: 1)
            if m.profiles.isEmpty {
                Onboarding()
            } else {
                HStack(spacing: 0) {
                    GroupSidebar(compact: sidebarWidth < 180).frame(width: sidebarWidth)
                    SidebarDivider(width: $sidebarWidth) { m.settings.sidebarWidth = Double(sidebarWidth) }
                    NodeList()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Kite.bg)
        .background(WindowSetup())
        .overlay(alignment: .bottom) { NoticeView() }
        .frame(minWidth: 760, minHeight: 520)
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
    /// Narrow: the names get the whole row.
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(m.groups) { g in GroupRow(group: g, selected: g.name == m.currentGroup?.name, compact: compact) { m.selectedGroup = g.name } }
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
    var compact = false
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
                if group.isAutomatic, !compact { Tag(text: group.typeLabel, tint: group.fixed != nil ? Kite.accent : .secondary).fixedSize() }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Kite.rowSelected : hover ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(group.isAutomatic ? "\(group.name) · \(group.typeLabel)" : group.name)
    }
}

struct Footer: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        // As much as fits: both rates and the port, then the rates, then the rates stacked.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { down; up; Spacer(minLength: 6); port }
            HStack(spacing: 10) { down; up; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 3) { down; up }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var down: some View { rate("arrow.down", m.traffic.down) }
    private var up: some View { rate("arrow.up", m.traffic.up) }

    private func rate(_ icon: String, _ value: Int64) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(value.bytesText + "/s").lineLimit(1).fixedSize()
        }
    }

    private var port: some View {
        Button { m.copyShellExport() } label: { Text(verbatim: ":\(m.settings.core.mixedPort)").lineLimit(1).fixedSize() }
            .buttonStyle(.plain)
            .help("127.0.0.1:\(m.settings.core.mixedPort) (HTTP + SOCKS) · \(m.coreState.label) — click to copy the shell proxy command")
    }
}

/// The line between the groups and the nodes. Drag it to resize the group list; double-click for the default width.
struct SidebarDivider: View {
    @Binding var width: CGFloat
    var commit: () -> Void
    static let range: ClosedRange<CGFloat> = 132...360

    var body: some View {
        Rectangle().fill(Kite.hairline).frame(width: 1)
            .overlay(Grip(width: $width, commit: commit).frame(width: 9))
            .zIndex(1)
    }

    /// AppKit, because the window moves when its background is dragged and this strip must not count as background.
    struct Grip: NSViewRepresentable {
        @Binding var width: CGFloat
        var commit: () -> Void

        func makeNSView(context: Context) -> GripView { GripView() }
        func updateNSView(_ v: GripView, context: Context) {
            v.current = { width }
            v.change = { width = min(max($0, SidebarDivider.range.lowerBound), SidebarDivider.range.upperBound) }
            v.commit = commit
        }
    }

    final class GripView: NSView {
        var current: () -> CGFloat = { 0 }
        var change: (CGFloat) -> Void = { _ in }
        var commit: () -> Void = {}
        private var startX: CGFloat = 0
        private var startWidth: CGFloat = 0

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

        override func mouseDown(with e: NSEvent) {
            if e.clickCount == 2 {
                change(CGFloat(AppSettings.defaultSidebarWidth))
                commit()
                return
            }
            startX = e.locationInWindow.x
            startWidth = current()
        }
        override func mouseDragged(with e: NSEvent) { change(startWidth + e.locationInWindow.x - startX) }
        override func mouseUp(with e: NSEvent) { if e.clickCount < 2 { commit() } }
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

/// The first screen: one column, one job. The mark over a dawn glow, what to do in a line, the link field as the only
/// strong element, and the two other ways in as quiet cards that say what they will find.
struct Onboarding: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var link = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showVerge = false
    @State private var vergeCount = 0
    @State private var aloft = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            DawnGlow()
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                KiteMark(size: 88)
                    .shadow(color: Kite.lilac.opacity(0.4), radius: 28, y: 12)
                    .offset(y: aloft ? -4 : 4)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: aloft)
                    .padding(.bottom, 20)
                Text("Add your subscription")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.6)
                Text("Paste the link from your provider. KiteLink keeps it fresh\nand puts every node in your menu bar.")
                    .font(.system(size: 13.5)).lineSpacing(3)
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.top, 9)
                linkField.padding(.top, 26)
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Kite.poor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8).padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Rectangle().fill(Kite.hairline).frame(height: 1)
                    Text("or").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                    Rectangle().fill(Kite.hairline).frame(height: 1)
                }
                .padding(.vertical, 16)
                HStack(spacing: 10) {
                    if vergeCount > 0 {
                        EntryCard(icon: "square.and.arrow.down", title: "From Clash Verge Rev",
                                  detail: "\(vergeCount) subscription\(vergeCount == 1 ? "" : "s") found") { showVerge = true }
                    }
                    EntryCard(icon: "doc.text", title: "Open a profile file", detail: "Clash or mihomo .yaml") { openFile() }
                }
                Spacer(minLength: 12)
                Steps().padding(.bottom, 18)
            }
            .frame(width: 452)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showVerge) { VergeImportSheet().environmentObject(m) }
        .onAppear {
            aloft = true
            focused = true
            vergeCount = (try? VergeImport.load().count) ?? 0
        }
    }

    /// Field and button as one control: the only thing on the screen with weight.
    private var linkField: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(focused ? Kite.accent : Color.secondary)
            TextField("Paste your subscription link", text: $link)
                .textFieldStyle(.plain).font(.system(size: 14))
                .focused($focused)
                .onSubmit(submit)
            Button(action: submit) {
                Group {
                    if busy { ProgressView().controlSize(.small) } else { Text("Import").font(.system(size: 13, weight: .semibold)) }
                }
                .frame(width: 70, height: 32)
                .foregroundStyle(link.isEmpty ? Color.secondary : Color.white)
                .background(RoundedRectangle(cornerRadius: 9).fill(link.isEmpty ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(Kite.accent)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy || link.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.leading, 14).padding(.trailing, 7)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 13).fill(Kite.field))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(focused ? Kite.accent.opacity(0.85) : Kite.hairline, lineWidth: focused ? 1.5 : 1))
        .shadow(color: focused ? Kite.accent.opacity(0.22) : .clear, radius: 12, y: 2)
        .animation(.easeOut(duration: 0.15), value: focused)
        .animation(.easeOut(duration: 0.15), value: link.isEmpty)
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

/// A soft dawn behind the mark: the palette as light, not as decoration.
struct DawnGlow: View {
    var body: some View {
        GeometryReader { g in
            ZStack {
                RadialGradient(colors: [Kite.lilac.opacity(0.2), .clear], center: UnitPoint(x: 0.57, y: 0.2), startRadius: 0, endRadius: g.size.width * 0.44)
                RadialGradient(colors: [Kite.rose.opacity(0.11), .clear], center: UnitPoint(x: 0.4, y: 0.27), startRadius: 0, endRadius: g.size.width * 0.38)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Another way in: an icon, what it is, and what it will find.
struct EntryCard: View {
    var icon: String
    var title: String
    var detail: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Kite.accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Kite.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 56).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 13).fill(hover ? Kite.cardHover : Kite.card))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(hover ? Kite.accent.opacity(0.45) : Kite.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// The whole product in one line, with the step you are on lit.
struct Steps: View {
    private let items = ["Paste a link", "Pick a node", "Fly"]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, text in
                if i > 0 { Rectangle().fill(Kite.hairline).frame(width: 22, height: 1) }
                HStack(spacing: 6) {
                    Text("\(i + 1)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(i == 0 ? Color.white : Color.secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(i == 0 ? AnyShapeStyle(Kite.accent) : AnyShapeStyle(Color.primary.opacity(0.08))))
                    Text(text).font(.system(size: 11.5, weight: i == 0 ? .medium : .regular)).foregroundStyle(i == 0 ? Color.primary : Color.secondary)
                }
            }
        }
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
