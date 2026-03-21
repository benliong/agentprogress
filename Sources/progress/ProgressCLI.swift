import ArgumentParser
import Foundation
import ProgressCore

@main
struct ProgressCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "progress",
        abstract: "Show what AI agents are working on.",
        subcommands: [Show.self, Watch.self, History.self, Clear.self],
        defaultSubcommand: Show.self
    )
}

// MARK: - Show

struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show current agent activity (default)."
    )

    func run() async throws {
        let dir = URL.progressDirectory
        let entries = ProgressStore.loadCurrents(from: dir)
        if entries.isEmpty {
            print("No active task.")
            return
        }
        for entry in entries {
            printEntry(entry)
            if entries.count > 1 { print("") }
        }
    }
}

// MARK: - Watch

struct Watch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Live-tail agent activity (updates on file change)."
    )

    func run() async throws {
        let dir = URL.progressDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        print("Watching ~/.progress/ — press Ctrl-C to stop\n")

        // Print initial state
        printCurrentState(from: dir)

        // Watch for changes using DispatchSourceFileSystemObject on the directory
        let stream = AsyncStream<Void> { continuation in
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: open(dir.path, O_EVTONLY),
                eventMask: .write,
                queue: DispatchQueue.global()
            )
            source.setEventHandler {
                continuation.yield()
            }
            source.setCancelHandler {
                continuation.finish()
            }
            source.resume()

            continuation.onTermination = { _ in
                source.cancel()
            }
        }

        for await _ in stream {
            printCurrentState(from: dir)
        }
    }

    private func printCurrentState(from dir: URL) {
        let entries = ProgressStore.loadCurrents(from: dir)
        print("\u{1B}[2J\u{1B}[H", terminator: "") // clear screen
        if entries.isEmpty {
            let ts = ISO8601DateFormatter().string(from: Date())
            print("[\(ts)] No active task.")
            return
        }
        for (i, entry) in entries.enumerated() {
            printEntry(entry)
            if i < entries.count - 1 { print("") }
        }
    }
}

// MARK: - History

struct History: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show recent agent activity history."
    )

    @Option(name: .long, help: "Number of entries to show.")
    var last: Int = 20

    @Flag(name: .long, help: "Output raw JSONL for piping.")
    var json = false

    func run() async throws {
        let dir = URL.progressDirectory
        var entries = ProgressStore.loadAllHistory(from: dir)

        // Merge remote history if backend is configured
        if let config = ProgressConfig.load(from: dir),
           let remote = await ProgressRemotePoller.fetchHistory(endpoint: config.endpoint, token: config.token, last: last) {
            let localKeys = Set(entries.map { dedupeKey($0) })
            let newRemote = remote.filter { !localKeys.contains(dedupeKey($0)) }
            entries = (entries + newRemote).sorted { $0.updatedAt > $1.updatedAt }
        }

        let limited = Array(entries.prefix(last))

        if json {
            let encoder = JSONEncoder.progressEncoder
            for entry in limited.reversed() { // chronological for JSONL
                if let data = try? encoder.encode(entry),
                   let line = String(data: data, encoding: .utf8) {
                    print(line)
                }
            }
        } else {
            if limited.isEmpty {
                print("No history.")
                return
            }
            for entry in limited {
                printHistoryLine(entry)
            }
        }
    }

    private func dedupeKey(_ entry: ProgressEntry) -> String {
        "\(entry.sessionId)-\(entry.updatedAt.timeIntervalSince1970)"
    }
}

// MARK: - Clear

struct Clear: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Delete current.json (mark as idle)."
    )

    func run() async throws {
        let dir = URL.progressDirectory
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let currents = files.filter { $0.lastPathComponent.hasPrefix("current") && $0.pathExtension == "json" }
        if currents.isEmpty {
            print("Nothing to clear.")
        } else {
            for file in currents { try fm.removeItem(at: file) }
            print("Cleared \(currents.count) file(s).")
        }
    }
}

// MARK: - Formatting helpers

private func printEntry(_ entry: ProgressEntry) {
    let now = Date()
    let elapsed = relativeTime(from: entry.startedAt, to: now)
    let agentLabel = [entry.agent, entry.hostname].compactMap { $0 }.joined(separator: "/")

    print("[\(entry.status.displayLabel.uppercased())] \(agentLabel) — \(entry.project)")
    print("Task:    \(entry.task)")
    if !entry.detail.isEmpty {
        print("Detail:  \(entry.detail)")
    }
    print("Started: \(elapsed) (\(formatDate(entry.startedAt)))")
    print("Updated: \(relativeTime(from: entry.updatedAt, to: now))")
    print("Session: \(entry.sessionId)")
}

private func printHistoryLine(_ entry: ProgressEntry) {
    let now = Date()
    let ago = relativeTime(from: entry.updatedAt, to: now)
    let status = entry.status.displayLabel.padding(toLength: 8, withPad: " ", startingAt: 0)
    let task = entry.task.count > 50 ? String(entry.task.prefix(47)) + "…" : entry.task
    print("[\(status)] \(ago.padding(toLength: 8, withPad: " ", startingAt: 0)) \(entry.project) · \(task)")
}

private func relativeTime(from date: Date, to now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
}

private func formatDate(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    return fmt.string(from: date)
}
