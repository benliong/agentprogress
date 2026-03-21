import Foundation

/// Remote backend configuration. Loaded from ~/.progress/config.json or env vars.
public struct ProgressConfig: Codable, Sendable {
    public let endpoint: URL
    public let token: String

    public init(endpoint: URL, token: String) {
        self.endpoint = endpoint
        self.token = token
    }

    /// Load config from `~/.progress/config.json` (preferred — works for menu bar which
    /// doesn't inherit shell env) or from PROGRESS_ENDPOINT + PROGRESS_TOKEN env vars.
    /// Returns nil if neither source is configured — remote polling is disabled.
    public static func load(from dir: URL = .progressDirectory) -> ProgressConfig? {
        // Config file first
        let configURL = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(ProgressConfig.self, from: data) {
            return config
        }

        // Fall back to environment variables
        let env = ProcessInfo.processInfo.environment
        guard let token = env["PROGRESS_TOKEN"], !token.isEmpty,
              let endpointStr = env["PROGRESS_ENDPOINT"], !endpointStr.isEmpty,
              let endpoint = URL(string: endpointStr) else { return nil }
        return ProgressConfig(endpoint: endpoint, token: token)
    }
}
