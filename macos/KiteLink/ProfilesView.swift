import SwiftUI
import KiteKit
import UniformTypeIdentifiers

/// Manage profiles: update, edit, override, delete, add.
struct ProfilesSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var editing: Profile?
    @State private var showVerge = false
    @State private var showAdd = false
    @State private var override: AppModel.OverrideTarget?
    @State private var confirmDelete: Profile?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Profiles").font(.title3.weight(.semibold))
                Spacer()
                Button("Update All") { Task { await m.updateAll() } }.controlSize(.small).disabled(!m.profiles.contains { $0.isRemote })
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            if let p = editing {
                ProfileEditor(profile: p) { editing = nil }
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(m.profiles) { p in
                            ProfileRow(profile: p, active: p.id == m.settings.activeProfileID,
                                       onActivate: { Task { await m.activate(p.id) } },
                                       onUpdate: { Task { await m.update(p.id) } },
                                       onEdit: { editing = p },
                                       onOverride: { override = .profile(p.id) },
                                       onDelete: { confirmDelete = p })
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(minHeight: 160)
                Rectangle().fill(Kite.hairline).frame(height: 1).padding(.top, 10)
                HStack(spacing: 12) {
                    Menu {
                        Button("Subscription Link…") { showAdd = true }
                        Button("Profile File…") { openFile() }
                        if VergeImport.isInstalled() { Button("From Clash Verge Rev…") { showVerge = true } }
                    } label: { Label("Add", systemImage: "plus") }
                    .fixedSize()
                    Spacer()
                    Button("Global Override…") { override = .global }.help("A YAML override merged into every profile")
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                .controlSize(.regular)
                .padding(20)
            }
        }
        .frame(width: 600)
        .frame(minHeight: 320)
        .sheet(isPresented: $showVerge) { VergeImportSheet().environmentObject(m) }
        .sheet(isPresented: $showAdd) { ImportSheet(prefill: "").environmentObject(m) }
        .sheet(item: $override) { OverrideEditor(target: $0).environmentObject(m) }
        .alert(item: $confirmDelete) { p in
            Alert(title: Text("Delete \(p.name)?"), message: Text("Its file and override are removed. The subscription on the provider's side is not affected."),
                  primaryButton: .destructive(Text("Delete")) { m.remove(p.id) }, secondaryButton: .cancel())
        }
    }

    func openFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType.yaml, UTType(filenameExtension: "yml") ?? .yaml]
        if p.runModal() == .OK, let u = p.url { m.handle(url: u) }
    }
}

struct ProfileRow: View {
    @EnvironmentObject var m: AppModel
    var profile: Profile
    var active: Bool
    var onActivate: () -> Void
    var onUpdate: () -> Void
    var onEdit: () -> Void
    var onOverride: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onActivate) {
                Image(systemName: active ? "largecircle.fill.circle" : "circle").foregroundStyle(active ? Kite.accent : .secondary).font(.system(size: 15))
            }.buttonStyle(.plain).help(active ? "Active" : "Use this profile")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(profile.name).font(.system(size: 13, weight: .semibold))
                    if !profile.isRemote { Tag(text: "file") }
                    if m.updating.contains(profile.id) { ProgressView().controlSize(.mini) }
                }
                if let u = profile.usage, let total = u.total, total > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule().fill((u.fraction ?? 0) > 0.9 ? Kite.poor : Kite.accent).frame(width: geo.size.width * (u.fraction ?? 0))
                            }
                        }.frame(width: 260, height: 4)
                        Text("\(u.used.bytesText) of \(total.bytesText)" + (u.expire.map { " · expires \($0.short)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    if let d = profile.updatedAt { Text("updated \(d.relative)") }
                    if profile.isRemote, let h = profile.updateIntervalHours { Text("· every \(h) h") }
                    if let e = profile.lastError { Text("· \(e)").foregroundStyle(Kite.poor).lineLimit(1) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                if profile.isRemote { Button { onUpdate() } label: { Image(systemName: "arrow.clockwise") }.help("Update now") }
                if let home = profile.homeURL, let u = URL(string: home) { Button { NSWorkspace.shared.open(u) } label: { Image(systemName: "safari") }.help("Open the provider's panel") }
                Button(action: onOverride) { Image(systemName: "slider.horizontal.3") }.help("Override")
                Button(action: onEdit) { Image(systemName: "pencil") }.help("Edit")
                Button(action: onDelete) { Image(systemName: "trash") }.help("Delete")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(active ? Kite.rowSelected : Color.primary.opacity(0.035)))
    }
}

struct ProfileEditor: View {
    @EnvironmentObject var m: AppModel
    @State var profile: Profile
    var done: () -> Void
    @State private var interval: String = ""
    @State private var ua: String = ""

    var body: some View {
        Form {
            TextField("Name", text: $profile.name)
            if profile.isRemote {
                TextField("Link", text: Binding(get: { profile.url ?? "" }, set: { profile.url = $0 }))
                TextField("Update every (hours)", text: $interval)
                Toggle("Update automatically", isOn: $profile.autoUpdate)
                Toggle("Fetch through the proxy", isOn: $profile.updateThroughProxy)
                TextField("User-Agent (optional)", text: $ua)
            }
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save") {
                    profile.updateIntervalHours = Int(interval).flatMap { $0 > 0 ? $0 : nil }
                    profile.userAgent = ua.isEmpty ? nil : ua
                    m.edit(profile)
                    done()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Kite.accent)
            }
        }
        .formStyle(.grouped)
        .onAppear { interval = profile.updateIntervalHours.map(String.init) ?? ""; ua = profile.userAgent ?? "" }
    }
}

/// Paste a link (also opened by clash:// links with the URL filled in).
struct ImportSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @State var prefill: String
    var prefillName: String = ""
    @State private var link = ""
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Subscription").font(.title3.weight(.semibold))
            TextField("Subscription link", text: $link).textFieldStyle(.roundedBorder).onSubmit { submit() }
            TextField("Name (optional — taken from the provider when empty)", text: $name).textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.caption).foregroundStyle(Kite.poor) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: submit) { if busy { ProgressView().controlSize(.small).frame(width: 50) } else { Text("Import").frame(width: 50) } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Kite.accent).disabled(busy || link.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { link = prefill; name = prefillName }
    }

    func submit() {
        guard !busy, !link.isEmpty else { return }
        busy = true; error = nil
        Task {
            do { _ = try await m.add(subscription: link, name: name); dismiss() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct VergeImportSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var items: [VergeImport.Item] = []
    @State private var picked: Set<String> = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Clash Verge Rev").font(.title3.weight(.semibold))
            Text("Subscriptions found in Clash Verge Rev's data folder, with their node selections. Nothing is changed over there.").font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(Kite.poor).font(.caption) }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { it in
                        let dup = m.profiles.contains { $0.url == it.url }
                        Toggle(isOn: Binding(get: { picked.contains(it.id) }, set: { on in if on { picked.insert(it.id) } else { picked.remove(it.id) } })) {
                            HStack(spacing: 8) {
                                Text(it.name)
                                if dup { Tag(text: "already added") }
                                if let u = it.usage, let t = u.total, t > 0 { Text("\(u.used.bytesText) / \(t.bytesText)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.disabled(dup)
                    }
                }.padding(.vertical, 4)
            }.frame(minHeight: 80, maxHeight: 240)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: run) { if busy { ProgressView().controlSize(.small).frame(width: 60) } else { Text("Import \(picked.count)").frame(width: 60) } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Kite.accent).disabled(picked.isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            do {
                items = try VergeImport.load()
                picked = Set(items.filter { it in !m.profiles.contains { $0.url == it.url } }.map(\.id))
            } catch { self.error = error.localizedDescription }
        }
    }

    func run() {
        busy = true
        Task {
            await m.importFromVerge(items.filter { picked.contains($0.id) })
            busy = false
            dismiss()
        }
    }
}

/// YAML override editor, global or per profile.
struct OverrideEditor: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    var target: AppModel.OverrideTarget
    @State private var text = ""
    @State private var error: String?
    @State private var busy = false

    var title: String {
        switch target {
        case .global: return "Global Override"
        case .profile(let id): return "Override · \(m.profiles.first { $0.id == id }?.name ?? id)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            Text("YAML merged on top of the profile. A top-level key replaces the profile's; `prepend-rules`, `append-rules`, `prepend-proxies`, `append-proxies`, `prepend-proxy-groups` and `append-proxy-groups` splice into those lists — the same keys as a Clash Verge Rev merge file. Ports, the controller and the mode stay with KiteLink's settings.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Kite.hairline))
            if text.isEmpty {
                Button("Insert example") {
                    text = "prepend-rules:\n  - DOMAIN-SUFFIX,example.com,DIRECT\n# dns:\n#   enable: true\n#   enhanced-mode: fake-ip\n"
                }.buttonStyle(.link).font(.caption)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Kite.poor) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save & Apply") {
                    busy = true; error = nil
                    Task {
                        do { try await m.saveOverride(target, text: text); dismiss() } catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Kite.accent).disabled(busy)
            }
        }
        .padding(20)
        .frame(width: 620, height: 460)
        .onAppear { text = m.overrideText(target) }
    }
}
