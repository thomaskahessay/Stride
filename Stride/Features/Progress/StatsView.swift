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

                if let projection = computedCumulativeProjection {
                    // Main projected time
                    HStack(alignment: .firstTextBaseline, spacing: .strideXS) {
                        Text(estimator.formatted(seconds: projection.projectedSeconds))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.stride.lavenderDeep)

                        Text(profile.raceType.displayName)
                            .font(Font.stride.headingSmall)
                            .foregroundStyle(.secondary)
                    }

                    // Range (optimistic — pessimistic)
                    if projection.optimisticSeconds != projection.pessimisticSeconds {
                        Text("\(estimator.formatted(seconds: projection.optimisticSeconds)) – \(estimator.formatted(seconds: projection.pessimisticSeconds))")
                            .font(Font.stride.bodyMedium)
                            .foregroundStyle(.secondary)
                    }

                    // Confidence badge + run count
                    HStack(spacing: .strideSM) {
                        confidenceBadge(projection.confidence)

                        Text("Based on \(projection.qualifyingRunCount) qualifying run\(projection.qualifyingRunCount == 1 ? "" : "s")")
                            .font(Font.stride.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Trend chart
                    if projection.weeklyTrend.count >= 2 {
                        ProjectionTrendChart(
                            trend: projection.weeklyTrend,
                            formatter: { estimator.formatted(seconds: $0) }
                        )
                        .padding(.top, .strideXS)
                    }

                    Button(profile.recentRaceTime != nil ? "Update Time Trial" : "Add a Race Time for Better Accuracy") {
                        showAddTimeTrial = true
                    }
                    .font(Font.stride.caption.weight(.semibold))
                    .foregroundStyle(Color.stride.lavenderDeep)
                } else {
                    Text("Not enough run data yet.")
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)

                    Text("Log a few runs or add a race time to see your projected finish.")
                        .font(Font.stride.caption)
                        .foregroundStyle(.tertiary)

                    Button("Add a Recent Race Time") { showAddTimeTrial = true }
                        .buttonStyle(StrideSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Confidence Badge

    private func confidenceBadge(_ confidence: ProjectionConfidence) -> some View {
        Text(confidence.rawValue)
            .font(Font.stride.label)
            .padding(.horizontal, .strideSM)
            .padding(.vertical, .strideXS)
            .background(Capsule().fill(confidenceColor(confidence).opacity(0.15)))
            .foregroundStyle(confidenceColor(confidence))
    }

    private func confidenceColor(_ confidence: ProjectionConfidence) -> Color {
        switch confidence {
        case .early:    return Color.stride.warmOrange
        case .building: return Color.stride.sky
        case .strong:   return Color.stride.mint
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
                let maxMiles = weeks.map { max($0.miles, $0.targetMiles) }.max() ?? 1
                let chartHeight: CGFloat = 100

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(weeks) { week in
                        VStack(spacing: 2) {
                            ZStack(alignment: .bottom) {
                                // Actual mileage bar with label on top
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(barColor(for: week))
                                    .frame(
                                        height: max(4, chartHeight * CGFloat(week.miles) / CGFloat(maxMiles))
                                    )
                                    .overlay(alignment: .top) {
                                        if week.miles > 0 {
                                            Text(String(format: "%.0f", profile.unitPreference.convert(week.miles)))
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(Color.stride.lavenderDeep)
                                                .offset(y: -12)
                                        }
                                    }

                                // Target mileage dashed line marker
                                if week.targetMiles > 0 {
                                    let targetHeight = chartHeight * CGFloat(week.targetMiles) / CGFloat(maxMiles)
                                    VStack(spacing: 0) {
                                        Rectangle()
                                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                            .foregroundStyle(Color.stride.lavenderDeep.opacity(0.6))
                                            .frame(height: 1.5)

                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: targetHeight)
                                }
                            }

                            Text(week.label)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 130)

                HStack(spacing: .strideMD) {
                    let weekCount = weeks.count
                    Text("\(weekCount) weeks · \(profile.unitPreference.shortLabel)")
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Legend for target line
                    HStack(spacing: 4) {
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Color.stride.lavenderDeep.opacity(0.6))
                            .frame(width: 16, height: 1.5)
                        Text("Plan target")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
        let targetMiles: Double
        let isCurrent: Bool
        let source: WeekSource
    }

    /// Merges historical run data with plan workout data into one unified timeline.
    /// Shows up to 12 weeks of history before the plan, plus all plan weeks.
    private var unifiedWeeklyMileage: [WeekData] {
        let cal = Calendar.current
        let today = DateProvider.shared.now
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

        // Build plan week buckets (actual logged miles + target miles)
        // Uses effectiveDate so moved/rescheduled workouts land in the correct week.
        // Only counts workouts from planStartDate onward for target mileage.
        var planBuckets: [Date: Double] = [:]
        var planTargetBuckets: [Date: Double] = [:]
        if let plan = profile.activePlan {
            let planCreated = cal.startOfDay(for: plan.generatedAt)
            for workout in plan.workoutDays {
                let effectiveWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.effectiveDate)) ?? workout.effectiveDate
                // Only include target mileage for workouts on or after the plan was generated
                if workout.effectiveDate >= planCreated {
                    planTargetBuckets[effectiveWeekStart, default: 0] += workout.targetDistanceMiles
                }
                guard let log = workout.log else { continue }
                planBuckets[effectiveWeekStart, default: 0] += log.actualDistanceMiles
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
            let target = isHistorical ? 0 : (planTargetBuckets[weekStart] ?? 0)

            return WeekData(
                id: index,
                label: label,
                miles: miles,
                targetMiles: target,
                isCurrent: isCurrent,
                source: isHistorical ? .historical : .plan
            )
        }
    }

    /// Cumulative projection blending all training data + optional manual race time.
    private var computedCumulativeProjection: CumulativeProjection? {
        let planRuns: [QualifyingRun]
        if let workoutDays = profile.activePlan?.workoutDays {
            planRuns = FinishTimeEstimator.qualifyingRuns(from: workoutDays)
        } else {
            planRuns = []
        }
        let histRuns = FinishTimeEstimator.qualifyingRuns(from: historicalRuns)

        return estimator.cumulativeProjection(
            planLogs: planRuns,
            historicalRuns: histRuns,
            manualRaceTime: profile.recentRaceTime,
            targetRace: profile.raceType
        )
    }

    private var daysToRace: Int {
        let today = Calendar.current.startOfDay(for: DateProvider.shared.now)
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

// MARK: - Projection Trend Chart

/// A small sparkline showing how the projected finish time has changed week over week.
private struct ProjectionTrendChart: View {
    let trend: [WeeklyProjection]
    let formatter: (Int) -> String

    private let chartHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: .strideXS) {
            Text("Projection Trend")
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let width = geo.size.width
                let points = chartPoints(in: CGSize(width: width, height: chartHeight))

                ZStack(alignment: .topLeading) {
                    // Gradient fill below the line
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: CGPoint(x: first.x, y: chartHeight))
                        path.addLine(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        if let last = points.last {
                            path.addLine(to: CGPoint(x: last.x, y: chartHeight))
                        }
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.stride.lavender.opacity(0.3), Color.stride.lavender.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(Color.stride.lavenderDeep, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Data point dots
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(Color.stride.lavenderDeep)
                            .frame(width: 6, height: 6)
                            .position(point)
                    }

                    // Latest value label
                    if let last = points.last, let lastTrend = trend.last {
                        Text(formatter(lastTrend.projectedSeconds))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.stride.lavenderDeep)
                            .position(x: last.x, y: max(12, last.y - 14))
                    }
                }
            }
            .frame(height: chartHeight)

            // X-axis labels (first and last week)
            if let first = trend.first, let last = trend.last, trend.count >= 2 {
                HStack {
                    Text(first.weekStart.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(last.weekStart.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Map trend data to CGPoints within the given size.
    /// Y-axis is inverted: lower seconds (faster) = higher on chart.
    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard trend.count >= 2 else {
            if let single = trend.first {
                return [CGPoint(x: size.width / 2, y: size.height / 2)]
            }
            return []
        }

        let seconds = trend.map { $0.projectedSeconds }
        let minSec = Double(seconds.min() ?? 0)
        let maxSec = Double(seconds.max() ?? 1)
        let range = max(1, maxSec - minSec)
        let padding = range * 0.1  // 10% vertical padding

        return trend.enumerated().map { index, week in
            let x = size.width * CGFloat(index) / CGFloat(trend.count - 1)
            // Invert Y so faster (lower seconds) is higher
            let normalised = (Double(week.projectedSeconds) - (minSec - padding)) / (range + 2 * padding)
            let y = size.height * CGFloat(normalised)
            return CGPoint(x: x, y: y)
        }
    }
}
