import Foundation

public struct FlexSettings: Codable, Equatable, Sendable {
    public var quickAddMinutes: Int
    public var reminderHour: Int
    public var reminderMinute: Int
    public var reminderEnabled: Bool

    public init(
        quickAddMinutes: Int = 30,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        reminderEnabled: Bool = true
    ) {
        self.quickAddMinutes = quickAddMinutes
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.reminderEnabled = reminderEnabled
    }
}

public enum FlexEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case quickAdd
    case manualAdd
    case manualRemove
    case balanceAdjustment

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quickAdd:
            "Quick add"
        case .manualAdd:
            "Added time"
        case .manualRemove:
            "Removed time"
        case .balanceAdjustment:
            "Balance reset"
        }
    }

    public var participatesInTimeInsights: Bool {
        self != .balanceAdjustment
    }
}

public struct FlexEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var occurredAt: Date
    public var kind: FlexEventKind
    public var deltaMinutes: Int

    public init(
        id: UUID = UUID(),
        occurredAt: Date,
        kind: FlexEventKind,
        deltaMinutes: Int
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.deltaMinutes = deltaMinutes
    }
}

public struct FlexState: Codable, Equatable, Sendable {
    public var events: [FlexEvent]
    public var settings: FlexSettings

    public init(events: [FlexEvent] = [], settings: FlexSettings = FlexSettings()) {
        self.events = events
        self.settings = settings
    }
}

public enum FlexHeatmapMetric: String, CaseIterable, Identifiable, Sendable {
    case net
    case quickAdd
    case manualAdd
    case manualRemove

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .net:
            "Net"
        case .quickAdd:
            "Quick Add"
        case .manualAdd:
            "Added"
        case .manualRemove:
            "Removed"
        }
    }
}

public struct FlexDaySummary: Equatable, Identifiable, Sendable {
    public let date: Date
    public let events: [FlexEvent]
    public let netMinutes: Int
    public let quickAddMinutes: Int
    public let addedMinutes: Int
    public let removedMinutes: Int

    public var id: Date { date }

    public var activeEventCount: Int {
        events.filter { $0.kind != .balanceAdjustment }.count
    }

    public func value(for metric: FlexHeatmapMetric) -> Int {
        switch metric {
        case .net:
            netMinutes
        case .quickAdd:
            quickAddMinutes
        case .manualAdd:
            addedMinutes
        case .manualRemove:
            removedMinutes
        }
    }
}

public struct FlexWeekdayCount: Equatable, Identifiable, Sendable {
    public let weekday: Int
    public let label: String
    public let count: Int

    public var id: Int { weekday }
}

public struct FlexTimeOfDaySummary: Equatable, Identifiable, Sendable {
    public let kind: FlexEventKind
    public let label: String
    public let sampleCount: Int
    public let typicalMinutesFromMidnight: Int?

    public var id: FlexEventKind { kind }
}

public struct FlexStatsSnapshot: Equatable, Sendable {
    public let daySummaries: [FlexDaySummary]
    public let last30NetMinutes: Int
    public let last30ActiveDays: Int
    public let currentQuickAddStreak: Int
    public let bestQuickAddStreak: Int
    public let thisMonthNetMinutes: Int
    public let thisMonthLoggedDays: Int
    public let quickAddWeekdays: [FlexWeekdayCount]
    public let removeWeekdays: [FlexWeekdayCount]
    public let typicalTimes: [FlexTimeOfDaySummary]
    public let heatmapWindowStartDate: Date
    public let heatmapWindowEndDate: Date
    public let heatmapGridStartDate: Date
    public let heatmapGridEndDate: Date

    public func summary(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> FlexDaySummary? {
        let startOfDay = calendar.startOfDay(for: date)
        return daySummaries.first { calendar.isDate($0.date, inSameDayAs: startOfDay) }
    }
}
