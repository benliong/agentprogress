import Foundation
import XCTest

@testable import ProgressCore

final class ProgressEntryTests: XCTestCase {
    func testDecodesFromJSON() throws {
        let json = """
        {
          "version": 1,
          "agent": "claude-code",
          "project": "progress",
          "projectPath": "/Users/benliong/Projects/progress",
          "task": "Writing file watcher",
          "status": "working",
          "detail": "",
          "startedAt": "2026-03-19T14:23:01Z",
          "updatedAt": "2026-03-19T14:25:44Z",
          "sessionId": "abc123"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ProgressEntry.self, from: Data(json.utf8))

        XCTAssertEqual(entry.agent, "claude-code")
        XCTAssertEqual(entry.project, "progress")
        XCTAssertEqual(entry.status, .working)
        XCTAssertEqual(entry.sessionId, "abc123")
    }

    func testStatusSymbolNamesAreNonEmpty() {
        for status in ProgressStatus.allCases {
            XCTAssertFalse(status.symbolName.isEmpty)
        }
    }

    func testStableID() throws {
        let json = """
        {
          "version": 1, "agent": "claude-code", "project": "p", "projectPath": "/p",
          "task": "t", "status": "done", "detail": "",
          "startedAt": "2026-03-19T10:00:00Z",
          "updatedAt": "2026-03-19T10:05:00Z",
          "sessionId": "s1"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ProgressEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.id, entry.id)
    }
}

final class ProgressStoreTests: XCTestCase {
    func testLoadHistoryMissingFile() {
        let dir = URL(fileURLWithPath: "/tmp/progress-test-\(UUID().uuidString)")
        let history = ProgressStore.loadHistory(from: dir)
        XCTAssertTrue(history.isEmpty)
    }

    func testParsesJSONLMostRecentFirst() throws {
        let dir = URL(fileURLWithPath: "/tmp/progress-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let encoder = JSONEncoder.progressEncoder
        let entries = try (1 ... 3).map { i -> ProgressEntry in
            ProgressEntry(
                version: 1,
                agent: "claude-code",
                project: "p",
                projectPath: "/p",
                task: "task \(i)",
                status: .done,
                detail: "",
                startedAt: Date(timeIntervalSince1970: Double(i) * 1000),
                updatedAt: Date(timeIntervalSince1970: Double(i) * 1000 + 60),
                sessionId: "s\(i)"
            )
        }

        let jsonl = try entries
            .map { try String(data: encoder.encode($0), encoding: .utf8)! }
            .joined(separator: "\n")
        try jsonl.write(
            to: dir.appendingPathComponent("history.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let loaded = ProgressStore.loadHistory(from: dir)
        // Most-recent-first: task 3, then task 2, then task 1
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].task, "task 3")
        XCTAssertEqual(loaded[1].task, "task 2")
        XCTAssertEqual(loaded[2].task, "task 1")
    }
}
