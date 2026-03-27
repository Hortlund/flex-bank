import Foundation

public enum FlexDemoSeed {
    public static func makeState(
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> FlexState {
        let windowEnd = calendar.startOfDay(for: referenceDate)
        let windowStart = calendar.date(byAdding: .day, value: -329, to: windowEnd) ?? windowEnd

        var events: [FlexEvent] = []
        var currentDate = windowStart
        var workdayIndex = 0
        let recentTrackedDates = lastTrackedDates(count: 6, endingAt: windowEnd, calendar: calendar)

        while currentDate <= windowEnd {
            defer {
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }

            guard !calendar.isDateInWeekend(currentDate) else { continue }

            let shouldForceRecentQuickAdd = recentTrackedDates.contains(calendar.startOfDay(for: currentDate))
            let quickAddMinutesPattern = [45, 30, 45, 60, 30]
            let quickAddMinutes = quickAddMinutesPattern[workdayIndex % quickAddMinutesPattern.count]
            let morningHour = workdayIndex.isMultiple(of: 3) ? 7 : 8
            let morningMinute = 12 + ((workdayIndex * 7) % 34)

            if shouldForceRecentQuickAdd || workdayIndex % 6 != 1 {
                events.append(
                    FlexEvent(
                        occurredAt: makeDate(
                            day: currentDate,
                            hour: morningHour,
                            minute: morningMinute,
                            calendar: calendar
                        ),
                        kind: .quickAdd,
                        deltaMinutes: quickAddMinutes
                    )
                )
            }

            if workdayIndex % 4 == 1 || workdayIndex % 11 == 6 {
                let removeMinutes = 15 + ((workdayIndex % 3) * 15)
                events.append(
                    FlexEvent(
                        occurredAt: makeDate(
                            day: currentDate,
                            hour: 16,
                            minute: 5 + ((workdayIndex * 5) % 35),
                            calendar: calendar
                        ),
                        kind: .manualRemove,
                        deltaMinutes: -removeMinutes
                    )
                )
            }

            if workdayIndex % 7 == 2 || workdayIndex % 13 == 5 {
                let addMinutes = workdayIndex.isMultiple(of: 5) ? 45 : 30
                events.append(
                    FlexEvent(
                        occurredAt: makeDate(
                            day: currentDate,
                            hour: 12,
                            minute: 10 + ((workdayIndex * 3) % 25),
                            calendar: calendar
                        ),
                        kind: .manualAdd,
                        deltaMinutes: addMinutes
                    )
                )
            }

            if workdayIndex % 17 == 8 {
                events.append(
                    FlexEvent(
                        occurredAt: makeDate(
                            day: currentDate,
                            hour: 18,
                            minute: 6 + (workdayIndex % 11),
                            calendar: calendar
                        ),
                        kind: .manualRemove,
                        deltaMinutes: -30
                    )
                )
            }

            workdayIndex += 1
        }

        return FlexState(
            events: events.sorted { $0.occurredAt < $1.occurredAt },
            settings: FlexSettings(
                quickAddMinutes: 45,
                reminderHour: 9,
                reminderMinute: 15,
                reminderEnabled: true
            )
        )
    }

    private static func makeDate(
        day: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: startOfDay
        ) ?? startOfDay
    }

    private static func lastTrackedDates(
        count: Int,
        endingAt date: Date,
        calendar: Calendar
    ) -> Set<Date> {
        var results: [Date] = []
        var cursor = calendar.startOfDay(for: date)

        while results.count < count {
            if !calendar.isDateInWeekend(cursor) {
                results.append(cursor)
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: previous)
        }

        return Set(results)
    }
}
