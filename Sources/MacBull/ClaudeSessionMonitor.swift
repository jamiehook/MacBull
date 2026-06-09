import Foundation
import AppKit

/// A running Claude Code CLI session discovered on this machine.
struct ClaudeSession: Identifiable {
    let pid: pid_t
    /// The project directory the session was started in.
    let workingDirectory: String
    /// Most recent write to the session's transcript under ~/.claude/projects,
    /// or nil if no transcript was found for the project.
    let lastActivity: Date?

    var id: pid_t { pid }

    var projectName: String {
        let name = (workingDirectory as NSString).lastPathComponent
        return name.isEmpty ? workingDirectory : name
    }

    /// Claude Code appends to the transcript as it works, so a very recent
    /// write means the session is busy; anything older means it's waiting.
    var isWorking: Bool {
        guard let lastActivity else { return false }
        return Date().timeIntervalSince(lastActivity) < 30
    }

    /// Short state shown next to the project name in the menu.
    var stateLabel: String {
        if isWorking { return "working…" }
        guard let lastActivity else { return "idle" }
        return "idle · \(Self.relative(lastActivity))"
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60    { return "just now" }
        if seconds < 3600  { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

/// Discovers running Claude Code CLI sessions and keeps the list fresh.
///
/// Detection is in two steps: `ps` finds `claude` processes (both the
/// standalone binary and the npm install run via node), then one `lsof` call
/// resolves each process's working directory. The transcript directory for
/// that project (~/.claude/projects/<encoded-path>/) tells us when the session
/// last did something, which drives the working/idle label.
final class ClaudeSessionMonitor: ObservableObject {

    @Published private(set) var sessions: [ClaudeSession] = []

    private var timer: Timer?
    private let projectsDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    init() {
        refresh()
        // Common modes so the list keeps updating while the menu is open.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    /// Single-line summary for the submenu title.
    var summaryLabel: String {
        guard !sessions.isEmpty else { return "Claude Code: no sessions" }
        let working = sessions.filter(\.isWorking).count
        let count = "\(sessions.count) session\(sessions.count == 1 ? "" : "s")"
        return working > 0 ? "Claude Code: \(count), \(working) working"
                           : "Claude Code: \(count)"
    }

    /// Rescans off the main thread (ps + lsof can take a moment) and publishes
    /// the result back on main.
    func refresh() {
        let projectsDir = projectsDir
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.scan(projectsDir: projectsDir)
            DispatchQueue.main.async { self?.sessions = found }
        }
    }

    // MARK: Discovery

    private static func scan(projectsDir: URL) -> [ClaudeSession] {
        let pids = claudePIDs()
        let cwds = workingDirectories(for: pids)
        var sessions = cwds.map { pid, cwd in
            ClaudeSession(pid: pid,
                          workingDirectory: cwd,
                          lastActivity: latestTranscriptDate(projectsDir: projectsDir, cwd: cwd))
        }
        // Busy sessions first, then by most recent activity.
        sessions.sort { a, b in
            if a.isWorking != b.isWorking { return a.isWorking }
            return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
        }
        return sessions
    }

    /// PIDs of Claude Code CLI processes.
    private static func claudePIDs() -> [pid_t] {
        guard let output = run("/bin/ps", ["-axo", "pid=,command="]) else { return [] }
        var pids: [pid_t] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = pid_t(trimmed[..<space]) else { continue }
            if isClaudeCommand(String(trimmed[trimmed.index(after: space)...])) {
                pids.append(pid)
            }
        }
        return pids
    }

    /// Matches the CLI whether installed as a standalone `claude` binary or as
    /// an npm package run through node. Case-sensitive on purpose: the Claude
    /// desktop app's process is `Claude` and shouldn't be listed.
    private static func isClaudeCommand(_ command: String) -> Bool {
        let tokens = command.split(separator: " ", maxSplits: 2).map(String.init)
        guard let first = tokens.first else { return false }
        if (first as NSString).lastPathComponent == "claude" { return true }
        if (first as NSString).lastPathComponent.hasPrefix("node"), tokens.count > 1 {
            let script = tokens[1]
            return (script as NSString).lastPathComponent == "claude"
                || script.contains("@anthropic-ai/claude-code")
        }
        return false
    }

    /// Resolves working directories for all PIDs with a single lsof call.
    /// Output is field format: a `p<pid>` line, then `n<path>` for its cwd.
    private static func workingDirectories(for pids: [pid_t]) -> [pid_t: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        guard let output = run("/usr/sbin/lsof", ["-a", "-p", list, "-d", "cwd", "-Fpn"])
        else { return [:] }

        var result: [pid_t: String] = [:]
        var currentPID: pid_t?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPID = pid_t(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPID {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    /// Newest transcript write for the project at `cwd`. Claude Code stores
    /// transcripts in ~/.claude/projects/ under the project path with every
    /// non-alphanumeric character replaced by "-".
    private static func latestTranscriptDate(projectsDir: URL, cwd: String) -> Date? {
        let encoded = cwd.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let dir = projectsDir.appendingPathComponent(encoded, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap {
                try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            }
            .max()
    }

    /// Runs a tool and returns its stdout, or nil if it couldn't be launched.
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            NSLog("MacBull: failed to launch \(path): \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
