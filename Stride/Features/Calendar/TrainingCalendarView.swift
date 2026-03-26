import SwiftUI
import SwiftData

struct TrainingCalendarView: View {
    let profile: UserProfile

    @Query(sort: \HistoricalRun.date) private var historicalRuns: [HistoricalRun]

    @State private var displayedMonth: Date = Date()
    @State private var selectedDay: WorkoutDay? = nil
    @State private var selectedHistoricalRun: HistoricalRun? = nil
    @State private var showWorkoutDetail = false
    @State private var showHistoricalRunDetail = false

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {
                        monthHeader

                        GlassCard(padding: .strideSM) {
                            VStack(spacing: .strideXS) {
                                // Day-of-week headers
                                HStack {
                                    ForEach(Array(["S","M","T","W","T","F","S"].enumerated()), id: \.offset) { _, d in
                                        Text(d)
                                            .font(Font.stride.label)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(.bottom, .strideXS)

                                // Week rows
                                ForEach(weeksInMonth, id: \.self) { week in
                                    HStack(spacing: 2) {
                                        ForEach(week, id: \.self) { date in
                                            CalendarDayCell(
                                                date: date,
                                                workoutDay: plannedWorkout(for: date),
                                                historicalRun: historicalRun(for: date),
                                                isCurrentMonth: isSameMonth(date, as: displayedMonth)
                                            ) {
                                                if let day = plannedWorkout(for: date) {
                                                    selectedDay = day
                                                    showWorkoutDetail = true
                                                } else if let run = historicalRun(for: date) {
                                                    selectedHistoricalRun = run
                                                    showHistoricalRunDetail = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        weeklyMileageBars

                        if let todayCard = todayWorkoutDay {
                            todayWorkoutCard(todayCard)
                        }

                        thisWeekSummary

                        if !recentItems.isEmpty {
                            recentRunsSection
                        }
                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle("Training Calendar")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showWorkoutDetail) {
            if let day = selectedDay, let plan = profile.activePlan {
                let detailVM = WorkoutDetailViewModel(workout: day, plan: plan)
                WorkoutDetailView(viewModel: detailVM, units: profile.unitPreference)
            }
        }
        .sheet(isPresented: $showHistoricalRunDetail) {
            if let run = selectedHistoricalRun {
                HistoricalRunDetailSheet(run: run, units: profile.unitPreference)
            }
        }
        .onChange(of: showWorkoutDetail) { _, isShowing in
            if !isShowing { selectedDay = nil }
        }
        .onChange(of: showHistoricalRunDetail) { _, isShowing in
            if !isShowing { selectedHistoricalRun = nil }
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Button { shiftMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.stride.lavenderDeep)
                        .padding(.strideSM)
                }
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(Font.stride.headingMedium)
                Spacer()
                Button { shiftMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.stride.lavenderDeep)
                        .padding(.strideSM)
                }
            }

            let stats = monthStats
            if stats.totalDistance > 0 || stats.runCount > 0 {
                Text("\(stats.totalDistance.formattedDistance(unit: profile.unitPreference)) this month \u{2022} \(stats.runCount) runs")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Month Stats

    private var monthStats: (totalDistance: Double, runCount: Int) {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return (0, 0)
        }

        // Plan workout logs in this month
        let planWorkouts = (profile.activePlan?.workoutDays ?? [])
            .filter { $0.isCompleted && $0.effectiveDate >= monthInterval.start && $0.effectiveDate < monthInterval.end }
        let planDistance = planWorkouts.reduce(0.0) { $0 + ($1.log?.actualDistanceMiles ?? 0) }

        // Historical runs in this month
        let monthRuns = historicalRuns.filter { $0.date >= monthInterval.start && $0.date < monthInterval.end }
        let hkDistance = monthRuns.reduce(0.0) { $0 + $1.distanceMiles }

        return (planDistance + hkDistance, planWorkouts.count + monthRuns.count)
    }

    // MARK: - Weekly Mileage Bars

    private var weeklyMileageBars: some View {
        let weeks = weeklyMileageData
        let maxDistance = weeks.map(\.distance).max() ?? 1

        return GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("Weekly Mileage")
                    .font(Font.stride.headingSmall)

                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    HStack(spacing: .strideSM) {
                        Text("Week \(index + 1)")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)

                        GeometryReader { geo in
                            let fraction = maxDistance > 0 ? week.distance / maxDistance : 0
                            Capsule()
                                .fill(Color.stride.lavenderDeep)
                                .frame(width: max(4, geo.size.width * fraction))
                        }
                        .frame(height: 12)

                        Text(week.distance.formattedDistance(unit: profile.unitPreference))
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var weeklyMileageData: [(weekStart: Date, distance: Double)] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }

        // Collect ISO weeks that overlap this month
        var weekStarts: [Date] = []
        var current = monthInterval.start
        while current < monthInterval.end {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: current)?.start ?? current
            if !weekStarts.contains(where: { calendar.isDate($0, inSameDayAs: weekStart) }) {
                weekStarts.append(weekStart)
            }
            current = calendar.date(byAdding: .day, value: 7, to: current) ?? monthInterval.end
        }

        return weekStarts.map { weekStart in
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

            let planDist = (profile.activePlan?.workoutDays ?? [])
                .filter { $0.isCompleted && $0.effectiveDate >= weekStart && $0.effectiveDate < weekEnd }
                .reduce(0.0) { $0 + ($1.log?.actualDistanceMiles ?? 0) }

            let hkDist = historicalRuns
                .filter { $0.date >= weekStart && $0.date < weekEnd }
                .reduce(0.0) { $0 + $1.distanceMiles }

            return (weekStart, planDist + hkDist)
        }
    }

    // MARK: - Today's Workout Card

    private var todayWorkoutDay: WorkoutDay? {
        let now = DateProvider.shared.now
        return profile.activePlan?.workoutDays.first {
            calendar.isDate($0.effectiveDate, inSameDayAs: now) && $0.workoutType != .restDay
        }
    }

    private func todayWorkoutCard(_ day: WorkoutDay) -> some View {
        Button {
            selectedDay = day
            showWorkoutDetail = true
        } label: {
            GlassCard(padding: .strideSM) {
                HStack(spacing: .strideSM) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.workoutType.accentColor)
                        .frame(width: 4)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(DateProvider.shared.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)

                        Text(day.workoutType.rawValue)
                            .font(Font.stride.bodyMedium)

                        if day.isCompleted, let log = day.log, log.actualDistanceMiles > 0 {
                            Text(log.actualDistanceMiles.formattedDistance(unit: profile.unitPreference))
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        } else if !day.isCompleted {
                            let parts = [
                                day.targetDistanceMiles > 0 ? day.targetDistanceMiles.formattedDistance(unit: profile.unitPreference) : nil,
                                day.targetDurationMinutes > 0 ? "\(day.targetDurationMinutes):00" : nil
                            ].compactMap { $0 }
                            if !parts.isEmpty {
                                Text(parts.joined(separator: " \u{2022} "))
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if day.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.stride.mint)
                            .font(.system(size: 22))
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.stride.lavenderDeep)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - This Week Summary

    private var thisWeekSummary: some View {
        let stats = currentWeekStats
        return GlassCard {
            HStack(spacing: 0) {
                summaryItem(value: stats.distance.formattedDistance(unit: profile.unitPreference), label: "Distance")
                Divider().frame(height: 32)
                summaryItem(value: "\(stats.runCount)", label: "Runs")
                Divider().frame(height: 32)
                summaryItem(value: "\(stats.completed)/\(stats.planned)", label: "This Week")
            }
        }
    }

    private func summaryItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label)
                .font(Font.stride.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var currentWeekStats: (distance: Double, runCount: Int, completed: Int, planned: Int) {
        let now = DateProvider.shared.now
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return (0, 0, 0, 0)
        }

        let planWorkouts = (profile.activePlan?.workoutDays ?? [])
            .filter { $0.isCompleted && $0.effectiveDate >= weekInterval.start && $0.effectiveDate < weekInterval.end }
        let planDist = planWorkouts.reduce(0.0) { $0 + ($1.log?.actualDistanceMiles ?? 0) }

        let weekRuns = historicalRuns
            .filter { $0.date >= weekInterval.start && $0.date < weekInterval.end }
        let hkDist = weekRuns.reduce(0.0) { $0 + $1.distanceMiles }

        let allWeekWorkouts = (profile.activePlan?.workoutDays ?? [])
            .filter { $0.effectiveDate >= weekInterval.start && $0.effectiveDate < weekInterval.end && $0.workoutType != .restDay }
        let completed = allWeekWorkouts.filter { $0.isCompleted }.count

        return (planDist + hkDist, planWorkouts.count + weekRuns.count, completed, allWeekWorkouts.count)
    }

    // MARK: - Recent Runs Section

    private enum RecentItem: Identifiable {
        case planned(WorkoutDay)
        case historical(HistoricalRun)

        var id: String {
            switch self {
            case .planned(let day): return "plan-\(day.id)"
            case .historical(let run): return "hk-\(run.id)"
            }
        }

        var date: Date {
            switch self {
            case .planned(let day): return day.effectiveDate
            case .historical(let run): return run.date
            }
        }
    }

    private var recentItems: [RecentItem] {
        let now = DateProvider.shared.now

        let planItems: [RecentItem] = (profile.activePlan?.workoutDays ?? [])
            .filter { $0.isCompleted && $0.effectiveDate <= now }
            .map { .planned($0) }

        let hkItems: [RecentItem] = historicalRuns
            .filter { $0.date <= now }
            .map { .historical($0) }

        return (planItems + hkItems)
            .sorted { $0.date > $1.date }
            .prefix(5)
            .map { $0 }
    }

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: .strideSM) {
            Text("Recent Runs")
                .font(Font.stride.headingMedium)
                .padding(.horizontal, 2)

            ForEach(recentItems) { item in
                switch item {
                case .planned(let day):
                    RecentWorkoutCard(day: day, units: profile.unitPreference) {
                        selectedDay = day
                        showWorkoutDetail = true
                    }
                case .historical(let run):
                    RecentHistoricalRunCard(run: run, units: profile.unitPreference) {
                        selectedHistoricalRun = run
                        showHistoricalRunDetail = true
                    }
                }
            }
        }
    }

    // MARK: - Data Helpers

    /// Returns the planned WorkoutDay for a date, hiding days before the plan was generated
    /// (those were created retroactively and the user never trained them in-app).
    private func plannedWorkout(for date: Date) -> WorkoutDay? {
        guard let plan = profile.activePlan else { return nil }
        let planCreated = calendar.startOfDay(for: plan.generatedAt)
        guard date >= planCreated else { return nil }
        return plan.workoutDays.first {
            calendar.isDate($0.effectiveDate, inSameDayAs: date)
        }
    }

    private func historicalRun(for date: Date) -> HistoricalRun? {
        guard date < calendar.startOfDay(for: DateProvider.shared.now) else { return nil }
        return historicalRuns.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - Calendar Geometry

    private func shiftMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }

    private func isSameMonth(_ date: Date, as reference: Date) -> Bool {
        calendar.isDate(date, equalTo: reference, toGranularity: .month)
    }

    private var weeksInMonth: [[Date]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else { return [] }

        var weeks: [[Date]] = []
        var current = firstWeek.start
        while current < monthInterval.end {
            var week: [Date] = []
            for _ in 0..<7 {
                week.append(current)
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
            weeks.append(week)
        }
        return weeks
    }
}

// MARK: - Calendar Day Cell

private struct CalendarDayCell: View {
    let date: Date
    let workoutDay: WorkoutDay?
    let historicalRun: HistoricalRun?
    let isCurrentMonth: Bool
    let onTap: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isTappable: Bool { workoutDay != nil || historicalRun != nil }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(Font.stride.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        isToday ? Color.stride.lavenderDeep :
                        isCurrentMonth ? .primary :
                        Color(.systemGray4)
                    )

                indicator
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isToday ? Color.stride.lavenderLight : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isTappable)
    }

    @ViewBuilder
    private var indicator: some View {
        if let day = workoutDay {
            if day.isCompleted {
                VStack(spacing: 1) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.stride.mint)
                    if day.isSwapped {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.stride.lavenderDeep)
                    }
                }
            } else if day.isSkipped {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(.systemGray3))
            } else {
                VStack(spacing: 1) {
                    Circle()
                        .fill(day.workoutType.accentColor)
                        .frame(width: 6, height: 6)
                    if day.isSwapped {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.stride.lavenderDeep)
                    }
                }
            }
        } else if historicalRun != nil {
            Image(systemName: "figure.run")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.stride.lavenderDeep.opacity(0.65))
        } else {
            Circle()
                .fill(Color.clear)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Historical Run Detail Sheet

struct HistoricalRunDetailSheet: View {
    let run: HistoricalRun
    let units: UnitSystem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideLG) {
                        // Hero header
                        HeroGlassCard(tint: Color.stride.lavender) {
                            VStack(spacing: .strideMD) {
                                // Top row: icon + source badge
                                HStack {
                                    ZStack {
                                        Circle()
                                            .fill(Color.stride.lavenderDeep.opacity(0.15))
                                            .frame(width: 48, height: 48)
                                        Image(systemName: run.isIndoorRun ? "treadmill" : "figure.run")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(Color.stride.lavenderDeep)
                                    }
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.red.opacity(0.6))
                                        Text("Apple Health")
                                            .font(Font.stride.label)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.5))
                                    )
                                }

                                // Distance hero
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(displayDistance)
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.stride.lavenderDeep)
                                    Text(units.shortLabel)
                                        .font(Font.stride.headingSmall)
                                        .foregroundStyle(Color.stride.lavenderDeep.opacity(0.6))
                                    Spacer()
                                }

                                // Date + time
                                HStack(spacing: .strideSM) {
                                    Label(
                                        run.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                                        systemImage: "calendar"
                                    )
                                    Text("\u{00B7}")
                                    Text(run.startDate.formatted(.dateTime.hour().minute()))
                                }
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Quick stats row
                                HStack(spacing: 0) {
                                    quickStat(value: run.formattedDuration, label: "Duration")
                                    Divider().frame(height: 32)
                                    quickStat(value: run.formattedPace(units: units), label: "Avg Pace")
                                    if let kcal = run.totalCalories {
                                        Divider().frame(height: 32)
                                        quickStat(value: "\(Int(kcal))", label: "Calories")
                                    }
                                }
                                .padding(.top, .strideXS)
                            }
                        }

                        // Heart rate section
                        if run.averageHeartRate != nil || run.maxHeartRate != nil {
                            heartRateSection
                        }

                        // Running dynamics section
                        if run.averageCadenceSPM != nil || run.averageStrideLengthMeters != nil {
                            runningDynamicsSection
                        }
                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle(run.isIndoorRun ? "Indoor Run" : "Outdoor Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    // MARK: - Quick Stat

    private func quickStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label)
                .font(Font.stride.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Heart Rate Section

    private var heartRateSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Heart Rate", systemImage: "heart.fill")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)

                HStack(spacing: .strideMD) {
                    if let avg = run.averageHeartRate {
                        heartRateStat(
                            value: "\(Int(avg))",
                            label: "Avg",
                            color: heartRateColor(bpm: avg)
                        )
                    }
                    if let max = run.maxHeartRate {
                        heartRateStat(
                            value: "\(Int(max))",
                            label: "Max",
                            color: heartRateColor(bpm: max)
                        )
                    }
                }
            }
        }
    }

    private func heartRateStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: .strideXS) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text("bpm")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(Font.stride.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.strideSM)
        .background(
            RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    /// Simple color coding for heart rate values (not zones — just visual indication).
    private func heartRateColor(bpm: Double) -> Color {
        switch bpm {
        case ..<120:  return Color.stride.mint
        case ..<150:  return Color.stride.sage
        case ..<170:  return Color.stride.warmOrange
        default:      return Color.stride.coral
        }
    }

    // MARK: - Running Dynamics Section

    private var runningDynamicsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Running Dynamics", systemImage: "waveform.path.ecg")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)

                HStack(spacing: .strideMD) {
                    if let cadence = run.averageCadenceSPM {
                        dynamicStat(
                            value: "\(Int(cadence))",
                            unit: "spm",
                            label: "Cadence",
                            icon: "figure.run.circle"
                        )
                    }
                    if let stride = run.averageStrideLengthMeters {
                        dynamicStat(
                            value: String(format: "%.2f", stride),
                            unit: "m",
                            label: "Stride Length",
                            icon: "arrow.left.and.right"
                        )
                    }
                }
            }
        }
    }

    private func dynamicStat(value: String, unit: String, label: String, icon: String) -> some View {
        VStack(spacing: .strideXS) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.stride.lavenderDeep.opacity(0.6))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(unit)
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(Font.stride.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.strideSM)
        .background(
            RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                .fill(Color.stride.lavenderLight.opacity(0.3))
        )
    }

    private var displayDistance: String {
        let value = units == .miles ? run.distanceMiles : run.distanceMiles * 1.60934
        return String(format: "%.2f", value)
    }
}

// MARK: - Recent Workout Card

private struct RecentWorkoutCard: View {
    let day: WorkoutDay
    let units: UnitSystem
    let onTap: () -> Void

    private var distanceText: String {
        guard day.workoutType != .restDay else { return "" }
        if let log = day.log, log.actualDistanceMiles > 0 {
            return log.actualDistanceMiles.formattedDistance(unit: units)
        }
        return day.targetDistanceMiles > 0
            ? day.targetDistanceMiles.formattedDistance(unit: units)
            : ""
    }

    private var dateText: String {
        day.effectiveDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        Button(action: onTap) {
            GlassCard(padding: .strideSM) {
                HStack(spacing: .strideSM) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.workoutType.accentColor)
                        .frame(width: 4)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.workoutType.rawValue)
                            .font(Font.stride.bodyMedium)
                        Text(dateText)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if !distanceText.isEmpty {
                            Text(distanceText)
                                .font(Font.stride.bodyMedium)
                        }
                        if let log = day.log, log.actualDurationSeconds > 0 {
                            let mins = log.actualDurationSeconds / 60
                            let secs = log.actualDurationSeconds % 60
                            Text(String(format: "%d:%02d", mins, secs))
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.stride.mint)
                        .font(.system(size: 18))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Historical Run Card

private struct RecentHistoricalRunCard: View {
    let run: HistoricalRun
    let units: UnitSystem
    let onTap: () -> Void

    private var dateText: String {
        run.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        Button(action: onTap) {
            GlassCard(padding: .strideSM) {
                HStack(spacing: .strideSM) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.stride.lavenderDeep.opacity(0.6))
                        .frame(width: 4)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(run.isIndoorRun ? "Indoor Run" : "Outdoor Run")
                            .font(Font.stride.bodyMedium)
                        Text(dateText)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(run.distanceMiles.formattedDistance(unit: units))
                            .font(Font.stride.bodyMedium)
                        Text(run.formattedDuration)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "figure.run")
                        .foregroundStyle(Color.stride.lavenderDeep.opacity(0.65))
                        .font(.system(size: 16))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
