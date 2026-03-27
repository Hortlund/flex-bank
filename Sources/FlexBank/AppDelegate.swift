import AppKit
import FlexBankCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FlexStore()
    private var notificationCenter: UNUserNotificationCenter?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var statsWindowController: StatsWindowController?

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
            store.addTime(minutes: minutes)
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
            store.removeTime(minutes: minutes)
            refreshUI()
        }
    }

    @objc private func setQuickAddMinutes() {
        promptForText(
            title: "Change default quick add",
            message: "Set the default minutes used when you choose Quick add.",
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
            title: "Change reminder time",
            message: "Enter the weekday reminder time in HH:MM.",
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
        alert.informativeText = "This adds an internal balance adjustment and sets your balance to 0:00 without wiping the history."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            store.resetBank()
            refreshUI()
        }
    }

    @objc private func openStatsWindow() {
        if statsWindowController == nil {
            statsWindowController = StatsWindowController(store: store)
        }

        statsWindowController?.show()
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
        let bank = formatSignedMinutes(store.balanceMinutes)
        button.title = "⏱ \(bank)"
        button.toolTip = "Flex bank: \(bank)"
    }

    private func rebuildMenu() {
        let stats = store.stats()
        let settings = store.state.settings
        let quickAddUsedToday = store.hasLoggedQuickAddToday()
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(makeSectionHeader("Status"))

        let bankItem = NSMenuItem(title: "Flex bank: \(formatSignedMinutes(store.balanceMinutes))", action: nil, keyEquivalent: "")
        bankItem.isEnabled = false
        menu.addItem(bankItem)

        let last30Item = NSMenuItem(
            title: "Last 30d: \(formatSignedMinutes(stats.last30NetMinutes)) across \(stats.last30ActiveDays) logged day\(stats.last30ActiveDays == 1 ? "" : "s")",
            action: nil,
            keyEquivalent: ""
        )
        last30Item.isEnabled = false
        menu.addItem(last30Item)

        let streakItem = NSMenuItem(
            title: "Quick-add streak: \(stats.currentQuickAddStreak)d (best \(stats.bestQuickAddStreak)d)",
            action: nil,
            keyEquivalent: ""
        )
        streakItem.isEnabled = false
        menu.addItem(streakItem)

        menu.addItem(.separator())
        menu.addItem(makeSectionHeader("Actions"))

        let quickAddItem = makeItem("Quick add now (+\(settings.quickAddMinutes)m)", action: #selector(quickAdd))
        quickAddItem.isEnabled = !quickAddUsedToday
        menu.addItem(quickAddItem)

        if quickAddUsedToday {
            menu.addItem(makeInfoItem("Already logged today"))
        }

        menu.addItem(makeItem("Add time...", action: #selector(addTime)))
        menu.addItem(makeItem("Remove time...", action: #selector(removeTime)))
        menu.addItem(makeItem("Open stats dashboard...", action: #selector(openStatsWindow)))
        menu.addItem(.separator())

        menu.addItem(makeSectionHeader("Settings"))
        menu.addItem(makeInfoItem("Default quick add: +\(settings.quickAddMinutes)m"))
        menu.addItem(makeItem("Change default quick add...", action: #selector(setQuickAddMinutes)))
        menu.addItem(
            makeInfoItem(
                "Weekday reminder: \(settings.reminderEnabled ? "On" : "Off") at \(String(format: "%02d:%02d", settings.reminderHour, settings.reminderMinute))"
            )
        )
        menu.addItem(makeItem("Change reminder time...", action: #selector(setReminderTime)))
        menu.addItem(makeItem(settings.reminderEnabled ? "Turn reminders off" : "Turn reminders on", action: #selector(toggleReminder)))
        menu.addItem(makeItem("Reset time bank...", action: #selector(resetBank)))

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit FlexBank", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func makeItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func makeSectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    private func makeInfoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
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
            let request = UNNotificationRequest(
                identifier: "\(reminderBaseID).\(weekday)",
                content: content,
                trigger: trigger
            )
            notificationCenter.add(request)
        }
    }
}
