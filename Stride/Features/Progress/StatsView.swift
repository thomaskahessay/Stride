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

                        // Training progress bar
                        trainingProgressCard

                        // Training stats list
                        trainingStatsCard

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

    // MARK: - Training Progress Card

    private var trainingProgressCard: some View {
        let completion = profile.activePlan?.completionPercentage ?? 0

        return GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Training Progress", systemImage: "chart.bar.fill")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.stride.lavender.opacity(0.2))
                            .frame(height: 12)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.stride.lavenderDeep)
                            .frame(width: geo.size.width * max(0, min(1, completion)), height: 12)
                    }
                }
                .frame(height: 12)

                Text("\(Int(completion * 100))% complete")
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)

                HStack(spacing: .strideMD) {
                    Label("\(daysToRace) days to race", systemImage: "flag.checkered.2.crossed")
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Label("\(String(format: "%.0f", profile.unitPreference.convert(unifiedTotalMiles))) \(profile.unitPreference.shortLabel) run", systemImage: "road.lanes")
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Training Stats Card

    private var trainingStatsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Label("Training Stats", systemImage: "list.bullet.clipboard")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)
                    .padding(.bottom, .strideSM)

                if let pace = formattedAvgPace {
                    statRow(icon: "gauge.open.with.lines.needle.33percent", label: "Avg Pace", value: pace, color: Color.stride.sky)
                    Divider().padding(.leading, 32)
                }

                statRow(icon: "trophy.fill", label: "Longest Run", value: longestRunFormatted, color: Color.stride.warmOrange)
                Divider().padding(.leading, 32)

                statRow(icon: "chart.line.uptrend.xyaxis", label: "Weekly Avg", value: weeklyAvgFormatted, color: Color.stride.lavenderDeep)
                Divider().padding(.leading, 32)

                statRow(icon: "checkmark.circle.fill", label: "Runs Logged", value: "\(runsLogged)", color: Color.stride.mint)

                if let racePace = estimatedRacePace {
                    Divider().padding(.leading, 32)
                    statRow(icon: "figure.run", label: "Est. Race Pace", value: racePace, color: Color.stride.violet)
                }
            }
        }
    }

    // MARK: - Stat Row Helper

    private func statRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: .strideSM) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)

            Text(label)
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.stride.lavenderDeep)
        }
        .padding(.vertical, .strideSM)
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

    // MARK: - Computed data

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

    /// Estimated race pace from the finish time projection, in user's preferred units.
    private var estimatedRacePace: String? {
        guard let projection = computedCumulativeProjection else { return nil }
        let raceDistance: Double = profile.unitPreference == .miles
            ? profile.raceType.distanceMiles
            : profile.raceType.distanceKm
        guard raceDistance > 0 else { return nil }
        let paceSeconds = Double(projection.projectedSeconds) / raceDistance
        let mins = Int(paceSeconds) / 60
        let secs = Int(paceSeconds) % 60
        return String(format: "%d:%02d /%@", mins, secs, profile.unitPreference.shortLabel)
    }

    /// Number of runs logged (plan + historical).
    private var runsLogged: Int {
        let planRuns = profile.activePlan?.workoutDays
            .filter { $0.workoutType.isRun && $0.log != nil }
            .count ?? 0
        return planRuns + historicalRuns.count
    }

    /// Weighted average pace across all logged runs, formatted for display.
    private var formattedAvgPace: String? {
        var totalPace = 0.0
        var count = 0

        // Historical runs
        for run in historicalRuns {
            totalPace += run.averagePaceSecondsPerMile
            count += 1
        }

        // Plan logged runs
        if let workoutDays = profile.activePlan?.workoutDays {
            for day in workoutDays where day.workoutType.isRun {
                if let log = day.log, log.actualDistanceMiles > 0, log.actualDurationSeconds > 0 {
                    let pace = Double(log.actualDurationSeconds) / log.actualDistanceMiles
                    totalPace += pace
                    count += 1
                }
            }
        }

        guard count > 0 else { return nil }
        let avgPaceMi = totalPace / Double(count)
        let paceSeconds = profile.unitPreference == .miles ? avgPaceMi : avgPaceMi / 1.60934
        let mins = Int(paceSeconds) / 60
        let secs = Int(paceSeconds) % 60
        return String(format: "%d:%02d /%@", mins, secs, profile.unitPreference.shortLabel)
    }

    /// Longest run across historical + plan logged runs, in user's preferred units.
    private var longestRunFormatted: String {
        let historicalMax = historicalRuns.max(by: { $0.distanceMiles < $1.distanceMiles })?.distanceMiles ?? 0
        let planMax = profile.activePlan?.workoutDays
            .compactMap { $0.log?.actualDistanceMiles }
            .max() ?? 0
        let longestMiles = max(historicalMax, planMax)
        return String(format: "%.1f %@", profile.unitPreference.convert(longestMiles), profile.unitPreference.shortLabel)
    }

    /// Weekly average distance in user's preferred units.
    private var weeklyAvgFormatted: String {
        // Try historical-based calculation first
        let runs = historicalRuns
        if !runs.isEmpty, let earliest = runs.first?.date, let latest = runs.last?.date {
            let totalMiles = runs.reduce(0) { $0 + $1.distanceMiles }
            let cal = Calendar.current
            let weeksSpanned = max(1, (cal.dateComponents([.weekOfYear], from: earliest, to: latest).weekOfYear ?? 0) + 1)
            let avgWeekly = totalMiles / Double(weeksSpanned)
            return String(format: "%.1f %@/wk", profile.unitPreference.convert(avgWeekly), profile.unitPreference.shortLabel)
        }

        // Fallback: plan logged runs
        let planMiles = profile.activePlan?.workoutDays
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +) ?? 0
        if planMiles > 0, let plan = profile.activePlan {
            let totalDays = plan.workoutDays.count
            let weeks = max(1, totalDays / 7)
            let avg = planMiles / Double(weeks)
            return String(format: "%.1f %@/wk", profile.unitPreference.convert(avg), profile.unitPreference.shortLabel)
        }

        return "—"
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
