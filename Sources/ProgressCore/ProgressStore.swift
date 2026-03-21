import Foundation
import Observation

private let _progressDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

@MainActor
@Observable
public final class ProgressStore {
    /// All currently active agents (local + remote), sorted by updatedAt descending.
    public private(set) var actives: [ProgressEntry] = []
    /// Most-recently-updated active entry (backward compat).
    public var current: ProgressEntry? { actives.first }
    public private(set) var history: [ProgressEntry] = []

    private let progressDir: URL
    private var watcher: ProgressFileWatcher?
    private var localActives: [ProgressEntry] = []
    private var remoteActives: [ProgressEntry] = []
    private var poller: ProgressRemotePoller?

    public init(progressDir: URL = .progressDirectory) {
        self.progressDir = progressDir
        reload()
        startWatching()
        startPolling()
    }

    public func reload() {
        localActives = Self.loadCurrents(from: progressDir)
        mergeActives()
        history = Self.loadHistory(from: progressDir)
    }

    /// Delete all current-*.json files (and legacy current.json).
    public func clearCurrent() throws {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: progressDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("current") && file.pathExtension == "json" {
            try fm.removeItem(at: file)
        }
        localActives = []
        mergeActives()
    }

    // MARK: - Private

    /// Local entries override remote for the same agent+hostname (they are always written
    /// simultaneously with the remote push, so they are at least as fresh).
    private func mergeActives() {
        var merged: [String: ProgressEntry] = [:]
        for entry in remoteActives { merged["\(entry.hostname ?? ""):\(entry.agent)"] = entry }
        for entry in localActives  { merged["\(entry.hostname ?? ""):\(entry.agent)"] = entry }
        actives = merged.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func startWatching() {
        try? FileManager.default.createDirectory(at: progressDir, withIntermediateDirectories: true)

        let watcher = ProgressFileWatcher(path: progressDir.path) { [weak self] in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func startPolling() {
        guard let config = ProgressConfig.load(from: progressDir) else { return }

        let poller = ProgressRemotePoller(
            endpoint: config.endpoint,
            token: config.token,
            onUpdate: { [weak self] entries in
                Task { @MainActor [weak self] in
                    self?.remoteActives = entries
                    self?.mergeActives()
                }
            }
        )
        poller.start()
        self.poller = poller
    }

    /// Scan for all current-*.json files plus legacy current.json; return sorted by updatedAt desc.
    /// Filters out done/idle entries and entries older than 2 hours (stale crashed sessions).
    public nonisolated static func loadCurrents(from dir: URL) -> [ProgressEntry] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        var entries: [ProgressEntry] = []
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("current") && file.pathExtension == "json" else { continue }
            guard let data = try? Data(contentsOf: file),
                  let entry = try? _progressDecoder.decode(ProgressEntry.self, from: data)
            else { continue }
            guard entry.status != .done && entry.status != .idle else { continue }
            guard entry.updatedAt > twoHoursAgo else { continue }
            entries.append(entry)
        }
        return entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Load history entries, most recent first, up to `limit`.
    public nonisolated static func loadHistory(from dir: URL, limit: Int = 20) -> [ProgressEntry] {
        return loadRawHistory(from: dir).suffix(limit).reversed()
    }

    /// Load all history entries for CLI use (no limit, still most-recent-first).
    public nonisolated static func loadAllHistory(from dir: URL) -> [ProgressEntry] {
        return Array(loadRawHistory(from: dir).reversed())
    }

    /// Merge and sort all history-*.jsonl files (plus legacy history.jsonl) by updatedAt ascending.
    private nonisolated static func loadRawHistory(from dir: URL) -> [ProgressEntry] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var histFiles = files.filter {
            $0.lastPathComponent.hasPrefix("history-") && $0.pathExtension == "jsonl"
        }
        let legacy = dir.appendingPathComponent("history.jsonl")
        if fm.fileExists(atPath: legacy.path) { histFiles.append(legacy) }

        var entries: [ProgressEntry] = []
        for file in histFiles {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let entry = try? _progressDecoder.decode(ProgressEntry.self, from: data)
                else { continue }
                entries.append(entry)
            }
        }
        return entries.sorted { $0.updatedAt < $1.updatedAt }
    }
}

public extension URL {
    static var progressDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".progress")
    }
}

/// Shared ISO 8601 encoder for skill-compatible output.
public extension JSONEncoder {
    static let progressEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
