import Foundation
import Combine
import ServiceManagement

/// Owns the `caffeinate` subprocess and the user's selected assertions.
///
/// The five published `prevent…` / `declare…` flags map 1:1 to the flags of
/// `/usr/bin/caffeinate`. `durationSeconds` maps to `-t` (0 means "no limit").
/// Whenever the configuration changes while active, the running process is
/// torn down and relaunched with the new flag set.
final class CaffeinateController: ObservableObject {

    // MARK: Configuration (persisted to UserDefaults)

    @Published var preventDisplaySleep = true  { didSet { configChanged() } }   // -d
    @Published var preventIdleSleep    = true  { didSet { configChanged() } }   // -i
    @Published var preventDiskSleep    = false { didSet { configChanged() } }   // -m
    @Published var preventSystemSleep  = false { didSet { configChanged() } }   // -s
    @Published var declareUserActive   = false { didSet { configChanged() } }   // -u
    @Published var durationSeconds     = 0     { didSet { configChanged() } }   // -t (0 = indefinite)

    @Published var launchAtLogin = false { didSet { updateLoginItem() } }

    // MARK: Runtime state (read by the menu)

    /// True while a `caffeinate` process is running.
    @Published private(set) var isActive = false
    /// Seconds left when a duration is set, otherwise nil. Updated ~2x/sec while active.
    @Published private(set) var remaining: TimeInterval?

    // MARK: Private

    private let defaults = UserDefaults.standard
    private var process: Process?
    private var endDate: Date?
    private var ticker: Timer?
    /// Bumped on every teardown so a stale `terminationHandler` can no-op itself.
    private var generation = 0

    var anyModeSelected: Bool {
        preventDisplaySleep || preventIdleSleep || preventDiskSleep
            || preventSystemSleep || declareUserActive
    }

    // MARK: Lifecycle

    init() {
        load()
        launchAtLogin = (SMAppService.mainApp.status == .enabled)

        // Optionally come up already caffeinated (handy with "Launch at login").
        // Deferred so property observers behave normally once init has finished.
        if ProcessInfo.processInfo.environment["MACBULL_AUTOSTART"] == "1" {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isActive else { return }
                self.toggleActive()
            }
        }
    }

    // MARK: Public actions

    func toggleActive() {
        if isActive {
            deactivate()
        } else {
            // caffeinate with no assertion flag defaults to -i; mirror that in the UI
            // so the menu always reflects what's actually being held.
            if !anyModeSelected { preventIdleSleep = true }
            startProcess()
            isActive = true
        }
    }

    func deactivate() {
        stop()
        isActive = false
    }

    // MARK: Process management

    private func startProcess() {
        stop()                       // bumps generation, kills any previous process
        let myGeneration = generation
        let flags = currentFlags()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        proc.arguments = flags
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { _ in
            // Fires on a background thread; hop to main and ignore if superseded.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == myGeneration else { return }
                self.handleNaturalExit()
            }
        }

        do {
            try proc.run()
        } catch {
            NSLog("MacBull: failed to launch /usr/bin/caffeinate: \(error)")
            return
        }
        process = proc

        if durationSeconds > 0 {
            endDate = Date().addingTimeInterval(TimeInterval(durationSeconds))
            remaining = TimeInterval(durationSeconds)
            startTicker()
        } else {
            endDate = nil
            remaining = nil
        }
    }

    /// Tears down the current process without changing `isActive`.
    private func stop() {
        generation &+= 1
        ticker?.invalidate()
        ticker = nil
        if let proc = process {
            proc.terminationHandler = nil
            if proc.isRunning { proc.terminate() }
        }
        process = nil
        endDate = nil
        remaining = nil
    }

    /// Called when caffeinate exits on its own (timeout reached or killed externally).
    private func handleNaturalExit() {
        ticker?.invalidate()
        ticker = nil
        process = nil
        endDate = nil
        remaining = nil
        isActive = false
    }

    private func configChanged() {
        persist()
        guard isActive else { return }
        if anyModeSelected {
            startProcess()              // restart with the new flags / duration
        } else {
            deactivate()                // every assertion switched off → allow sleep
        }
    }

    private func currentFlags() -> [String] {
        var flags: [String] = []
        if preventDisplaySleep { flags.append("-d") }
        if preventIdleSleep    { flags.append("-i") }
        if preventDiskSleep    { flags.append("-m") }
        if preventSystemSleep  { flags.append("-s") }
        if declareUserActive   { flags.append("-u") }
        if flags.isEmpty       { flags.append("-i") }   // safety net; matches caffeinate's default
        if durationSeconds > 0 { flags += ["-t", String(durationSeconds)] }
        // Tie the child's lifetime to ours: caffeinate releases its assertion and
        // exits when this pid dies, so a crash / force-quit can't strand the Mac awake.
        flags += ["-w", String(ProcessInfo.processInfo.processIdentifier)]
        return flags
    }

    // MARK: Countdown

    private func startTicker() {
        ticker?.invalidate()
        // Common modes so it keeps ticking while the menu is open (event-tracking).
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        remaining = max(0, left)
        if left <= 0 {
            ticker?.invalidate()
            ticker = nil
        }
    }

    // MARK: Launch at login

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("MacBull: could not update login item: \(error)")
        }
    }

    // MARK: Persistence

    private func persist() {
        defaults.set(preventDisplaySleep, forKey: Keys.display)
        defaults.set(preventIdleSleep,    forKey: Keys.idle)
        defaults.set(preventDiskSleep,    forKey: Keys.disk)
        defaults.set(preventSystemSleep,  forKey: Keys.system)
        defaults.set(declareUserActive,   forKey: Keys.user)
        defaults.set(durationSeconds,     forKey: Keys.duration)
    }

    private func load() {
        guard defaults.object(forKey: Keys.display) != nil else { return }  // first run → keep defaults
        preventDisplaySleep = defaults.bool(forKey: Keys.display)
        preventIdleSleep    = defaults.bool(forKey: Keys.idle)
        preventDiskSleep    = defaults.bool(forKey: Keys.disk)
        preventSystemSleep  = defaults.bool(forKey: Keys.system)
        declareUserActive   = defaults.bool(forKey: Keys.user)
        durationSeconds     = defaults.integer(forKey: Keys.duration)
    }

    private enum Keys {
        static let display  = "preventDisplaySleep"
        static let idle     = "preventIdleSleep"
        static let disk     = "preventDiskSleep"
        static let system   = "preventSystemSleep"
        static let user     = "declareUserActive"
        static let duration = "durationSeconds"
    }
}

// MARK: - Display helpers

extension CaffeinateController {
    /// Single-line status shown at the top of the menu.
    var statusText: String {
        guard isActive else { return "Sleep allowed" }
        if let remaining {
            return "Awake · \(Self.format(remaining)) left"
        }
        return "Awake · no time limit"
    }

    /// Human label for the currently-selected duration.
    var durationLabel: String {
        switch durationSeconds {
        case 0:     return "No limit"
        case 900:   return "15 minutes"
        case 1800:  return "30 minutes"
        case 3600:  return "1 hour"
        case 7200:  return "2 hours"
        case 14400: return "4 hours"
        case 28800: return "8 hours"
        default:    return "\(durationSeconds / 60) min"
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
