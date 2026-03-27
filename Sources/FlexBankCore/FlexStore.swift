import Combine
import Foundation

@MainActor
public final class FlexStore: ObservableObject {
    @Published public private(set) var state: FlexState

    public let stateFileURL: URL

    private let calendar: Calendar
    private let fileManager: FileManager

    public init(
        fileManager: FileManager = .default,
        stateFileURL: URL? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.stateFileURL = stateFileURL ?? Self.makeDefaultStateFileURL(fileManager: fileManager)

        do {
            try fileManager.createDirectory(
                at: self.stateFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("FlexBank: failed to create Application Support folder: \(error)")
        }

        if
            let data = try? Data(contentsOf: self.stateFileURL),
            let decoded = Self.decodeState(from: data)
        {
            state = decoded
        } else {
            state = FlexState()
            save()
        }
    }

    public var balanceMinutes: Int {
        state.events.reduce(into: 0) { partialResult, event in
            partialResult += event.deltaMinutes
        }
    }

    public func stats(referenceDate: Date = Date()) -> FlexStatsSnapshot {
        FlexStatsEngine.makeSnapshot(
            from: state.events,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    public func logQuickAdd(now: Date = Date()) -> Bool {
        let minutes = max(0, state.settings.quickAddMinutes)
        guard minutes > 0 else { return false }
        guard !hasLoggedQuickAddToday(now: now) else { return false }
        appendEvent(kind: .quickAdd, deltaMinutes: minutes, now: now)
        return true
    }

    public func hasLoggedQuickAddToday(now: Date = Date()) -> Bool {
        let today = calendar.startOfDay(for: now)
        return state.events.contains { event in
            event.kind == .quickAdd && calendar.isDate(event.occurredAt, inSameDayAs: today)
        }
    }

    public func addTime(minutes: Int, now: Date = Date()) {
        let normalized = abs(minutes)
        guard normalized > 0 else { return }
        appendEvent(kind: .manualAdd, deltaMinutes: normalized, now: now)
    }

    public func removeTime(minutes: Int, now: Date = Date()) {
        let normalized = abs(minutes)
        guard normalized > 0 else { return }
        appendEvent(kind: .manualRemove, deltaMinutes: -normalized, now: now)
    }

    public func updateQuickAddMinutes(_ minutes: Int) {
        state.settings.quickAddMinutes = max(0, minutes)
        save()
    }

    public func updateReminderTime(hour: Int, minute: Int) {
        state.settings.reminderHour = max(0, min(23, hour))
        state.settings.reminderMinute = max(0, min(59, minute))
        save()
    }

    public func setReminderEnabled(_ enabled: Bool) {
        state.settings.reminderEnabled = enabled
        save()
    }

    public func resetBank(now: Date = Date()) {
        let currentBalance = balanceMinutes
        guard currentBalance != 0 else { return }
        appendEvent(kind: .balanceAdjustment, deltaMinutes: -currentBalance, now: now)
    }

    private func appendEvent(kind: FlexEventKind, deltaMinutes: Int, now: Date) {
        guard deltaMinutes != 0 else { return }
        state.events.append(
            FlexEvent(
                occurredAt: now,
                kind: kind,
                deltaMinutes: deltaMinutes
            )
        )
        save()
    }

    private func save() {
        do {
            let data = try Self.makeEncoder().encode(state)
            try data.write(to: stateFileURL, options: [.atomic])
        } catch {
            NSLog("FlexBank: failed to save state: \(error)")
        }
    }

    private static func decodeState(from data: Data) -> FlexState? {
        do {
            return try makeDecoder().decode(FlexState.self, from: data)
        } catch {
            NSLog("FlexBank: failed to decode state, starting fresh: \(error)")
            return nil
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeDefaultStateFileURL(fileManager: FileManager) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupportURL
            .appendingPathComponent("FlexBank", isDirectory: true)
            .appendingPathComponent("state.json")
    }
}
