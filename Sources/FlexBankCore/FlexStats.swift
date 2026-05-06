import Foundation

public enum FlexStatsEngine {
    public static let minimumInsightSamples = 3
    public static let heatmapFuturePaddingDays = 56

    public static func makeSnapshot(
        from events: [FlexEvent],
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> FlexStatsSnapshot {
        let sortedEvents = events.sorted { $0.occurredAt < $1.occurredAt }
        let daySummaries = makeDaySummaries(from: sortedEvents, calendar: calendar)

        let windowEnd = calendar.startOfDay(for: referenceDate)
        let windowStart = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -364, to: windowEnd) ?? windowEnd
        )
        let gridStart = startOfWeek(containing: windowStart, calendar: calendar)
        let paddedWindowEnd = calendar.date(
            byAdding: .day,
            value: heatmapFuturePaddingDays,
            to: windowEnd
        ) ?? windowEnd
        let gridEnd = endOfWeek(containing: paddedWindowEnd, calendar: calendar)

        let last30Start = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -29, to: windowEnd) ?? windowEnd
        )
        let last30Summaries = daySummaries.filter { $0.date >= last30Start && $0.date <= windowEnd }

        let monthInterval = calendar.dateInterval(of: .month, for: windowEnd)
        let thisMonthSummaries = daySummaries.filter { summary in
            guard let monthInterval else { return false }
            return monthInterval.contains(summary.date)
        }

        let quickAddDates = Set(sortedEvents.compactMap { event -> Date? in
            guard event.kind == .quickAdd else { return nil }
            return calendar.startOfDay(for: event.occurredAt)
        })

        let quickAddStreaks = makeQuickAddStreaks(
            quickAddDates: quickAddDates,
            referenceDate: windowEnd,
            calendar: calendar
        )

        return FlexStatsSnapshot(
            daySummaries: daySummaries,
            last30NetMinutes: last30Summaries.reduce(0) { $0 + $1.netMinutes },
            last30ActiveDays: last30Summaries.filter { $0.activeEventCount > 0 }.count,
            currentQuickAddStreak: quickAddStreaks.current,
            bestQuickAddStreak: quickAddStreaks.best,
            thisMonthNetMinutes: thisMonthSummaries.reduce(0) { $0 + $1.netMinutes },
            thisMonthLoggedDays: thisMonthSummaries.filter { $0.activeEventCount > 0 }.count,
            quickAddWeekdays: makeWeekdayCounts(
                from: sortedEvents.filter { $0.kind == .quickAdd },
                calendar: calendar
            ),
            removeWeekdays: makeWeekdayCounts(
                from: sortedEvents.filter { $0.kind == .manualRemove },
                calendar: calendar
            ),
            typicalTimes: makeTypicalTimes(from: sortedEvents, calendar: calendar),
            heatmapWindowStartDate: windowStart,
            heatmapWindowEndDate: windowEnd,
            heatmapGridStartDate: gridStart,
            heatmapGridEndDate: gridEnd
        )
    }

    private static func makeDaySummaries(
        from sortedEvents: [FlexEvent],
        calendar: Calendar
    ) -> [FlexDaySummary] {
        let grouped = Dictionary(grouping: sortedEvents) { event in
            calendar.startOfDay(for: event.occurredAt)
        }

        return grouped
            .map { date, events in
                let orderedEvents = events.sorted { $0.occurredAt < $1.occurredAt }
                var netMinutes = 0
                var quickAddMinutes = 0
                var addedMinutes = 0
                var removedMinutes = 0

                for event in orderedEvents {
                    netMinutes += event.deltaMinutes

                    switch event.kind {
                    case .quickAdd:
                        quickAddMinutes += max(0, event.deltaMinutes)
                    case .manualAdd:
                        addedMinutes += max(0, event.deltaMinutes)
                    case .manualRemove:
                        removedMinutes += abs(event.deltaMinutes)
                    case .balanceAdjustment:
                        break
                    }
                }

                return FlexDaySummary(
                    date: date,
                    events: orderedEvents,
                    netMinutes: netMinutes,
                    quickAddMinutes: quickAddMinutes,
                    addedMinutes: addedMinutes,
                    removedMinutes: removedMinutes
                )
            }
            .sorted { $0.date < $1.date }
    }

    private static func makeWeekdayCounts(
        from events: [FlexEvent],
        calendar: Calendar
    ) -> [FlexWeekdayCount] {
        let counts = events.reduce(into: [Int: Int]()) { partialResult, event in
            let weekday = calendar.component(.weekday, from: event.occurredAt)
            partialResult[weekday, default: 0] += 1
        }

        return orderedWeekdays(calendar: calendar).map { weekday in
            FlexWeekdayCount(
                weekday: weekday,
                label: weekdayLabel(for: weekday),
                count: counts[weekday, default: 0]
            )
        }
    }

    private static func makeTypicalTimes(
        from events: [FlexEvent],
        calendar: Calendar
    ) -> [FlexTimeOfDaySummary] {
        let orderedKinds: [FlexEventKind] = [.quickAdd, .manualAdd, .manualRemove]

        return orderedKinds.map { kind in
            let minutes = events
                .filter { $0.kind == kind }
                .map { event -> Int in
                    let components = calendar.dateComponents([.hour, .minute], from: event.occurredAt)
                    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
                }
                .sorted()

            let typicalMinutes: Int?
            if minutes.count >= minimumInsightSamples {
                typicalMinutes = minutes[minutes.count / 2]
            } else {
                typicalMinutes = nil
            }

            return FlexTimeOfDaySummary(
                kind: kind,
                label: kind.title,
                sampleCount: minutes.count,
                typicalMinutesFromMidnight: typicalMinutes
            )
        }
    }

    private static func makeQuickAddStreaks(
        quickAddDates: Set<Date>,
        referenceDate: Date,
        calendar: Calendar
    ) -> (current: Int, best: Int) {
        let sortedDates = quickAddDates.sorted()
        guard !sortedDates.isEmpty else { return (0, 0) }

        var best = 0
        var running = 0
        var previous: Date?

        for date in sortedDates {
            if let previous, isConsecutiveTrackedDay(previous, date, calendar: calendar) {
                running += 1
            } else {
                running = 1
            }

            best = max(best, running)
            previous = date
        }

        var current = 0
        var cursor = latestTrackedWorkday(onOrBefore: referenceDate, calendar: calendar)
        while let currentDate = cursor, quickAddDates.contains(currentDate) {
            current += 1
            cursor = previousTrackedWorkday(before: currentDate, calendar: calendar)
        }

        return (current, best)
    }

    private static func latestTrackedWorkday(
        onOrBefore date: Date,
        calendar: Calendar
    ) -> Date? {
        var current = calendar.startOfDay(for: date)
        while calendar.isDateInWeekend(current) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else { return nil }
            current = calendar.startOfDay(for: previous)
        }
        return current
    }

    private static func previousTrackedWorkday(
        before date: Date,
        calendar: Calendar
    ) -> Date? {
        var current = calendar.startOfDay(for: date)
        while true {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else { return nil }
            current = calendar.startOfDay(for: previous)
            if !calendar.isDateInWeekend(current) {
                return current
            }
        }
    }

    private static func isConsecutiveTrackedDay(
        _ lhs: Date,
        _ rhs: Date,
        calendar: Calendar
    ) -> Bool {
        previousTrackedWorkday(before: rhs, calendar: calendar) == lhs
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
    }

    private static func endOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let start = startOfWeek(containing: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return calendar.startOfDay(for: end)
    }

    private static func orderedWeekdays(calendar: Calendar) -> [Int] {
        let firstWeekday = calendar.firstWeekday
        return (0..<7).map { offset in
            ((firstWeekday - 1 + offset) % 7) + 1
        }
    }

    private static func weekdayLabel(for weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        return formatter.shortWeekdaySymbols[weekday - 1]
    }
}
