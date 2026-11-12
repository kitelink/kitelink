import Foundation

/// The bundled mihomo, run as a child process in the app's core directory. Its output goes to logs/core.log; the last
/// lines are kept so a failed start can say why.
final class CoreProcess: @unchecked Sendable {
    private var process: Process?
    private var logHandle: FileHandle?
    private let lock = NSLock()
    private var tail: [String] = []
    private var pidFile: URL?
    var onExit: ((Int32) -> Void)?

    static var binary: URL? { Bundle.main.url(forAuxiliaryExecutable: "mihomo") }

    var isRunning: Bool { process?.isRunning ?? false }
    var pid: Int32? { process?.processIdentifier }

    var recentOutput: String {
        lock.lock(); defer { lock.unlock() }
        return tail.suffix(12).joined(separator: "\n")
    }

    /// Error lines the core printed since it started, cleaned of the log prefix.
    var errors: [String] {
        lock.lock(); defer { lock.unlock() }
        return tail.filter { $0.contains("level=error") || $0.contains("level=fatal") }.map(CoreProcess.clean)
    }

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"time="[^"]*" level=\w+ msg="#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
    }

    /// A core left behind by a previous run that was killed (its pid is in core/mihomo.pid) still holds the ports.
    static func reapStale(in directory: URL) {
        let file = directory.appendingPathComponent("mihomo.pid")
        defer { try? FileManager.default.removeItem(at: file) }
        guard let text = try? String(contentsOf: file, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1, kill(pid, 0) == 0 else { return }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf).hasSuffix("/mihomo") else { return }
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(2)
        while kill(pid, 0) == 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    func start(directory: URL, config: URL, log: URL) throws {
        guard let bin = CoreProcess.binary else { throw CoreError.missingBinary }
        stop()
        CoreProcess.reapStale(in: directory)
        pidFile = directory.appendingPathComponent("mihomo.pid")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        handle.seekToEndOfFile()
        logHandle = handle
        let p = Process()
        p.executableURL = bin
        p.arguments = ["-d", directory.path, "-f", config.path]
        p.currentDirectoryURL = directory
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let self else { return }
            self.logHandle?.write(d)
            if let s = String(data: d, encoding: .utf8) {
                self.lock.lock()
                self.tail.append(contentsOf: s.split(separator: "\n").map(String.init))
                if self.tail.count > 200 { self.tail.removeFirst(self.tail.count - 200) }
                self.lock.unlock()
            }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            self?.logHandle?.closeFile()
            self?.onExit?(proc.terminationStatus)
        }
        lock.lock(); tail = []; lock.unlock()
        try p.run()
        process = p
        try? String(p.processIdentifier).write(to: directory.appendingPathComponent("mihomo.pid"), atomically: true, encoding: .utf8)
    }

    func stop() {
        defer { if let f = pidFile { try? FileManager.default.removeItem(at: f) } }
        guard let p = process, p.isRunning else { process = nil; return }
        p.terminationHandler = nil
        p.terminate()
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        process = nil
    }

    /// `mihomo -t`: parses a config without running it. Returns nil when fine, else the complaint.
    static func check(config: URL, directory: URL) -> String? {
        guard let bin = binary else { return "The core is missing from the app bundle." }
        let p = Process()
        p.executableURL = bin
        p.arguments = ["-d", directory.path, "-f", config.path, "-t"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "\(error)" }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus == 0 { return nil }
        let line = out.split(separator: "\n").last(where: { $0.contains("level=error") || $0.contains("level=fatal") }) ?? Substring(out.suffix(300))
        return line.replacingOccurrences(of: #"time="[^"]*" level=\w+ msg="#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
    }

    enum CoreError: Error, LocalizedError {
        case missingBinary, didNotStart(String)
        var errorDescription: String? {
            switch self {
            case .missingBinary: return "The core is missing from the app bundle."
            case .didNotStart(let why): return why.isEmpty ? "The core did not start." : why
            }
        }
    }
}
