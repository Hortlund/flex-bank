import FlexBankCore
import Foundation
import SwiftUI

func formatSignedMinutes(_ minutes: Int) -> String {
    let sign = minutes < 0 ? "-" : "+"
    let absolute = abs(minutes)
    let hours = absolute / 60
    let remainingMinutes = absolute % 60
    return String(format: "%@%d:%02d", sign, hours, remainingMinutes)
}

func formatUnsignedMinutes(_ minutes: Int) -> String {
    let absolute = abs(minutes)
    let hours = absolute / 60
    let remainingMinutes = absolute % 60
    return String(format: "%d:%02d", hours, remainingMinutes)
}

func formatEventDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

func formatEventTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
}

func formatTypicalTime(_ minutesFromMidnight: Int?) -> String {
    guard let minutesFromMidnight else { return "Need 3 samples" }
    var components = DateComponents()
    components.hour = minutesFromMidnight / 60
    components.minute = minutesFromMidnight % 60

    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeStyle = .short
    formatter.dateStyle = .none

    let calendar = Calendar.autoupdatingCurrent
    return calendar.date(from: components).map { formatter.string(from: $0) } ?? "n/a"
}

func label(for event: FlexEvent) -> String {
    event.kind.title
}

func eventAccentColor(for kind: FlexEventKind) -> Color {
    switch kind {
    case .quickAdd:
        return Color(red: 0.14, green: 0.63, blue: 0.55)
    case .manualAdd:
        return Color(red: 0.12, green: 0.46, blue: 0.82)
    case .manualRemove:
        return Color(red: 0.87, green: 0.43, blue: 0.18)
    case .balanceAdjustment:
        return Color.secondary
    }
}

func heatmapColor(
    value: Int,
    metric: FlexHeatmapMetric,
    maxMagnitude: Int
) -> Color {
    guard value != 0 else {
        return Color(NSColor.quaternaryLabelColor).opacity(0.18)
    }

    let intensity = max(0.2, min(1, Double(abs(value)) / Double(max(maxMagnitude, 1))))

    switch metric {
    case .net:
        if value > 0 {
            return Color(red: 0.12, green: 0.58, blue: 0.29).opacity(0.22 + 0.68 * intensity)
        }
        return Color(red: 0.83, green: 0.21, blue: 0.21).opacity(0.22 + 0.68 * intensity)
    case .quickAdd:
        return eventAccentColor(for: .quickAdd).opacity(0.22 + 0.68 * intensity)
    case .manualAdd:
        return eventAccentColor(for: .manualAdd).opacity(0.22 + 0.68 * intensity)
    case .manualRemove:
        return eventAccentColor(for: .manualRemove).opacity(0.22 + 0.68 * intensity)
    }
}
