import SwiftUI
import KiteKit

/// Logs and connections, for the days something is wrong.
struct ConsoleView: View {
    @EnvironmentObject var m: AppModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Logs").tag(0)
                Text("Connections").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240).padding(10)
            Divider()
            if tab == 0 { LogsView() } else { ConnectionsView() }
        }
    }
}

struct LogsView: View {
    @EnvironmentObject var m: AppModel
    @State private var lines: [LogLine] = []
    @State private var task: Task<Void, Never>?
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 220)
                Spacer()
                Button("Clear") { lines = [] }
                Button("Open Log File") { NSWorkspace.shared.open(m.store.coreLog) }
            }.controlSize(.small).padding(8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines.filter { filter.isEmpty || $0.payload.localizedCaseInsensitiveContains(filter) }) { l in
                            HStack(alignment: .top, spacing: 8) {
                                Text(l.type.uppercased()).foregroundStyle(color(l.type)).frame(width: 52, alignment: .leading)
                                Text(l.payload).textSelection(.enabled)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .id(l.id)
                        }
                    }.padding(8)
                }
                .onChange(of: lines.count) { _, _ in if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .onAppear { stream() }
        .onDisappear { task?.cancel() }
        .onChange(of: m.coreState) { _, _ in stream() }
    }

    func color(_ t: String) -> Color {
        switch t { case "error": return Kite.poor; case "warning": return Kite.fair; case "debug": return .secondary; default: return .primary }
    }

    func stream() {
        task?.cancel()
        guard let api = m.api else { return }
        task = Task {
            do {
                for try await l in api.logs(level: m.settings.core.logLevel == "silent" ? "info" : m.settings.core.logLevel) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        lines.append(l)
                        if lines.count > 2000 { lines.removeFirst(500) }
                    }
                }
            } catch {}
        }
    }
}

struct ConnectionsView: View {
    @EnvironmentObject var m: AppModel
    @State private var snap: ConnectionsSnapshot?
    @State private var task: Task<Void, Never>?
    @State private var sort = [KeyPathComparator(\ConnectionInfo.start, order: .reverse)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let s = snap {
                    Text("\(s.connections?.count ?? 0) connections · ↓ \(s.downloadTotal.bytesText) ↑ \(s.uploadTotal.bytesText)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close All") { Task { try? await m.api?.closeAllConnections() } }
            }.controlSize(.small).padding(8)
            Table((snap?.connections ?? []).sorted(using: sort), sortOrder: $sort) {
                TableColumn("Host", value: \.target) { Text($0.target).font(.system(size: 11, design: .monospaced)) }.width(min: 200)
                TableColumn("Process", value: \.metadata.process.orEmpty) { Text($0.metadata.process ?? "") }.width(min: 80)
                TableColumn("Rule", value: \.rule) { Text($0.rule + ($0.rulePayload.isEmpty ? "" : " · " + $0.rulePayload)).font(.system(size: 11)) }.width(min: 140)
                TableColumn("Via", value: \.chains.first.orEmpty) { Text($0.chains.first ?? "").font(.system(size: 11)) }.width(min: 120)
                TableColumn("↓", value: \.download) { Text($0.download.bytesText).font(.system(size: 11, design: .monospaced)) }.width(70)
                TableColumn("↑", value: \.upload) { Text($0.upload.bytesText).font(.system(size: 11, design: .monospaced)) }.width(70)
            }
        }
        .onAppear { stream() }
        .onDisappear { task?.cancel() }
        .onChange(of: m.coreState) { _, _ in stream() }
    }

    func stream() {
        task?.cancel()
        guard let api = m.api else { snap = nil; return }
        task = Task {
            do {
                for try await s in api.connectionsStream() {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { snap = s }
                }
            } catch {}
        }
    }
}

extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
