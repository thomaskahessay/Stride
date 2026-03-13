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

                        legendRow

                        if !recentWorkouts.isEmpty {
                            recentWorkoutsSection
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
    }

    // MARK: - Legend

    private var legendRow: some View {
        GlassCard(padding: .strideSM) {
            HStack(spacing: .strideMD) {
                ForEach([WorkoutType.easyRun, .longRun, .tempoRun, .intervalRun, .restDay], id: \.self) { type in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(type.accentColor)
                            .frame(width: 8, height: 8)
                        Text(type == .easyRun ? "Easy" :
                             type == .longRun ? "Long" :
                             type == .tempoRun ? "Tempo" :
                             type == .intervalRun ? "Speed" : "Rest")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Historical run indicator
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.stride.lavenderDeep.opacity(0.6))
                    Text("History")
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Recent Workouts Section

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: .strideSM) {
            Text("Recent Workouts")
                .font(Font.stride.headingMedium)
                .padding(.horizontal, 2)

            ForEach(recentWorkouts, id: \.id) { day in
                RecentWorkoutCard(day: day, units: profile.unitPreference) {
                    selectedDay = day
                    showWorkoutDetail = true
                }
            }
        }
    }

    private var recentWorkouts: [WorkoutDay] {
        let now = DateProvider.shared.now
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return (profile.activePlan?.workoutDays ?? [])
            .filter { $0.isCompleted && $0.effectiveDate >= cutoff && $0.effectiveDate <= now }
            .sorted { $0.effectiveDate > $1.effectiveDate }
    }

    // MARK: - Data Helpers

    /// For past dates, only returns the WorkoutDay if it has been completed (has a log).
    /// For today and future dates, returns any planned WorkoutDay regardless of completion.
    /// This prevents unlogged past plan days (generated retroactively) from showing as "missed".
    private func plannedWorkout(for date: Date) -> WorkoutDay? {
        let isPast = date < calendar.startOfDay(for: DateProvider.shared.now)
        guard let day = profile.activePlan?.workoutDays.first(where: {
            calendar.isDate($0.effectiveDate, inSameDayAs: date)
        }) else { return nil }
        return isPast ? (day.isCompleted ? day : nil) : day
    }

    private func historicalRun(for date: Date) -> HistoricalRun? {
        // Only show historical runs on past dates
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.stride.mint)
            } else if day.isSkipped {
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(day.workoutType.accentColor)
                    .frame(width: 6, height: 6)
            }
        } else if historicalRun != nil {
            // Small running figure for imported HealthKit history
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
                                    Text("·")
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
        if let log = day.log {
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
