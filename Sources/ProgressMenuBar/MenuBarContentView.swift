import AppKit
import ProgressCore
import SwiftUI

struct MenuBarContentView: View {
    let store: ProgressStore

    @State private var now = Date()
    private let tickTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var localHostname: String {
        ProcessInfo.processInfo.hostName
            .components(separatedBy: ".").first?
            .lowercased() ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.actives.isEmpty {
                Text("No active task")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            } else {
                ForEach(store.actives) { entry in
                    CurrentTaskCard(entry: entry, now: now, localHostname: localHostname)
                    Divider()
                }
            }

            if !store.history.isEmpty {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                ForEach(store.history.prefix(10)) { entry in
                    HistoryRow(entry: entry, now: now)
                }

                Divider()
            }

            Button("Reveal ~/.progress in Finder") {
                NSWorkspace.shared.open(.progressDirectory)
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .frame(minWidth: 300)
        .onReceive(tickTimer) { date in
            now = date
        }
    }
}

// MARK: - Current Task Card

private struct CurrentTaskCard: View {
    let entry: ProgressEntry
    let now: Date
    let localHostname: String

    private var agentLabel: String {
        guard let hostname = entry.hostname, hostname != localHostname else {
            return entry.agent
        }
        return "\(entry.agent) @ \(hostname)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.project)
                    .font(.headline)
                Spacer()
                StatusBadge(status: entry.status)
            }

            Text(entry.task)
                .font(.body)
                .lineLimit(3)

            HStack {
                Text(agentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(relativeTime(from: entry.startedAt, to: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let entry: ProgressEntry
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.status.symbolName)
                .foregroundStyle(statusColor(entry.status))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.task)
                    .font(.callout)
                    .lineLimit(1)
                Text(entry.project)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(relativeTime(from: entry.updatedAt, to: now))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: ProgressStatus

    var body: some View {
        Text(status.displayLabel)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }
}

// MARK: - Helpers

private func statusColor(_ status: ProgressStatus) -> Color {
    switch status {
    case .working:  .blue
    case .thinking: .purple
    case .waiting:  .orange
    case .done:     .green
    case .error:    .red
    case .idle:     .secondary
    }
}

private func relativeTime(from date: Date, to now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
}
