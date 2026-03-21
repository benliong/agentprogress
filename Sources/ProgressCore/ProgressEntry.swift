import Foundation

public enum ProgressStatus: String, Codable, Sendable, CaseIterable {
    case working
    case thinking
    case waiting
    case done
    case error
    case idle
}

public struct ProgressEntry: Codable, Sendable, Identifiable {
    public let version: Int
    public let agent: String
    public let hostname: String?   // machine that wrote this entry, e.g. "mini", "air"
    public let project: String
    public let projectPath: String
    public let task: String
    public let status: ProgressStatus
    public let detail: String
    public let startedAt: Date
    public let updatedAt: Date
    public let sessionId: String

    // Stable identity for SwiftUI lists — combine agent + hostname + session + startedAt
    public var id: String { "\(agent)-\(hostname ?? "")-\(sessionId)-\(startedAt.timeIntervalSince1970)" }
}

public extension ProgressStatus {
    /// SF Symbol name for each status.
    var symbolName: String {
        switch self {
        case .working:  "cpu"
        case .thinking: "brain"
        case .waiting:  "clock"
        case .done:     "checkmark.circle"
        case .error:    "exclamationmark.triangle"
        case .idle:     "circle.dotted"
        }
    }

    var displayLabel: String {
        switch self {
        case .working:  "Working"
        case .thinking: "Thinking"
        case .waiting:  "Waiting"
        case .done:     "Done"
        case .error:    "Error"
        case .idle:     "Idle"
        }
    }
}
