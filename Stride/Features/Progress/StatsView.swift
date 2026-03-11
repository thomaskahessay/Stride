import SwiftUI
import SwiftData

// NOTE: This is named StatsView intentionally — ProgressView conflicts with SwiftUI's built-in.
struct StatsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HistoricalRun.startDate, order: .forward) private var historicalRuns: [HistoricalRun]

    @State private var showAddTimeTrial = false

    private let estimator = FinishTimeEstimator()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {

                        // Projected finish time — top, full width
                        finishTimeCard

                        // Plan completion + race countdown + total miles row
                        HStack(spacing: .strideMD) {
                            overviewStat(
                                label: "Plan Complete",
                                value: "\(Int((profile.activePlan?.completionPercentage ?? 0) * 100))%",
                                icon: "checkmark.seal.fill",
                                color: Color.stride.lavender
                            )
                            overviewStat(
                                label: "Days to Race",
                                value: "\(daysToRace)",
                                icon: "flag.checkered.2.crossed",
                                color: Color.stride.sage
                            )
                            overviewStat(
                                label: "Total \(profile.unitPreference.shortLabel.capitalized)",
                                value: String(format: "%.0f", profile.unitPreference.convert(unifiedTotalMiles)),
                                icon: "road.lanes",
                                color: Color.stride.mint,
                                subtitle: totalMilesSubtitle
                            )
                        }

                        // Running history card (only if historical data exists)
                        if let summary = historicalSummary {
                            runningHistoryCard(summary)
                        }

                        // Unified weekly mileage chart
                        weeklyMileageChart

                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showAddTimeTrial) {
            AddTimeTrialView(profile: profile)
        }
    }

    // MARK: - Overview stat pill

    private func overviewStat(
        label: String,
        value: String,
        icon: String,
        color: Color,
        subtitle: String? = nil
    ) -> some View {
        GlassCard(cornerRadius: .strideRadiusMD, padding: .strideSM) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(label)
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Finish Time Card

    private var finishTimeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Projected Finish Time", systemImage: "stopwatch.fill")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)

                if let projection = resolvedProjection {
                    HStack(alignment: .firstTextBaseline, spacing: .strideXS) {
                        Text(estimator.formatted(seconds: projection.seconds))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.stride.lavenderDeep)

                        Text(profile.raceType.displayName)
                            .font(Font.stride.headingSmall)
                            .foregroundStyle(.secondary)
                    }

                    Text(projection.sourceLabel)
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)

                    Text(projection.caveat)
                        .font(Font.stride.caption)
                        .foregroundStyle(.tertiary)
                        .italic()

                    Button(profile.recentRaceTime != nil ? "Update Time Trial" : "Add a Race Time for Better Accuracy") {
                        showAddTimeTrial = true
                    }
                    .font(Font.stride.caption.weight(.semibold))
                    .foregroundStyle(Color.stride.lavenderDeep)
                } else {
                    Text("No time trial entered yet.")
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)

                    Button("Add a Recent Race Time") { showAddTimeTrial = true }
                        .buttonStyle(StrideSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Running History Card

    private func runningHistoryCard(_ summary: HistoricalSummary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideMD) {
                HStack {
                    Label("Your Running History", systemImage: "figure.run")
                        .font(Font.stride.headingSmall)
                        .foregroundStyle(Color.stride.lavenderDeep)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red.opacity(0.5))
                        Text("Apple Health")
                            .font(Font.stride.label)
                            .foregroundStyle(.tertiary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .strideSM) {
                    historyStat(
                        value: "\(summary.totalRuns)",
                        label: "Runs Imported",
                        icon: "checkmark.circle.fill",
                        color: Color.stride.mint
                    )
                    historyStat(
                        value: String(format: "%.1f", profile.unitPreference.convert(summary.avgWeeklyMiles)),
                        label: "\(profile.unitPreference.shortLabel)/week avg",
                        icon: "chart.line.uptrend.xyaxis",
                        color: Color.stride.lavenderDeep
                    )
                    historyStat(
                        value: String(format: "%.1f", profile.unitPreference.convert(summary.longestRunMiles)),
                        label: "Longest Run (\(profile.unitPreference.shortLabel))",
                        icon: "trophy.fill",
                        color: Color.stride.warmOrange
                    )
                    historyStat(
                        value: summary.formattedAvgPace(units: profile.unitPreference),
                        label: "Avg Pace",
                        icon: "gauge.open.with.lines.needle.33percent",
                        color: Color.stride.sky
                    )
                }
            }
        }
    }

    private func historyStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: .strideXS) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color.opacity(0.7))
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.stride.lavenderDeep)
            Text(label)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .strideSM)
        .background(
            RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                .fill(color.opacity(0.06))
        )
    }

    // MARK: - Weekly Mileage Chart

    private var weeklyMileageChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("Weekly Mileage")
                    .font(Font.stride.headingSmall)

                let weeks = unifiedWeeklyMileage
                let maxMiles = weeks.map(\.miles).max() ?? 1

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(weeks) { week in
                        VStack(spacing: 4) {
                            if week.miles > 0 {
                                Text(String(format: "%.0f", profile.unitPreference.convert(week.miles)))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.stride.lavenderDeep)
                            }

                            RoundedRectangle(cornerRadius: 4)
                                .fill(barColor(for: week))
                                .frame(
                                    height: max(4, 100 * CGFloat(week.miles) / CGFloat(maxMiles))
                                )

                            Text(week.label)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 130)

                let weekCount = weeks.count
                Text("\(weekCount) weeks · \(profile.unitPreference.shortLabel)")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func barColor(for week: WeekData) -> Color {
        if week.isCurrent {
            return Color.stride.lavender
        } else if week.source == .historical {
            return Color.stride.lavenderLight.opacity(0.5)
        } else {
            return Color.stride.lavenderLight
        }
    }

    // MARK: - Computed data

    private enum WeekSource {
        case historical
        case plan
    }

    private struct WeekData: Identifiable {
        let id: Int
        let label: String
        let miles: Double
        let isCurrent: Bool
        let source: WeekSource
    }

    /// Merges historical run data with plan workout data into one unified timeline.
    /// Shows up to 12 weeks of history before the plan, plus all plan weeks.
    private var unifiedWeeklyMileage: [WeekData] {
        let cal = Calendar.current
        let today = Date()
        let currentWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today

        // Determine plan start week (if plan exists)
        let planStartDate = profile.activePlan?.planStartDate
        let planWeekStart: Date? = if let psd = planStartDate {
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: psd))
        } else {
            nil
        }

        // Build historical week buckets (keyed by week start date)
        var historicalBuckets: [Date: Double] = [:]
        for run in historicalRuns {
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: run.date)) ?? run.date
            // Only include weeks before the plan started (or all if no plan)
            if let pws = planWeekStart, weekStart >= pws { continue }
            historicalBuckets[weekStart, default: 0] += run.distanceMiles
        }

        // Build plan week buckets
        var planBuckets: [Date: Double] = [:]
        if let plan = profile.activePlan {
            for workout in plan.workoutDays {
                guard let log = workout.log else { continue }
                let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)) ?? workout.date
                planBuckets[weekStart, default: 0] += log.actualDistanceMiles
            }
        }

        // Determine the earliest week to show (up to 12 weeks before current week)
        let maxHistoryWeeks = 12
        let earliestAllowed = cal.date(byAdding: .weekOfYear, value: -maxHistoryWeeks, to: currentWeekStart) ?? currentWeekStart

        // Collect all week start dates in range
        var allWeekStarts = Set<Date>()

        // Add historical weeks (capped)
        for weekStart in historicalBuckets.keys where weekStart >= earliestAllowed {
            allWeekStarts.insert(weekStart)
        }

        // Add plan weeks up to current week
        for weekStart in planBuckets.keys where weekStart <= currentWeekStart {
            allWeekStarts.insert(weekStart)
        }

        // Ensure current week is always included
        allWeekStarts.insert(currentWeekStart)

        // Fill in any gap weeks between earliest data and current week
        let sortedWeeks = allWeekStarts.sorted()
        if let earliest = sortedWeeks.first {
            var cursor = earliest
            while cursor <= currentWeekStart {
                allWeekStarts.insert(cursor)
                cursor = cal.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? currentWeekStart
            }
        }

        // Build final array
        let finalWeeks = allWeekStarts.sorted()
        return finalWeeks.enumerated().map { index, weekStart in
            let isHistorical = planWeekStart.map { weekStart < $0 } ?? true
            let miles: Double
            if isHistorical {
                miles = historicalBuckets[weekStart] ?? 0
            } else {
                miles = planBuckets[weekStart] ?? 0
            }

            let label = weekStart.formatted(.dateTime.month(.abbreviated).day())
            let isCurrent = weekStart == currentWeekStart

            return WeekData(
                id: index,
                label: label,
                miles: miles,
                isCurrent: isCurrent,
                source: isHistorical ? .historical : .plan
            )
        }
    }

    /// Resolved projection with source label and caveat text.
    private struct ResolvedProjection {
        let seconds: Int
        let sourceLabel: String
        let caveat: String
    }

    /// Tiered projection:
    /// 1. User-entered time trial (most accurate)
    /// 2. Race-distance match from HealthKit (accurate)
    /// 3. Longest run fallback (rough estimate)
    private var resolvedProjection: ResolvedProjection? {
        let targetRace = profile.raceType

        // Tier 1: User-entered time trial
        if let manual = profile.recentRaceTime,
           let projected = estimator.projectedTime(from: manual, for: targetRace) {
            return ResolvedProjection(
                seconds: projected,
                sourceLabel: estimator.sourceLabel(for: manual),
                caveat: "This estimate improves as you train."
            )
        }

        // Tier 2 & 3: Historical data
        guard let estimate = estimator.bestHistoricalEstimate(from: historicalRuns) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        switch estimate {
        case .raceMatch(let raceTime):
            guard let projected = estimator.projectedTime(from: raceTime, for: targetRace) else { return nil }
            return ResolvedProjection(
                seconds: projected,
                sourceLabel: "Based on your \(raceTime.raceDistance.displayName) on \(formatter.string(from: raceTime.raceDate)) (from Apple Health)",
                caveat: "This estimate improves as you train."
            )

        case .longestRun(let distanceMiles, let durationSeconds, let date):
            guard let projected = estimator.projectedTime(
                fromDistanceMiles: distanceMiles,
                durationSeconds: durationSeconds,
                for: targetRace
            ) else { return nil }
            let distLabel = String(format: "%.1f mi", distanceMiles)
            return ResolvedProjection(
                seconds: projected,
                sourceLabel: "Based on your \(distLabel) run on \(formatter.string(from: date)) (from Apple Health)",
                caveat: "Rough estimate from your longest run — add a race time for better accuracy."
            )
        }
    }

    private var daysToRace: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let components = Calendar.current.dateComponents([.day], from: today, to: profile.raceDate)
        return max(0, components.day ?? 0)
    }

    /// Unified total: historical miles + plan logged miles.
    private var unifiedTotalMiles: Double {
        let historicalMiles = historicalRuns.reduce(0) { $0 + $1.distanceMiles }
        let planMiles = profile.activePlan?.workoutDays
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +) ?? 0
        return historicalMiles + planMiles
    }

    /// Subtitle for the total miles stat showing the date range.
    private var totalMilesSubtitle: String? {
        guard let earliest = historicalRuns.first?.date else { return nil }
        return "since \(earliest.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Summary of historical runs for the history card.
    private var historicalSummary: HistoricalSummary? {
        let runs = historicalRuns
        guard !runs.isEmpty else { return nil }

        let totalMiles = runs.reduce(0) { $0 + $1.distanceMiles }
        let longestRun = runs.max(by: { $0.distanceMiles < $1.distanceMiles })
        let totalPaceSum = runs.reduce(0.0) { $0 + $1.averagePaceSecondsPerMile }
        let avgPace = totalPaceSum / Double(runs.count)

        let cal = Calendar.current
        guard let earliest = runs.first?.date, let latest = runs.last?.date else { return nil }
        let weeksSpanned = max(1, (cal.dateComponents([.weekOfYear], from: earliest, to: latest).weekOfYear ?? 0) + 1)
        let avgWeeklyMiles = totalMiles / Double(weeksSpanned)

        return HistoricalSummary(
            totalRuns: runs.count,
            totalMiles: totalMiles,
            avgWeeklyMiles: avgWeeklyMiles,
            avgPaceSecondsPerMile: avgPace,
            longestRunMiles: longestRun?.distanceMiles ?? 0,
            longestRunDate: longestRun?.date,
            earliestDate: earliest
        )
    }
}

// MARK: - Add Time Trial Sheet

struct AddTimeTrialView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var raceType: RaceType = .fiveK
    @State private var hours: Int = 0
    @State private var minutes: Int = 28
    @State private var seconds: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                VStack(spacing: .strideMD) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: .strideSM) {
                            Text("Race Distance")
                                .font(Font.stride.headingSmall)

                            Picker("Race", selection: $raceType) {
                                ForEach(RaceType.allCases, id: \.self) { race in
                                    Text(race.shortDisplayName).tag(race)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: .strideSM) {
                            Text("Finish Time")
                                .font(Font.stride.headingSmall)

                            HStack(spacing: 0) {
                                timePicker(label: "h", binding: $hours, range: 0...8)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                timePicker(label: "m", binding: $minutes, range: 0...59)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                timePicker(label: "s", binding: $seconds, range: 0...59)
                            }
                        }
                    }

                    Spacer()

                    Button("Save Time Trial") { save() }
                        .buttonStyle(StridePrimaryButtonStyle())
                        .padding(.horizontal, .strideMD)
                }
                .padding(.strideMD)
            }
            .navigationTitle("Add Race Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    private func save() {
        profile.recentRaceTime = RaceTime(
            raceDistance: raceType,
            finishTimeSeconds: hours * 3600 + minutes * 60 + seconds,
            raceDate: Date()
        )
        try? modelContext.save()
        dismiss()
    }

    private func timePicker(label: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            Picker("", selection: binding) {
                ForEach(range, id: \.self) { v in Text(String(format: "%02d", v)).tag(v) }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 80)
            .clipped()
            Text(label).font(Font.stride.caption).foregroundStyle(.secondary)
        }
    }
}
