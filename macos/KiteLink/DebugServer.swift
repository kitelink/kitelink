#if DEBUG
import AppKit
import Network
import KiteKit

/// A tiny HTTP server for driving the app from a script during development (KITELINK_DEBUG_PORT=… in the environment).
/// Clicks and keys go through NSApp.sendEvent, so the test exercises the same path a user does.
///   GET  /state                      → JSON summary of the model
///   GET  /window                     → window number and frame (for `screencapture -l`)
///   POST /click  {"x":…,"y":…,"count":1}   points from the main window's top-left
///   POST /key    {"chars":"…"} or {"key":"return|escape|tab"}
///   POST /scroll {"x":…,"y":…,"dy":…}
///   POST /paste  {"text":"…"}        types into the focused field via the pasteboard
///   POST /window {"id":"console|settings|main"}
@MainActor
final class DebugServer {
    static var shared: DebugServer?
    private var listener: NWListener?

    static func startIfRequested() {
        guard let p = ProcessInfo.processInfo.environment["KITELINK_DEBUG_PORT"], let port = UInt16(p) else { return }
        let s = DebugServer()
        s.start(port: port)
        shared = s
    }

    private func start(port: UInt16) {
        guard let l = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!) else { return }
        l.newConnectionHandler = { [weak self] c in
            c.start(queue: .main)
            MainActor.assumeIsolated { self?.read(c, buffer: Data()) }
        }
        l.start(queue: .main)
        listener = l
    }

    private func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, _ in
          MainActor.assumeIsolated {
            var buf = buffer
            if let data { buf.append(data) }
            if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
                let len = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                let body = buf[r.upperBound...]
                if body.count >= len {
                    let line = head.split(separator: "\r\n").first ?? ""
                    let parts = line.split(separator: " ")
                    let reply = self?.handle(method: String(parts.first ?? ""), path: String(parts.dropFirst().first ?? "/"), body: Data(body.prefix(len))) ?? "{}"
                    let out = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(reply.utf8.count)\r\nConnection: close\r\n\r\n\(reply)"
                    c.send(content: Data(out.utf8), completion: .contentProcessed { _ in c.cancel() })
                    return
                }
            }
            if done { c.cancel() } else { self?.read(c, buffer: buf) }
          }
        }
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && ($0.identifier?.rawValue.hasPrefix("main") == true || $0.title == "KiteLink") }
            ?? NSApp.windows.first { $0.isVisible && $0.level == .normal && !($0 is NSPanel) }
    }

    /// The window a user would be clicking in: the deepest sheet on the main window, or the window named by `id`.
    private func target(_ json: [String: Any]) -> NSWindow? {
        var w: NSWindow?
        if let id = json["window"] as? String {
            w = NSApp.windows.first { $0.isVisible && ($0.identifier?.rawValue.hasPrefix(id) == true || $0.title.lowercased().contains(id)) }
        }
        w = w ?? mainWindow
        while let sheet = w?.attachedSheet { w = sheet }
        return w
    }

    private func handle(method: String, path: String, body: Data) -> String {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let m = AppModel.shared
        switch (method, path) {
        case ("GET", "/state"):
            let state: [String: Any] = [
                "core": m.coreState.label, "running": m.coreState.isRunning, "systemProxy": m.settings.systemProxy,
                "mode": m.settings.core.mode.rawValue, "profiles": m.profiles.map { ["id": $0.id, "name": $0.name, "active": $0.id == m.settings.activeProfileID] },
                "groups": m.groups.map { ["name": $0.name, "type": $0.type, "now": $0.now ?? "", "count": $0.all?.count ?? 0] },
                "selectedGroup": m.selectedGroup ?? "", "traffic": ["up": m.traffic.up, "down": m.traffic.down],
                "notice": m.notice?.text ?? "", "sheets": ["profiles": m.showProfiles, "import": m.showImport],
                "windows": NSApp.windows.filter { $0.isVisible }.map { ["title": $0.title, "id": $0.identifier?.rawValue ?? "", "number": $0.windowNumber, "w": $0.frame.width, "h": $0.frame.height] },
            ]
            return encode(state)
        case ("GET", "/window"):
            guard let w = mainWindow else { return "{}" }
            return encode(["number": w.windowNumber, "x": w.frame.minX, "y": w.frame.minY, "w": w.frame.width, "h": w.frame.height, "key": w.isKeyWindow])
        case ("POST", "/click"):
            guard let w = target(json), let x = json["x"] as? Double, let y = json["y"] as? Double else { return #"{"error":"no window"}"# }
            let count = json["count"] as? Int ?? 1
            let p = NSPoint(x: x, y: w.frame.height - y)
            w.makeKeyAndOrderFront(nil)
            for i in 1...count {
                for (type, mask) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: mask + i, clickCount: i, pressure: type == .leftMouseDown ? 1 : 0) {
                        // Queued, not sent: an AppKit control tracks the mouse in its own loop and reads the up event from the queue.
                        NSApp.postEvent(e, atStart: false)
                    }
                }
            }
            let hit = w.contentView?.hitTest(p)
            var chain: [String] = []
            var v: NSView? = hit
            while let cur = v, chain.count < 6 { chain.append(String(describing: type(of: cur))); v = cur.superview }
            return encode(["hit": chain])
        case ("POST", "/scroll"):
            guard let w = target(json), let x = json["x"] as? Double, let y = json["y"] as? Double, let dy = json["dy"] as? Double else { return "{}" }
            let p = NSPoint(x: x, y: w.frame.height - y)
            if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0) {
                cg.location = CGPoint(x: w.frame.minX + p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - (w.frame.minY + p.y))
                if let e = NSEvent(cgEvent: cg) { NSApp.sendEvent(e) }
            }
            return "{}"
        case ("POST", "/key"):
            guard let w = target(json) else { return "{}" }
            if let chars = json["chars"] as? String {
                var flags: NSEvent.ModifierFlags = []
                if json["cmd"] as? Bool == true { flags.insert(.command) }
                if json["shift"] as? Bool == true { flags.insert(.shift) }
                if json["opt"] as? Bool == true { flags.insert(.option) }
                for ch in chars { send(key: String(ch), code: 0, window: w, flags: flags) }
            } else if let key = json["key"] as? String {
                let codes: [String: (UInt16, String)] = ["return": (36, "\r"), "escape": (53, "\u{1b}"), "tab": (48, "\t"), "delete": (51, "\u{7f}")]
                if let (code, ch) = codes[key] { send(key: ch, code: code, window: w) }
            }
            return "{}"
        case ("POST", "/paste"):
            guard let text = json["text"] as? String, let w = target(json) else { return "{}" }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            send(key: "v", code: 9, window: w, flags: .command)
            return "{}"
        case ("POST", "/window"):
            let id = json["id"] as? String ?? "main"
            if id == "settings" { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            else if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(id) == true }) { w.makeKeyAndOrderFront(nil) }
            return "{}"
        default:
            return #"{"error":"unknown"}"#
        }
    }

    private func send(key: String, code: UInt16, window: NSWindow, flags: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code) {
                NSApp.sendEvent(e)
            }
        }
    }

    private func encode(_ v: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
#endif
