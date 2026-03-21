import Foundation

/// Polls the remote backend for current entries on a fixed interval.
/// Fire-and-forget: silently ignores network errors so offline mode works transparently.
public final class ProgressRemotePoller: Sendable {
    private let endpoint: URL
    private let token: String
    private let interval: TimeInterval
    private let onUpdate: @Sendable ([ProgressEntry]) -> Void

    // nonisolated(unsafe) is safe here: start()/stop() are only ever called
    // from ProgressStore which is @MainActor, so access is never concurrent.
    nonisolated(unsafe) private var pollingTask: Task<Void, Never>?

    public init(
        endpoint: URL,
        token: String,
        interval: TimeInterval = 10,
        onUpdate: @escaping @Sendable ([ProgressEntry]) -> Void
    ) {
        self.endpoint = endpoint
        self.token = token
        self.interval = interval
        self.onUpdate = onUpdate
    }

    /// Begin polling immediately, then every `interval` seconds.
    public func start() {
        let endpoint = endpoint
        let token = token
        let interval = interval
        let onUpdate = onUpdate

        pollingTask = Task {
            while !Task.isCancelled {
                await Self.fetchCurrent(endpoint: endpoint, token: token, onUpdate: onUpdate)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    deinit { pollingTask?.cancel() }

    // MARK: - Network

    private static func fetchCurrent(
        endpoint: URL,
        token: String,
        onUpdate: @Sendable ([ProgressEntry]) -> Void
    ) async {
        var request = URLRequest(url: endpoint.appendingPathComponent("current"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }

        struct Resp: Decodable { let entries: [ProgressEntry] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let resp = try? decoder.decode(Resp.self, from: data) else { return }
        onUpdate(resp.entries)
    }

    /// Fetch history entries from the remote backend. Used by the CLI.
    public static func fetchHistory(endpoint: URL, token: String, last: Int) async -> [ProgressEntry]? {
        var components = URLComponents(url: endpoint.appendingPathComponent("history"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "last", value: "\(last)")]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct Resp: Decodable { let entries: [ProgressEntry] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Resp.self, from: data))?.entries
    }
}
