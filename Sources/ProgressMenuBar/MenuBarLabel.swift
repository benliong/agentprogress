import ProgressCore
import SwiftUI

struct MenuBarLabel: View {
    let actives: [ProgressEntry]

    private var symbolName: String {
        if actives.count > 1 { return "cpu" }
        return actives.first?.status.symbolName ?? "circle.dotted"
    }

    private var labelText: String {
        if actives.isEmpty { return "idle" }
        if actives.count > 1 { return "\(actives.count) agents" }
        let entry = actives[0]
        let combined = "\(entry.project) · \(entry.task)"
        return combined.count > 40 ? String(combined.prefix(37)) + "…" : combined
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
            Text(labelText)
                .lineLimit(1)
        }
    }
}
