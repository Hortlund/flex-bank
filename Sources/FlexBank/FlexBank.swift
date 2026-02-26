import AppKit
import Foundation
import UserNotifications

@main
struct FlexBankMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

struct FlexSettings: Codable {
    var quickAddMinutes: Int = 30
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    var reminderEnabled: Bool = true
}

struct FlexState: Codable {
    var bankMinutes: Int = 0
    var quickAddByDate: [String: Int] = [:]
    var settings = FlexSettings()
}

@MainActor
final class FlexStore {
    private(set) var state: FlexState

    private let stateFileURL: URL
    private let appFolderName = "FlexBank"
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(fileManager: FileManager = .default) {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folderURL = appSupportURL.appendingPathComponent(appFolderName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            NSLog("FlexBank: failed to create Application Support folder: \(error)")
        }

        stateFileURL = folderURL.appendingPathComponent("state.json")

        if
            let data = try? Data(contentsOf: stateFileURL),
            let decoded = try? JSONDecoder().decode(FlexState.self, from: data)
        {
            state = decoded
        } else {
            state = FlexState()
            save()
        }
    }

    func logQuickAdd(now: Date = Date()) -> Bool {
        pruneOldQuickAddLogs(reference: now)
        let key = dateKey(for: now)
        guard state.quickAddByDate[key] == nil else { return false }
        state.quickAddByDate[key] = state.settings.quickAddMinutes
        state.bankMinutes += state.settings.quickAddMinutes
        save()
        return true
    }

    func hasLoggedQuickAddToday(now: Date = Date()) -> Bool {
        state.quickAddByDate[dateKey(for: now)] != nil
    }

    func adjustBank(by minutes: Int) {
        guard minutes != 0 else { return }
        state.bankMinutes += minutes
        save()
    }

    func updateQuickAddMinutes(_ minutes: Int) {
        state.settings.quickAddMinutes = max(0, minutes)
        save()
    }

    func updateReminderTime(hour: Int, minute: Int) {
        state.settings.reminderHour = max(0, min(23, hour))
        state.settings.reminderMinute = max(0, min(59, minute))
        save()
    }

    func setReminderEnabled(_ enabled: Bool) {
        state.settings.reminderEnabled = enabled
        save()
    }

    func resetBank() {
        state.bankMinutes = 0
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateFileURL, options: [.atomic])
        } catch {
            NSLog("FlexBank: failed to save state: \(error)")
        }
    }

    private func dateKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func pruneOldQuickAddLogs(reference: Date) {
        let calendar = Calendar.current
        state.quickAddByDate = state.quickAddByDate.filter { key, _ in
            guard let date = dayFormatter.date(from: key) else { return false }
            let days = calendar.dateComponents([.day], from: date, to: reference).day ?? 0
            return days < 90
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FlexStore()
    private var notificationCenter: UNUserNotificationCenter?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?

    private let reminderBaseID = "com.flexbank.reminder"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if Bundle.main.bundleURL.pathExtension == "app" {
            notificationCenter = UNUserNotificationCenter.current()
            configureReminders()
        }
        startRefreshTimer()
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    @objc private func quickAdd() {
        guard store.logQuickAdd() else {
            NSSound.beep()
            return
        }
        refreshUI()
    }

    @objc private func addTime() {
        promptForText(
            title: "Add flex time",
            message: "Enter positive minutes to add.",
            defaultValue: "30"
        ) { [weak self] text in
            guard let self, let text, let minutes = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            guard minutes > 0 else { return }
            store.adjustBank(by: minutes)
            refreshUI()
        }
    }

    @objc private func removeTime() {
        promptForText(
            title: "Remove flex time",
            message: "Enter positive minutes to remove.",
            defaultValue: "30"
        ) { [weak self] text in
            guard let self, let text, let minutes = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            guard minutes > 0 else { return }
            store.adjustBank(by: -minutes)
            refreshUI()
        }
    }

    @objc private func setQuickAddMinutes() {
        promptForText(
            title: "Quick add minutes",
            message: "Minutes to add when you use quick add.",
            defaultValue: "\(store.state.settings.quickAddMinutes)"
        ) { [weak self] text in
            guard let self, let text, let minutes = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            store.updateQuickAddMinutes(minutes)
            refreshUI()
        }
    }

    @objc private func setReminderTime() {
        let settings = store.state.settings
        let defaultValue = String(format: "%02d:%02d", settings.reminderHour, settings.reminderMinute)

        promptForText(
            title: "Reminder time",
            message: "Enter 24h time in HH:MM (for weekdays).",
            defaultValue: defaultValue
        ) { [weak self] text in
            guard let self, let text else { return }
            let pieces = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
            guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]) else { return }
            guard (0...23).contains(hour), (0...59).contains(minute) else { return }
            store.updateReminderTime(hour: hour, minute: minute)
            scheduleReminders()
            refreshUI()
        }
    }

    @objc private func toggleReminder() {
        store.setReminderEnabled(!store.state.settings.reminderEnabled)
        scheduleReminders()
        refreshUI()
    }

    @objc private func resetBank() {
        let alert = NSAlert()
        alert.messageText = "Reset time bank?"
        alert.informativeText = "This sets your balance to 0:00."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.resetBank()
            refreshUI()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshUI()
            }
        }
    }

    private func refreshUI() {
        updateStatusTitle()
        rebuildMenu()
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        let bank = formatSignedMinutes(store.state.bankMinutes)
        button.title = "⏱ \(bank)"
        button.toolTip = "Flex bank: \(bank)"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let bankItem = NSMenuItem(title: "Flex bank: \(formatSignedMinutes(store.state.bankMinutes))", action: nil, keyEquivalent: "")
        bankItem.isEnabled = false
        menu.addItem(bankItem)

        let quickAddMinutes = store.state.settings.quickAddMinutes
        let quickAddItem = makeItem("Quick add +\(quickAddMinutes)m", action: #selector(quickAdd))
        quickAddItem.isEnabled = !store.hasLoggedQuickAddToday()
        menu.addItem(quickAddItem)

        if store.hasLoggedQuickAddToday() {
            let doneItem = NSMenuItem(title: "Quick add already used today", action: nil, keyEquivalent: "")
            doneItem.isEnabled = false
            menu.addItem(doneItem)
        }

        menu.addItem(makeItem("Add time...", action: #selector(addTime)))
        menu.addItem(makeItem("Remove time...", action: #selector(removeTime)))
        menu.addItem(.separator())

        let settings = store.state.settings
        menu.addItem(makeItem("Quick add minutes: \(settings.quickAddMinutes)...", action: #selector(setQuickAddMinutes)))
        menu.addItem(makeItem("Reminder time: \(String(format: "%02d:%02d", settings.reminderHour, settings.reminderMinute))...", action: #selector(setReminderTime)))
        menu.addItem(makeItem("Reminder: \(settings.reminderEnabled ? "On" : "Off")", action: #selector(toggleReminder)))
        menu.addItem(makeItem("Reset time bank...", action: #selector(resetBank)))

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func makeItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func promptForText(title: String, message: String, defaultValue: String, completion: (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completion(input.stringValue)
        } else {
            completion(nil)
        }
    }

    private func configureReminders() {
        guard let notificationCenter else { return }
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.scheduleReminders()
            }
        }
    }

    private func scheduleReminders() {
        guard let notificationCenter else { return }
        let allReminderIDs = (2...6).map { "\(reminderBaseID).\($0)" }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: allReminderIDs)

        guard store.state.settings.reminderEnabled else { return }

        let settings = store.state.settings
        for weekday in 2...6 {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = settings.reminderHour
            components.minute = settings.reminderMinute

            let content = UNMutableNotificationContent()
            content.title = "FlexTime reminder"
            content.body = "Remember to update your flex bank (+ or - minutes). Quick add is +\(settings.quickAddMinutes)m."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "\(reminderBaseID).\(weekday)", content: content, trigger: trigger)
            notificationCenter.add(request)
        }
    }

    private func formatSignedMinutes(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : "+"
        let absolute = abs(minutes)
        let hours = absolute / 60
        let remainingMinutes = absolute % 60
        return String(format: "%@%d:%02d", sign, hours, remainingMinutes)
    }
}
