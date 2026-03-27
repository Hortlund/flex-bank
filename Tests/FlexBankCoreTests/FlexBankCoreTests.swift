import Foundation
import Testing
@testable import FlexBankCore

struct FlexBankCoreTests {
    @Test
    func statsGroupEventsByLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3600)!

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let events = [
            FlexEvent(
                occurredAt: formatter.date(from: "2026-03-27T22:30:00Z")!,
                kind: .manualAdd,
                deltaMinutes: 30
            ),
            FlexEvent(
                occurredAt: formatter.date(from: "2026-03-27T23:30:00Z")!,
                kind: .manualRemove,
                deltaMinutes: -15
            ),
        ]

        let snapshot = FlexStatsEngine.makeSnapshot(
            from: events,
            referenceDate: formatter.date(from: "2026-03-28T12:00:00Z")!,
            calendar: calendar
        )

        #expect(snapshot.daySummaries.count == 2)
        #expect(snapshot.daySummaries[0].netMinutes == 30)
        #expect(snapshot.daySummaries[1].netMinutes == -15)
    }

    @MainActor
    @Test
    func quickAddLocksOutWithinSameDay() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let store = FlexStore(
            stateFileURL: tempDirectory.appendingPathComponent("state.json"),
            calendar: calendar
        )

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let morning = formatter.date(from: "2026-03-27T07:30:00Z")!
        let later = formatter.date(from: "2026-03-27T09:00:00Z")!
        let nextDay = formatter.date(from: "2026-03-28T08:00:00Z")!

        #expect(store.logQuickAdd(now: morning))
        #expect(!store.logQuickAdd(now: later))
        #expect(store.logQuickAdd(now: nextDay))
    }

    @MainActor
    @Test
    func balanceIsDerivedFromMixedEventsAndResetAdjustment() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let store = FlexStore(stateFileURL: tempDirectory.appendingPathComponent("state.json"))
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        store.addTime(minutes: 60, now: formatter.date(from: "2026-03-24T08:00:00Z")!)
        store.removeTime(minutes: 15, now: formatter.date(from: "2026-03-24T15:00:00Z")!)
        #expect(store.logQuickAdd(now: formatter.date(from: "2026-03-25T07:40:00Z")!))

        #expect(store.balanceMinutes == 75)

        store.resetBank(now: formatter.date(from: "2026-03-25T17:00:00Z")!)

        #expect(store.balanceMinutes == 0)
        #expect(store.state.events.last?.kind == .balanceAdjustment)
        #expect(store.state.events.last?.deltaMinutes == -75)
    }

    @Test
    func typicalTimesUseMedianAndIgnoreBalanceAdjustments() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let events = [
            FlexEvent(occurredAt: formatter.date(from: "2026-03-23T07:30:00Z")!, kind: .quickAdd, deltaMinutes: 30),
            FlexEvent(occurredAt: formatter.date(from: "2026-03-24T07:40:00Z")!, kind: .quickAdd, deltaMinutes: 30),
            FlexEvent(occurredAt: formatter.date(from: "2026-03-25T07:50:00Z")!, kind: .quickAdd, deltaMinutes: 30),
            FlexEvent(occurredAt: formatter.date(from: "2026-03-25T12:00:00Z")!, kind: .balanceAdjustment, deltaMinutes: -90),
        ]

        let snapshot = FlexStatsEngine.makeSnapshot(from: events, calendar: calendar)
        let quickAddTime = snapshot.typicalTimes.first { $0.kind == .quickAdd }

        #expect(quickAddTime?.sampleCount == 3)
        #expect(quickAddTime?.typicalMinutesFromMidnight == 460)
    }

    @Test
    func weekdayRankingAndStreaksHandleWeekendCarry() {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let events = [
            FlexEvent(occurredAt: formatter.date(from: "2026-03-05T07:30:00Z")!, kind: .quickAdd, deltaMinutes: 30),
            FlexEvent(occurredAt: formatter.date(from: "2026-03-06T07:35:00Z")!, kind: .quickAdd, deltaMinutes: 30),
            FlexEvent(occurredAt: formatter.date(from: "2026-03-09T07:40:00Z")!, kind: .quickAdd, deltaMinutes: 30),
            FlexEvent(occurredAt: formatter.date(from: "2026-03-10T07:45:00Z")!, kind: .quickAdd, deltaMinutes: 30),
            FlexEvent(occurredAt: formatter.date(from: "2026-03-04T16:00:00Z")!, kind: .manualRemove, deltaMinutes: -30),
            FlexEvent(occurredAt: formatter.date(from: "2026-03-11T16:10:00Z")!, kind: .manualRemove, deltaMinutes: -30),
        ]

        let referenceDate = formatter.date(from: "2026-03-10T18:00:00Z")!
        let snapshot = FlexStatsEngine.makeSnapshot(from: events, referenceDate: referenceDate)

        #expect(snapshot.bestQuickAddStreak == 4)
        #expect(snapshot.currentQuickAddStreak == 4)
        #expect(snapshot.removeWeekdays.contains(where: { $0.count == 2 }))
    }

    @Test
    func demoSeedProducesRichHistoryForDashboard() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let referenceDate = formatter.date(from: "2026-03-27T12:00:00Z")!

        let state = FlexDemoSeed.makeState(
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(state.settings.quickAddMinutes == 45)
        #expect(state.events.count > 150)
        #expect(state.events.contains(where: { $0.kind == .quickAdd }))
        #expect(state.events.contains(where: { $0.kind == .manualAdd }))
        #expect(state.events.contains(where: { $0.kind == .manualRemove }))

        let snapshot = FlexStatsEngine.makeSnapshot(
            from: state.events,
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(snapshot.daySummaries.count > 100)
        #expect(snapshot.currentQuickAddStreak >= 5)
        #expect(snapshot.typicalTimes.allSatisfy { $0.sampleCount >= 3 })
    }
}
