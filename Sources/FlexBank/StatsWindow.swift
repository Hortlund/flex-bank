import AppKit
import Charts
import FlexBankCore
import SwiftUI

@MainActor
final class StatsWindowController: NSWindowController {
    init(store: FlexStore) {
        let rootView = StatsDashboardView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "FlexBank Stats"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1080, height: 760))
        window.minSize = NSSize(width: 980, height: 700)
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct StatsDashboardView: View {
    @ObservedObject var store: FlexStore
    @State private var selectedMetric: FlexHeatmapMetric = .net
    @State private var selectedDay: Date?
    @State private var referenceDate = Date()
    @State private var midnightRefreshTask: Task<Void, Never>?

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        let snapshot = store.stats(referenceDate: referenceDate)
        let detailDate = selectedDay ?? snapshot.daySummaries.last?.date ?? snapshot.heatmapWindowEndDate

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardHero(snapshot: snapshot, balanceMinutes: store.balanceMinutes)
                HeatmapDashboardCard(
                    snapshot: snapshot,
                    selectedMetric: $selectedMetric,
                    selectedDay: $selectedDay,
                    detailDate: detailDate,
                    calendar: calendar
                )
                InsightsGrid(snapshot: snapshot)
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .frame(minWidth: 980, minHeight: 700)
        .background(StatsBackground())
        .onAppear {
            refreshSnapshot(at: Date())
            startMidnightRefreshTask()
        }
        .onDisappear {
            midnightRefreshTask?.cancel()
            midnightRefreshTask = nil
        }
        .onChange(of: store.state.events.count) { _ in
            syncSelection(with: store.stats(referenceDate: referenceDate))
        }
    }

    private func refreshSnapshot(at now: Date) {
        referenceDate = now
        syncSelection(with: store.stats(referenceDate: now))
    }

    private func syncSelection(with snapshot: FlexStatsSnapshot) {
        if
            let selectedDay,
            selectedDay >= snapshot.heatmapWindowStartDate,
            selectedDay <= snapshot.heatmapWindowEndDate
        {
            return
        }

        self.selectedDay = snapshot.daySummaries.last?.date ?? snapshot.heatmapWindowEndDate
    }

    private func startMidnightRefreshTask() {
        midnightRefreshTask?.cancel()
        midnightRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                let now = Date()
                let nextDayStart = nextStartOfDay(after: now)
                let delay = max(1, nextDayStart.timeIntervalSince(now))
                let nanoseconds = UInt64(delay * 1_000_000_000)

                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                refreshSnapshot(at: Date())
            }
        }
    }

    private func nextStartOfDay(after date: Date) -> Date {
        if let interval = calendar.dateInterval(of: .day, for: date) {
            return interval.end
        }

        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date.addingTimeInterval(24 * 60 * 60)
    }
}

private struct DashboardHero: View {
    let snapshot: FlexStatsSnapshot
    let balanceMinutes: Int

    private let calendar = Calendar.autoupdatingCurrent
    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    private var totalEventCount: Int {
        snapshot.daySummaries.reduce(0) { partialResult, summary in
            partialResult + summary.events.count
        }
    }

    private var trackedDayCount: Int {
        let components = calendar.dateComponents([.day], from: snapshot.heatmapWindowStartDate, to: snapshot.heatmapWindowEndDate)
        return (components.day ?? 364) + 1
    }

    private var trackedWeekCount: Int {
        max(1, trackedDayCount / 7)
    }

    private var coverageRate: Int {
        guard trackedDayCount > 0 else { return 0 }
        let ratio = Double(snapshot.daySummaries.count) / Double(trackedDayCount)
        return Int((ratio * 100).rounded())
    }

    private var windowRangeLabel: String {
        "\(formatMonthYear(snapshot.heatmapWindowStartDate)) - \(formatMonthYear(snapshot.heatmapWindowEndDate))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FlexBank Stats")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))

                    Text("Balance, streaks, and the days where time mysteriously evaporates.")
                        .font(.callout)
                        .foregroundStyle(StatsTheme.secondaryText)

                    HStack(spacing: 10) {
                        HeroInfoCard(
                            title: "Window",
                            value: windowRangeLabel,
                            detail: "\(trackedWeekCount) calendar weeks"
                        )
                        HeroInfoCard(
                            title: "Coverage",
                            value: "\(snapshot.daySummaries.count) logged day\(snapshot.daySummaries.count == 1 ? "" : "s")",
                            detail: "\(coverageRate)% of the tracked window"
                        )
                    }
                }

                Spacer(minLength: 24)

                BalanceHighlightCard(
                    balanceMinutes: balanceMinutes,
                    monthNetMinutes: snapshot.thisMonthNetMinutes,
                    monthLoggedDays: snapshot.thisMonthLoggedDays
                )
            }

            LazyVGrid(columns: metricColumns, spacing: 14) {
                MetricTile(
                    title: "Last 30 days",
                    value: formatSignedMinutes(snapshot.last30NetMinutes),
                    subtitle: "\(snapshot.last30ActiveDays) logged day\(snapshot.last30ActiveDays == 1 ? "" : "s")"
                )
                MetricTile(
                    title: "This month",
                    value: formatSignedMinutes(snapshot.thisMonthNetMinutes),
                    subtitle: "\(snapshot.thisMonthLoggedDays) active day\(snapshot.thisMonthLoggedDays == 1 ? "" : "s")"
                )
                MetricTile(
                    title: "Active streak",
                    value: "\(snapshot.currentQuickAddStreak)d",
                    subtitle: quickAddStreakSubtitle
                )
                MetricTile(
                    title: "History",
                    value: "\(totalEventCount)",
                    subtitle: "Total logged event\(totalEventCount == 1 ? "" : "s")"
                )
            }
        }
    }

    private var quickAddStreakSubtitle: String {
        if snapshot.currentQuickAddStreak > 0 {
            return "Best \(snapshot.bestQuickAddStreak)d"
        }

        return "Best \(snapshot.bestQuickAddStreak)d · paused"
    }
}

private struct HeroInfoCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(StatsTheme.secondaryText)

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(detail)
                .font(.caption)
                .foregroundStyle(StatsTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(StatsCardBackground(cornerRadius: 16))
    }
}

private struct HeatmapDashboardCard: View {
    let snapshot: FlexStatsSnapshot
    @Binding var selectedMetric: FlexHeatmapMetric
    @Binding var selectedDay: Date?
    let detailDate: Date
    let calendar: Calendar

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Activity Heatmap")
                                .font(.title3.weight(.semibold))
                            Text("Columns are weeks, rows are weekdays. Click a day to inspect the logged changes.")
                                .font(.callout)
                                .foregroundStyle(StatsTheme.secondaryText)
                        }

                        Spacer(minLength: 24)

                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(FlexHeatmapMetric.allCases) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 340)
                    }

                    HeatmapMetricSummary(
                        snapshot: snapshot,
                        metric: selectedMetric,
                        detailDate: detailDate,
                        calendar: calendar
                    )

                    HeatmapView(
                        snapshot: snapshot,
                        metric: selectedMetric,
                        selectedDay: $selectedDay,
                        calendar: calendar
                    )
                }

                HStack(alignment: .top, spacing: 18) {
                    DayInspectorCard(
                        date: detailDate,
                        summary: snapshot.summary(on: detailDate, calendar: calendar)
                    )
                    .frame(width: 320)

                    LoggedDaysCard(
                        snapshot: snapshot,
                        selectedDay: $selectedDay,
                        calendar: calendar
                    )
                }
            }
        }
    }
}

private struct InsightsGrid: View {
    let snapshot: FlexStatsSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 18) {
                WeekdayChartCard(
                    title: "Quick Adds By Weekday",
                    subtitle: "Where the routine tends to hold.",
                    emptyMessage: "Log a few quick adds and this chart will stop pretending to be modern art.",
                    data: snapshot.quickAddWeekdays,
                    color: eventAccentColor(for: .quickAdd)
                )

                WeekdayChartCard(
                    title: "Removed Time By Weekday",
                    subtitle: "The weekdays most likely to eat your balance.",
                    emptyMessage: "No removed time yet. A rare and beautiful moment.",
                    data: snapshot.removeWeekdays,
                    color: eventAccentColor(for: .manualRemove)
                )
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 18) {
                TypicalTimesCard(summaries: snapshot.typicalTimes)
                ActivityInsightsCard(snapshot: snapshot)
            }
            .frame(width: 320)
        }
    }
}

private struct StatsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                StatsTheme.backgroundTop,
                StatsTheme.backgroundBottom,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.14, green: 0.63, blue: 0.55).opacity(0.11))
                .frame(width: 320, height: 320)
                .blur(radius: 24)
                .offset(x: 120, y: -100)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color(red: 0.12, green: 0.46, blue: 0.82).opacity(0.09))
                .frame(width: 280, height: 280)
                .blur(radius: 28)
                .offset(x: -100, y: 120)
        }
        .ignoresSafeArea()
    }
}

private struct BalanceHighlightCard: View {
    let balanceMinutes: Int
    let monthNetMinutes: Int
    let monthLoggedDays: Int

    private var monthArrow: String {
        monthNetMinutes < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Current balance")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.84))

            Text(formatSignedMinutes(balanceMinutes))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Divider()
                .overlay(Color.white.opacity(0.16))

            HStack {
                Label("This month \(formatSignedMinutes(monthNetMinutes))", systemImage: monthArrow)
                Spacer()
                Text("\(monthLoggedDays) days")
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.84))
        }
        .padding(20)
        .frame(width: 290, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.20, blue: 0.32),
                            Color(red: 0.13, green: 0.36, blue: 0.53),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 12)
        )
    }
}

private struct HeroBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(StatsTheme.secondaryText)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(StatsTheme.badgeFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(StatsTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StatsTheme.secondaryText)

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(StatsTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(StatsCardBackground(cornerRadius: 18))
    }
}

private struct HeatmapMetricSummary: View {
    let snapshot: FlexStatsSnapshot
    let metric: FlexHeatmapMetric
    let detailDate: Date
    let calendar: Calendar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var peakDay: FlexDaySummary? {
        snapshot.daySummaries
            .filter { $0.value(for: metric) != 0 }
            .max { abs($0.value(for: metric)) < abs($1.value(for: metric)) }
    }

    private var selectedSummary: FlexDaySummary? {
        snapshot.summary(on: detailDate, calendar: calendar)
    }

    private var selectedValue: Int {
        selectedSummary?.value(for: metric) ?? 0
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ContextChip(
                title: "Metric",
                value: metric.title,
                detail: "Showing \(metricDescription)",
                tint: metricAccentColor(for: metric, value: selectedValue)
            )
            ContextChip(
                title: "Peak Day",
                value: peakDay.map { formatMetricValue($0.value(for: metric), metric: metric) } ?? "n/a",
                detail: peakDay.map { formatEventDate($0.date) } ?? "No activity logged yet",
                tint: metricAccentColor(for: metric, value: peakDay?.value(for: metric) ?? 0)
            )
            ContextChip(
                title: "Selected Day",
                value: formatEventDate(detailDate),
                detail: selectedSummary.map { "\(metric.title): \(formatMetricValue(selectedValue, metric: metric)) · \($0.events.count) event\($0.events.count == 1 ? "" : "s")" } ?? "No entries for this day",
                tint: calendar.isDateInToday(detailDate) ? StatsTheme.todayAccent : metricAccentColor(for: metric, value: selectedValue)
            )
        }
    }

    private var metricDescription: String {
        switch metric {
        case .net:
            "net change per day"
        case .quickAdd:
            "quick-add minutes"
        case .manualAdd:
            "manual additions"
        case .manualRemove:
            "removed minutes"
        }
    }
}

private struct ContextChip: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(StatsTheme.secondaryText)

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(detail)
                .font(.caption)
                .foregroundStyle(StatsTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

private struct DayInspectorCard: View {
    let date: Date
    let summary: FlexDaySummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Selected Day")
                    .font(.headline)
                Text(formatEventDate(date))
                    .font(.title3.weight(.semibold))
                Text(summarySummary)
                    .font(.callout)
                    .foregroundStyle(StatsTheme.secondaryText)
            }

            if let summary {
                HStack(spacing: 10) {
                    DayStatPill(
                        title: "Net",
                        value: formatSignedMinutes(summary.netMinutes),
                        tint: metricAccentColor(for: .net, value: summary.netMinutes)
                    )
                    DayStatPill(
                        title: "Events",
                        value: "\(summary.events.count)",
                        tint: Color(red: 0.12, green: 0.46, blue: 0.82)
                    )
                }

                VStack(spacing: 10) {
                    ForEach(summary.events) { event in
                        DayEventRow(event: event)
                    }
                }
            } else {
                EmptyStateCard(
                    title: "Nothing logged here",
                    message: "Pick a brighter square if you want the paper trail."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(StatsTheme.inspectorFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(StatsTheme.border, lineWidth: 1)
                )
        )
    }

    private var summarySummary: String {
        guard let summary else {
            return "No recorded changes for this day."
        }

        return "\(summary.events.count) event\(summary.events.count == 1 ? "" : "s") recorded"
    }
}

private struct DayStatPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(StatsTheme.secondaryText)
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

private struct LoggedDaysCard: View {
    let snapshot: FlexStatsSnapshot
    @Binding var selectedDay: Date?
    let calendar: Calendar

    private var loggedDays: [FlexDaySummary] {
        snapshot.daySummaries
            .filter { $0.activeEventCount > 0 }
            .sorted { $0.date > $1.date }
    }

    private var totalRemovedMinutes: Int {
        loggedDays.reduce(0) { partialResult, summary in
            partialResult + summary.removedMinutes
        }
    }

    private var totalGainedMinutes: Int {
        loggedDays.reduce(0) { partialResult, summary in
            partialResult + summary.addedMinutes + summary.quickAddMinutes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Logged Days")
                        .font(.headline)
                    Text("Recent days with quick adds, manual adds, and removed time.")
                        .font(.callout)
                        .foregroundStyle(StatsTheme.secondaryText)
                }
            }

            HStack(spacing: 10) {
                DayStatPill(
                    title: "Logged",
                    value: "\(loggedDays.count)",
                    tint: Color(red: 0.12, green: 0.46, blue: 0.82)
                )
                DayStatPill(
                    title: "Gained",
                    value: formatUnsignedMinutes(totalGainedMinutes),
                    tint: eventAccentColor(for: .manualAdd)
                )
                DayStatPill(
                    title: "Removed",
                    value: formatUnsignedMinutes(totalRemovedMinutes),
                    tint: eventAccentColor(for: .manualRemove)
                )
            }

            if loggedDays.isEmpty {
                EmptyStateCard(
                    title: "No logged days yet",
                    message: "Use Quick add, Add time, or Remove time from the menu to populate this view."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(loggedDays) { summary in
                            LoggedDayRow(
                                summary: summary,
                                isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: summary.date) } ?? false
                            ) {
                                selectedDay = summary.date
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 300)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(StatsTheme.inspectorFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(StatsTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct LoggedDayRow: View {
    let summary: FlexDaySummary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(formatEventDate(summary.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        ActivityMetricPill(
                            title: "Net",
                            value: formatSignedMinutes(summary.netMinutes),
                            tint: metricAccentColor(for: .net, value: summary.netMinutes)
                        )

                        if summary.quickAddMinutes > 0 {
                            ActivityMetricPill(
                                title: "Quick",
                                value: formatUnsignedMinutes(summary.quickAddMinutes),
                                tint: eventAccentColor(for: .quickAdd)
                            )
                        }

                        if summary.addedMinutes > 0 {
                            ActivityMetricPill(
                                title: "Added",
                                value: formatUnsignedMinutes(summary.addedMinutes),
                                tint: eventAccentColor(for: .manualAdd)
                            )
                        }

                        if summary.removedMinutes > 0 {
                            ActivityMetricPill(
                                title: "Removed",
                                value: formatUnsignedMinutes(summary.removedMinutes),
                                tint: eventAccentColor(for: .manualRemove)
                            )
                        }
                    }
                }

                Spacer(minLength: 12)

                Text("\(summary.events.count)")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(StatsTheme.secondaryText)
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(12)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .help("\(formatEventDate(summary.date)): net \(formatSignedMinutes(summary.netMinutes)), removed \(formatUnsignedMinutes(summary.removedMinutes))")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isSelected ? StatsTheme.todayAccent.opacity(0.13) : StatsTheme.subtleFill)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? StatsTheme.todayAccent.opacity(0.55) : Color.clear, lineWidth: 1)
            )
    }
}

private struct ActivityMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        Text("\(title) \(value)")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct DayEventRow: View {
    let event: FlexEvent

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(eventAccentColor(for: event.kind))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(label(for: event))
                    .font(.subheadline.weight(.semibold))
                Text(formatEventTime(event.occurredAt))
                    .font(.caption)
                    .foregroundStyle(StatsTheme.secondaryText)
            }

            Spacer()

            Text(formatSignedMinutes(event.deltaMinutes))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(eventAccentColor(for: event.kind))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(eventAccentColor(for: event.kind).opacity(0.12))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(StatsTheme.subtleFill)
        )
    }
}

private struct WeekdayChartCard: View {
    let title: String
    let subtitle: String
    let emptyMessage: String
    let data: [FlexWeekdayCount]
    let color: Color

    private var totalCount: Int {
        data.reduce(0) { partialResult, item in
            partialResult + item.count
        }
    }

    private var peakDay: FlexWeekdayCount? {
        data.max { $0.count < $1.count }
    }

    private var maxCount: Int {
        max(1, data.map(\.count).max() ?? 0)
    }

    var body: some View {
        StatsCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(StatsTheme.secondaryText)
                }

                Spacer()

                if let peakDay, peakDay.count > 0 {
                    HeroBadge(title: "Peak", value: "\(peakDay.label) · \(peakDay.count)")
                }
            }

            if totalCount == 0 {
                EmptyStateCard(
                    title: "Nothing to chart yet",
                    message: emptyMessage
                )
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Weekday", item.label),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(color.gradient)
                    .cornerRadius(6)
                }
                .frame(height: 190)
                .chartYScale(domain: 0...Double(maxCount + 1))
                .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(StatsTheme.secondaryText)
                        }
                    }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            .foregroundStyle(StatsTheme.gridLine)
                        AxisValueLabel()
                            .foregroundStyle(StatsTheme.secondaryText)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(StatsTheme.subtleFill)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                HStack {
                    Text("\(totalCount) total event\(totalCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(StatsTheme.secondaryText)

                    Spacer()

                    Text("Busiest: \(peakDay?.label ?? "n/a")")
                        .font(.caption)
                        .foregroundStyle(StatsTheme.secondaryText)
                }
            }
        }
    }
}

private struct TypicalTimesCard: View {
    let summaries: [FlexTimeOfDaySummary]

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Typical Log Times")
                    .font(.headline)

                Text("These are medians, not biometric surveillance. We are still just reading button clicks like civilized people.")
                    .font(.callout)
                    .foregroundStyle(StatsTheme.secondaryText)
            }

            VStack(spacing: 12) {
                ForEach(summaries) { summary in
                    TypicalTimeRow(summary: summary)
                }
            }
        }
    }
}

private struct TypicalTimeRow: View {
    let summary: FlexTimeOfDaySummary

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(eventAccentColor(for: summary.kind))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.label)
                    .font(.subheadline.weight(.semibold))
                Text(sampleText)
                    .font(.caption)
                    .foregroundStyle(StatsTheme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatTypicalTime(summary.typicalMinutesFromMidnight))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(eventAccentColor(for: summary.kind))

                if summary.typicalMinutesFromMidnight == nil {
                    Text("Need \(max(0, FlexStatsEngine.minimumInsightSamples - summary.sampleCount)) more")
                        .font(.caption)
                        .foregroundStyle(StatsTheme.secondaryText)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(StatsTheme.subtleFill)
        )
    }

    private var sampleText: String {
        "\(summary.sampleCount) sample\(summary.sampleCount == 1 ? "" : "s")"
    }
}

private struct ActivityInsightsCard: View {
    let snapshot: FlexStatsSnapshot

    private var averageNetMinutes: Int? {
        guard !snapshot.daySummaries.isEmpty else { return nil }
        let total = snapshot.daySummaries.reduce(0) { partialResult, summary in
            partialResult + summary.netMinutes
        }
        return total / snapshot.daySummaries.count
    }

    private var biggestGainDay: FlexDaySummary? {
        let best = snapshot.daySummaries.max { $0.netMinutes < $1.netMinutes }
        guard let best, best.netMinutes > 0 else { return nil }
        return best
    }

    private var roughestDay: FlexDaySummary? {
        let worst = snapshot.daySummaries.min { $0.netMinutes < $1.netMinutes }
        guard let worst, worst.netMinutes < 0 else { return nil }
        return worst
    }

    private var multiEditDays: Int {
        snapshot.daySummaries.filter { $0.events.count > 1 }.count
    }

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Patterns At A Glance")
                    .font(.headline)

                Text("A few quick reads so you do not need to squint at the whole dashboard every time.")
                    .font(.callout)
                    .foregroundStyle(StatsTheme.secondaryText)
            }

            VStack(spacing: 10) {
                InsightRow(
                    title: "Average logged day",
                    value: averageNetMinutes.map(formatSignedMinutes) ?? "n/a",
                    detail: snapshot.daySummaries.isEmpty ? "Need more history" : "Across \(snapshot.daySummaries.count) logged day\(snapshot.daySummaries.count == 1 ? "" : "s")",
                    tint: metricAccentColor(for: .net, value: averageNetMinutes ?? 0)
                )
                InsightRow(
                    title: "Biggest gain",
                    value: biggestGainDay.map { formatSignedMinutes($0.netMinutes) } ?? "n/a",
                    detail: biggestGainDay.map { formatEventDate($0.date) } ?? "No positive days yet",
                    tint: metricAccentColor(for: .net, value: biggestGainDay?.netMinutes ?? 0)
                )
                InsightRow(
                    title: "Sharpest drop",
                    value: roughestDay.map { formatSignedMinutes($0.netMinutes) } ?? "n/a",
                    detail: roughestDay.map { formatEventDate($0.date) } ?? "No negative days yet",
                    tint: metricAccentColor(for: .net, value: roughestDay?.netMinutes ?? 0)
                )
                InsightRow(
                    title: "Multi-edit days",
                    value: "\(multiEditDays)",
                    detail: "Days with more than one event",
                    tint: Color(red: 0.12, green: 0.46, blue: 0.82)
                )
            }
        }
    }
}

private struct InsightRow: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(StatsTheme.secondaryText)
            }

            Spacer()

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.12))
                )
                .foregroundStyle(tint == .secondary ? .primary : tint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(StatsTheme.subtleFill)
        )
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(StatsTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(StatsTheme.subtleFill)
        )
    }
}

private struct StatsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(StatsCardBackground(cornerRadius: 22))
    }
}

private struct StatsCardBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        StatsTheme.cardFill,
                        StatsTheme.cardFillElevated,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(StatsTheme.border, lineWidth: 1)
            )
            .shadow(color: StatsTheme.shadow, radius: 16, x: 0, y: 12)
    }
}

private struct HeatmapView: View {
    let snapshot: FlexStatsSnapshot
    let metric: FlexHeatmapMetric
    @Binding var selectedDay: Date?
    let calendar: Calendar

    private let cellSize: CGFloat = 16
    private let cellSpacing: CGFloat = 4
    private let axisSpacing: CGFloat = 10
    private let weekdayLabelWidth: CGFloat = 24
    private let headerHeight: CGFloat = 18

    var body: some View {
        let weeks = buildWeeks()
        let monthSections = buildMonthSections(from: weeks)
        let gridWidth = widthForWeekColumns(weeks.count)
        let today = calendar.startOfDay(for: Date())
        let maxMagnitude = max(
            1,
            weeks
                .flatMap(\.days)
                .compactMap { day in
                    guard day.isStatsWindowDate else { return nil }
                    return abs(day.summary?.value(for: metric) ?? 0)
                }
                .max() ?? 1
        )

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: axisSpacing) {
                        Color.clear.frame(width: weekdayLabelWidth)

                        HeatmapMonthLabelsView(
                            sections: monthSections,
                            width: gridWidth,
                            cellSize: cellSize,
                            cellSpacing: cellSpacing,
                            height: headerHeight
                        )
                    }

                    HStack(alignment: .top, spacing: axisSpacing) {
                        VStack(alignment: .trailing, spacing: cellSpacing) {
                            ForEach(Array(weekdayLabels().enumerated()), id: \.offset) { index, label in
                                Text(weekdayLabel(for: label, index: index))
                                    .font(.caption)
                                    .foregroundStyle(StatsTheme.secondaryText)
                                    .frame(width: weekdayLabelWidth, height: cellSize, alignment: .trailing)
                            }
                        }

                        HStack(alignment: .top, spacing: cellSpacing) {
                            ForEach(weeks) { week in
                                VStack(spacing: cellSpacing) {
                                    ForEach(week.days) { day in
                                        HeatmapCell(
                                            day: day,
                                            metric: metric,
                                            maxMagnitude: maxMagnitude,
                                            isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false,
                                            isToday: calendar.isDate(day.date, inSameDayAs: today)
                                        ) {
                                            selectedDay = day.date
                                        }
                                        .id(day.date)
                                    }
                                }
                                .overlay(alignment: .leading) {
                                    if week.startsMonth {
                                        Rectangle()
                                            .fill(StatsTheme.monthDivider)
                                            .frame(width: 1)
                                            .offset(x: -2.5)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 8)
            }
            .onAppear {
                scrollToFocusedDay(with: proxy)
            }
            .onChange(of: selectedDay) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollToFocusedDay(with: proxy)
                }
            }
        }
    }

    private func scrollToFocusedDay(with proxy: ScrollViewProxy) {
        let focusDay = calendar.startOfDay(for: selectedDay ?? snapshot.heatmapWindowEndDate)

        DispatchQueue.main.async {
            proxy.scrollTo(focusDay, anchor: .center)
        }
    }

    private func weekdayLabels() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let orderedWeekdays = (0..<7).map { offset in
            ((calendar.firstWeekday - 1 + offset) % 7)
        }
        return orderedWeekdays.map { symbols[$0] }
    }

    private func weekdayLabel(for label: String, index: Int) -> String {
        switch index {
        case 0, 2, 4, 6:
            return label
        default:
            return ""
        }
    }

    private func widthForWeekColumns(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return (CGFloat(count) * cellSize) + (CGFloat(count - 1) * cellSpacing)
    }

    private func buildMonthSections(from weeks: [HeatmapWeek]) -> [HeatmapMonthSection] {
        var sections: [HeatmapMonthSection] = []

        for week in weeks {
            guard let firstVisibleDate = week.firstVisibleDate else { continue }
            let month = calendar.component(.month, from: firstVisibleDate)
            let year = calendar.component(.year, from: firstVisibleDate)
            let isPartialLeadingMonth = calendar.component(.day, from: firstVisibleDate) != 1

            if let lastIndex = sections.indices.last,
               sections[lastIndex].month == month,
               sections[lastIndex].year == year {
                sections[lastIndex].weekCount += 1
            } else {
                sections.append(
                    HeatmapMonthSection(
                        startDate: week.startDate,
                        label: formatHeatmapMonthLabel(firstVisibleDate),
                        weekCount: 1,
                        month: month,
                        year: year,
                        isPartialLeadingMonth: isPartialLeadingMonth
                    )
                )
            }
        }

        return sections
    }

    private func buildWeeks() -> [HeatmapWeek] {
        var weeks: [HeatmapWeek] = []
        var cursor = snapshot.heatmapGridStartDate

        while cursor <= snapshot.heatmapGridEndDate {
            let weekDays = (0..<7).compactMap { offset -> HeatmapDay? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: cursor) else { return nil }
                let isStatsWindowDate = date >= snapshot.heatmapWindowStartDate && date <= snapshot.heatmapWindowEndDate
                let isVisibleCalendarDate = date >= snapshot.heatmapWindowStartDate && date <= snapshot.heatmapGridEndDate
                return HeatmapDay(
                    date: date,
                    summary: snapshot.summary(on: date, calendar: calendar),
                    isStatsWindowDate: isStatsWindowDate,
                    isVisibleCalendarDate: isVisibleCalendarDate,
                    isFutureDate: date > snapshot.heatmapWindowEndDate
                )
            }

            let firstVisibleDate = weekDays.first(where: { $0.isVisibleCalendarDate })?.date
            let monthStartDate = weekDays.first { day in
                guard day.isVisibleCalendarDate,
                      let monthInterval = calendar.dateInterval(of: .month, for: day.date)
                else {
                    return false
                }

                return calendar.isDate(day.date, inSameDayAs: monthInterval.start)
            }?.date

            let startsMonth = monthStartDate != nil
            let labelAnchorDate = monthStartDate ?? (weeks.isEmpty ? firstVisibleDate : nil)
            let monthLabel = labelAnchorDate.map(formatHeatmapMonthLabel)

            weeks.append(
                HeatmapWeek(
                    startDate: cursor,
                    days: weekDays,
                    firstVisibleDate: firstVisibleDate,
                    startsMonth: startsMonth,
                    monthLabel: monthLabel
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }

        return weeks
    }
}

private struct HeatmapMonthLabelsView: View {
    let sections: [HeatmapMonthSection]
    let width: CGFloat
    let cellSize: CGFloat
    let cellSpacing: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: cellSpacing) {
            ForEach(sections) { section in
                Group {
                    if showsLabel(for: section) {
                        Text(section.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    } else {
                        Text(" ")
                            .hidden()
                    }
                }
                .frame(width: widthForWeekColumns(section.weekCount), alignment: .center)
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
    }

    private func showsLabel(for section: HeatmapMonthSection) -> Bool {
        !(section.isPartialLeadingMonth && section.weekCount < 2)
    }

    private func widthForWeekColumns(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return (CGFloat(count) * cellSize) + (CGFloat(count - 1) * cellSpacing)
    }
}

private struct HeatmapCell: View {
    let day: HeatmapDay
    let metric: FlexHeatmapMetric
    let maxMagnitude: Int
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(fillColor)
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(StatsTheme.selectedAccent, lineWidth: 2.4)
                            .frame(width: 22, height: 22)
                    }
                }
                .shadow(color: isSelected ? StatsTheme.selectedAccent.opacity(0.45) : .clear, radius: 5, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .disabled(!day.isVisibleCalendarDate)
        .help(tooltip)
    }

    private var fillColor: Color {
        guard day.isVisibleCalendarDate else {
            return Color.clear
        }

        if day.isFutureDate {
            return StatsTheme.futureDayFill
        }

        let value = day.summary?.value(for: metric) ?? 0
        return heatmapColor(value: value, metric: metric, maxMagnitude: maxMagnitude)
    }

    private var strokeColor: Color {
        if isSelected {
            return StatsTheme.selectedAccent
        }

        if isToday {
            return StatsTheme.todayAccent
        }

        if day.isFutureDate {
            return StatsTheme.futureDayBorder
        }

        return StatsTheme.border
    }

    private var strokeWidth: CGFloat {
        if isSelected {
            return 2.2
        }

        if isToday {
            return 1.4
        }

        return 1
    }

    private var opacity: Double {
        if !day.isVisibleCalendarDate {
            return 0.16
        }

        if day.isFutureDate {
            return 0.62
        }

        return 1
    }

    private var tooltip: String {
        let title = formatEventDate(day.date)
        let value = day.summary?.value(for: metric) ?? 0
        let todayLine = isToday ? "\nToday" : ""
        let futureLine = day.isFutureDate ? "\nFuture calendar day" : ""
        return "\(title)\n\(metric.title): \(formatMetricValue(value, metric: metric))\(todayLine)\(futureLine)"
    }
}

private enum StatsTheme {
    static let backgroundTop = Color(nsColor: .windowBackgroundColor)
    static let backgroundBottom = Color(nsColor: .underPageBackgroundColor)
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let cardFillElevated = Color(nsColor: .textBackgroundColor)
    static let inspectorFill = Color(nsColor: .windowBackgroundColor)
    static let badgeFill = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.78)
    static let subtleFill = Color(nsColor: .quaternaryLabelColor).opacity(0.14)
    static let gridLine = Color(nsColor: .separatorColor).opacity(0.55)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let todayAccent = Color(nsColor: .controlAccentColor)
    static let selectedAccent = Color(nsColor: .controlAccentColor)
    static let futureDayFill = Color(nsColor: .quaternaryLabelColor).opacity(0.26)
    static let futureDayBorder = Color(nsColor: .separatorColor).opacity(0.5)
    static let monthDivider = Color(nsColor: .separatorColor).opacity(0.62)
    static let shadow = Color.black.opacity(0.14)
}

private struct HeatmapWeek: Identifiable {
    let startDate: Date
    let days: [HeatmapDay]
    let firstVisibleDate: Date?
    let startsMonth: Bool
    let monthLabel: String?

    var id: Date { startDate }
}

private struct HeatmapMonthSection: Identifiable {
    let startDate: Date
    let label: String
    var weekCount: Int
    let month: Int
    let year: Int
    let isPartialLeadingMonth: Bool

    var id: Date { startDate }
}

private struct HeatmapDay: Identifiable {
    let date: Date
    let summary: FlexDaySummary?
    let isStatsWindowDate: Bool
    let isVisibleCalendarDate: Bool
    let isFutureDate: Bool

    var id: Date { date }
}

private func formatMetricValue(_ value: Int, metric: FlexHeatmapMetric) -> String {
    switch metric {
    case .net:
        return formatSignedMinutes(value)
    case .quickAdd, .manualAdd, .manualRemove:
        return formatUnsignedMinutes(value)
    }
}

private func formatMonthYear(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateFormat = "MMM yyyy"
    return formatter.string(from: date)
}

private func formatHeatmapMonthLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateFormat = "MMM"
    return formatter.string(from: date)
}

private func metricAccentColor(for metric: FlexHeatmapMetric, value: Int) -> Color {
    switch metric {
    case .net:
        if value < 0 {
            return eventAccentColor(for: .manualRemove)
        }
        return Color(red: 0.12, green: 0.58, blue: 0.29)
    case .quickAdd:
        return eventAccentColor(for: .quickAdd)
    case .manualAdd:
        return eventAccentColor(for: .manualAdd)
    case .manualRemove:
        return eventAccentColor(for: .manualRemove)
    }
}
