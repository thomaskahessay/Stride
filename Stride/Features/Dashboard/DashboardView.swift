import SwiftUI
import SwiftData

struct DashboardView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DashboardViewModel
    @State private var selectedWorkout: WorkoutDay? = nil
    @State private var showReadyCheck = false
    @State private var hasAutoShownReadyCheck = false
    @State private var showHKLogWorkout = false
    @State private var showConfetti = false

    init(profile: UserProfile) {
        self.profile = profile
        self._viewModel = State(initialValue: DashboardViewModel(profile: profile))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {
                        // Greeting + compact race countdown
                        greetingHeader

                        // Ready Check prompt (skip for rest & strength days)
                        if !viewModel.skipReadyCheck && !viewModel.hasCompletedReadyCheckToday {
                            ReadyCheckPromptCard { showReadyCheck = true }
                        }

                        // Coach recommendation (missed key workout)
                        if let recommendation = viewModel.coachRecommendation {
                            CoachRecommendationCard(
                                recommendation: recommendation,
                                onDismiss: { viewModel.dismissRecommendation() }
                            )
                        }

                        // Weekly calendar strip
                        WeeklyCalendarStrip(weekDays: viewModel.currentWeekDays) { workout in
                            selectedWorkout = workout
                        }

                        // Today's Workout (prominent)
                        if viewModel.isRestDay {
                            RestDayCard(
                                message: viewModel.motivationalMessage,
                                nextWorkout: viewModel.nextRunWorkout,
                                units: profile.unitPreference,
                                onTapNext: { if let next = viewModel.nextRunWorkout { selectedWorkout = next } }
                            )
                        } else if let workout = viewModel.todayWorkout {
                            TodayWorkoutCard(
                                workout: workout,
                                nextWorkout: viewModel.todayIsCompleted ? viewModel.nextWorkout : nil,
                                units: profile.unitPreference,
                                onTapToday: { selectedWorkout = workout },
                                onTapNext: {
                                    if let next = viewModel.nextWorkout {
                                        // If next is a rest day, tap should go to the workout after it
                                        if next.workoutType == .restDay, let run = viewModel.nextRunWorkout {
                                            selectedWorkout = run
                                        } else {
                                            selectedWorkout = next
                                        }
                                    }
                                }
                            )
                        }

                        // HealthKit run detected — quick log banner
                        if let hkRun = viewModel.todayHealthKitRun {
                            HealthKitRunBanner(
                                hkRun: hkRun,
                                units: profile.unitPreference
                            ) {
                                showHKLogWorkout = true
                            }
                        }

                        // Weekly Progress
                        WeeklyProgressCard(
                            completedMiles: viewModel.weeklyCompletedMiles,
                            targetMiles: viewModel.weeklyTargetMiles,
                            units: profile.unitPreference
                        )

                        // Weekly Consistency + Plan Progress
                        HStack(spacing: .strideMD) {
                            WeeklyConsistencyCard(
                                completed: viewModel.weeklyWorkoutsCompleted,
                                planned: viewModel.weeklyWorkoutsPlanned
                            )
                            .frame(maxWidth: .infinity)

                            PlanProgressCard(completion: viewModel.planCompletionPercent)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, .strideMD)
                    .padding(.vertical, .strideMD)
                }
                .refreshable {
                    await HealthKitManager.shared.fetchRecentWorkouts()
                    viewModel.refresh()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.refresh()

                // Auto-show Ready Check as full-screen cover on first daily open
                if !hasAutoShownReadyCheck
                    && !viewModel.skipReadyCheck
                    && !viewModel.hasCompletedReadyCheckToday
                    && viewModel.todayWorkout != nil {
                    hasAutoShownReadyCheck = true
                    // Small delay so the dashboard renders first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showReadyCheck = true
                    }
                }
            }
            .sheet(item: $selectedWorkout) { workout in
                if let detailVM = viewModel.makeWorkoutDetailViewModel(for: workout) {
                    WorkoutDetailView(viewModel: detailVM, units: profile.unitPreference)
                }
            }
            .onChange(of: selectedWorkout) { _, newValue in
                if newValue == nil { viewModel.refresh() }
            }
            .fullScreenCover(isPresented: $showReadyCheck) {
                ReadyCheckView(profile: profile, modelContext: modelContext)
            }
            .onChange(of: showReadyCheck) { _, isShowing in
                if !isShowing { viewModel.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("workoutLogged"))) { _ in
                viewModel.refresh()
            }
            .sheet(isPresented: $showHKLogWorkout, onDismiss: {
                viewModel.refresh()
            }) {
                LogWorkoutView(
                    workoutDay: viewModel.todayWorkout,
                    units: profile.unitPreference,
                    prefillHealthKitData: viewModel.todayHealthKitRun,
                    plan: profile.activePlan,
                    showConfettiOnParent: $showConfetti
                )
            }
        }
    }

    private var greetingHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)
                Text(profile.firstName)
                    .font(Font.stride.displayMedium)
                    .foregroundStyle(Color.stride.lavenderDeep)
            }
            Spacer()
            Image("StrideLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 36)
            Spacer()
            // Compact race countdown pill
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(viewModel.daysToRace)d")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.stride.lavenderDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.stride.lavender.opacity(0.25))
                        .overlay(Capsule().strokeBorder(Color.stride.lavender, lineWidth: 1))
                )
                Text(profile.raceType.displayName)
                    .font(Font.stride.label)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, .strideSM)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: DateProvider.shared.now)
        switch hour {
        case 5..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        default: return "Good evening,"
        }
    }
}

// MARK: - Weekly Calendar Strip

struct WeeklyCalendarStrip: View {
    let weekDays: [WorkoutDay]
    let onSelect: (WorkoutDay) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("THIS WEEK")
                    .font(Font.stride.label)
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                HStack(spacing: 0) {
                    ForEach(stripDates, id: \.self) { date in
                        let workout = weekDays.first {
                            Calendar.current.isDate($0.effectiveDate, inSameDayAs: date)
                        }
                        WeekStripDayCell(date: date, workout: workout) {
                            if let workout { onSelect(workout) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var stripDates: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        let today = cal.startOfDay(for: DateProvider.shared.now)
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let sunday = cal.date(byAdding: .day, value: -(weekday - 1), to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: sunday) }
    }
}

struct WeekStripDayCell: View {
    let date: Date
    let workout: WorkoutDay?
    let onTap: () -> Void

    private var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: DateProvider.shared.now) }
    private var isPast: Bool { date < Calendar.current.startOfDay(for: DateProvider.shared.now) }
    private var isTappable: Bool { workout != nil }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Text(dayLetter)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isToday ? Color.stride.lavenderDeep : .secondary)

                ZStack {
                    if isToday {
                        Circle()
                            .fill(Color.stride.lavender)
                            .frame(width: 30, height: 30)
                    }
                    Text(dayNumber)
                        .font(.system(size: 13, weight: isToday ? .bold : .regular, design: .rounded))
                        .foregroundStyle(isToday ? Color.stride.lavenderDeep : .primary)
                }
                .frame(width: 30, height: 30)

                // Workout dot
                dotView
            }
        }
        .buttonStyle(.plain)
        .disabled(!isTappable)
    }

    @ViewBuilder
    private var dotView: some View {
        if let workout {
            if workout.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.stride.mint)
            } else if workout.isSkipped {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(.systemGray3))
            } else {
                Circle()
                    .fill(workout.workoutType.accentColor.opacity(isPast ? 0.35 : 0.75))
                    .frame(width: 7, height: 7)
            }
        } else {
            Spacer().frame(height: 10)
        }
    }

    private var dayLetter: String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }
}

// MARK: - Today Workout Card (prominent)
// When today's workout is completed and there's a next workout, the card
// shows a compact completed summary at the top with an "up next" preview below.

struct TodayWorkoutCard: View {
    let workout: WorkoutDay
    let nextWorkout: WorkoutDay?
    let units: UnitSystem
    let onTapToday: () -> Void
    let onTapNext: () -> Void

    private var isCompleted: Bool { workout.isCompleted }

    var body: some View {
        if isCompleted, let next = nextWorkout {
            // Combined card: compact completed summary + up next preview
            HeroGlassCard(tint: next.workoutType == .restDay ? Color(.systemGray4) : next.workoutType.accentColor) {
                VStack(alignment: .leading, spacing: 0) {
                    // Compact completed summary (tappable)
                    Button(action: onTapToday) {
                        HStack(spacing: .strideSM) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.stride.mint)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(workout.workoutTitle)
                                    .font(Font.stride.bodyMedium.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if workout.workoutType.isRun {
                                        Text("\(formatDistance(workout.targetDistanceMiles)) \(units.shortLabel)")
                                            .font(Font.stride.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Done")
                                        .font(Font.stride.caption.weight(.medium))
                                        .foregroundStyle(Color.stride.mint)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    // Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 1)
                        .padding(.vertical, .strideSM)

                    // Up next preview
                    if next.workoutType == .restDay {
                        // Rest day preview — non-tappable, just informational
                        VStack(alignment: .leading, spacing: .strideSM) {
                            HStack {
                                Label("UP NEXT — \(nextDayLabel(next))", systemImage: "moon.fill")
                                    .font(Font.stride.label)
                                    .foregroundStyle(.secondary)
                                    .tracking(1.0)
                                Spacer()
                            }

                            Text("Rest Day")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text("Recovery is part of the plan. You earned it.")
                                .font(Font.stride.bodyMedium)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // Regular workout preview (tappable)
                        Button(action: onTapNext) {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                HStack {
                                    Label("UP NEXT — \(nextDayLabel(next))", systemImage: "arrow.right.circle.fill")
                                        .font(Font.stride.label)
                                        .foregroundStyle(next.workoutType.accentColor)
                                        .tracking(1.0)
                                    Spacer()
                                    WorkoutTypeBadge(type: next.workoutType)
                                }

                                Text(next.workoutTitle)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if next.workoutType.isRun {
                                    HStack(spacing: .strideLG) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(formatDistance(next.targetDistanceMiles))
                                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                            Text(units.shortLabel)
                                                .font(Font.stride.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(width: 1, height: 28)

                                        if let pace = next.targetPaceSecPerMile {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(pace.formattedPace(unit: units))
                                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                                Text("target pace")
                                                    .font(Font.stride.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Rectangle()
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(width: 1, height: 28)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(next.effortLevel.rawValue)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            Text("effort")
                                                .font(Font.stride.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } else {
                                    HStack(spacing: .strideLG) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(formatDuration(next.targetDurationMinutes))
                                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                            Text("duration")
                                                .font(Font.stride.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(width: 1, height: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(next.effortLevel.rawValue)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            Text("effort")
                                                .font(Font.stride.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Text("Tap to preview →")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            // Standard today card (not completed, or no next workout)
            Button(action: onTapToday) {
                HeroGlassCard(tint: workout.workoutType.accentColor) {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        HStack {
                            Label(workout.workoutType.isRun ? "TODAY'S RUN" : "TODAY'S WORKOUT", systemImage: "calendar")
                                .font(Font.stride.label)
                                .foregroundStyle(workout.workoutType.accentColor)
                                .tracking(1.0)
                            Spacer()
                            WorkoutTypeBadge(type: workout.workoutType)
                        }

                        Text(workout.workoutTitle)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        if workout.workoutType.isRun {
                            HStack(spacing: .strideLG) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatDistance(workout.targetDistanceMiles))
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text(units.shortLabel)
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 1, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.targetPaceSecPerMile.map { $0.formattedPace(unit: units) } ?? formatDuration(workout.targetDurationMinutes))
                                        .font(.system(size: workout.targetPaceSecPerMile != nil ? 18 : 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text(workout.targetPaceSecPerMile != nil ? "target pace" : "duration")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 1, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.effortLevel.rawValue)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("effort")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HStack(spacing: .strideLG) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatDuration(workout.targetDurationMinutes))
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("duration")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 1, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.effortLevel.rawValue)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("effort")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if workout.isCompleted {
                            Label("Completed", systemImage: "checkmark.circle.fill")
                                .font(Font.stride.bodyMedium.weight(.semibold))
                                .foregroundStyle(Color.stride.mint)
                                .padding(.top, 2)
                        } else {
                            Text("Tap to view details →")
                                .font(Font.stride.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func formatDistance(_ miles: Double) -> String {
        String(format: "%.1f", units.convert(miles))
    }

    private func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func nextDayLabel(_ next: WorkoutDay) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: DateProvider.shared.now)
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
           cal.isDate(next.effectiveDate, inSameDayAs: tomorrow) {
            return "TOMORROW"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: next.effectiveDate).uppercased()
    }
}

// MARK: - Rest Day Card

struct RestDayCard: View {
    let message: String
    var nextWorkout: WorkoutDay? = nil
    var units: UnitSystem = .miles
    var onTapNext: (() -> Void)? = nil

    var body: some View {
        HeroGlassCard(tint: nextWorkout?.workoutType.accentColor ?? Color(.systemGray4)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Label("REST DAY", systemImage: "moon.fill")
                            .font(Font.stride.label)
                            .foregroundStyle(.secondary)
                            .tracking(1.0)
                        Text(message)
                            .font(Font.stride.bodyLarge)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.stride.mint)
                }

                if let next = nextWorkout {
                    // Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 1)
                        .padding(.vertical, .strideSM)

                    // Up next preview
                    Button(action: { onTapNext?() }) {
                        VStack(alignment: .leading, spacing: .strideSM) {
                            HStack {
                                Label("UP NEXT — \(nextDayLabel(next))", systemImage: "arrow.right.circle.fill")
                                    .font(Font.stride.label)
                                    .foregroundStyle(next.workoutType.accentColor)
                                    .tracking(1.0)
                                Spacer()
                                WorkoutTypeBadge(type: next.workoutType)
                            }

                            Text(next.workoutTitle)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            if next.workoutType.isRun {
                                HStack(spacing: .strideLG) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formatDistance(next.targetDistanceMiles, units: units))
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                        Text(units.shortLabel)
                                            .font(Font.stride.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 1, height: 28)

                                    if let pace = next.targetPaceSecPerMile {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pace.formattedPace(unit: units))
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                            Text("target pace")
                                                .font(Font.stride.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(width: 1, height: 28)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(next.effortLevel.rawValue)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        Text("effort")
                                            .font(Font.stride.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Text("Tap to preview →")
                                .font(Font.stride.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func nextDayLabel(_ workout: WorkoutDay) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: DateProvider.shared.now)
        let target = cal.startOfDay(for: workout.effectiveDate)
        let diff = cal.dateComponents([.day], from: today, to: target).day ?? 0
        switch diff {
        case 1: return "TOMORROW"
        case 2...6:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: workout.effectiveDate).uppercased()
        default: return workout.effectiveDate.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func formatDistance(_ miles: Double, units: UnitSystem) -> String {
        String(format: "%.1f", units.convert(miles))
    }
}

// MARK: - Weekly Progress Card (Running Track)

/// A stadium-shaped running track with an open gap at the bottom center.
/// Draws clockwise from just right of bottom-center to just left of bottom-center.
private struct TrackShape: Shape {
    /// Half the gap width in points at the bottom of the track.
    static let gapHalf: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let r = rect.height / 2
        let gapHalf = Self.gapHalf

        guard rect.width - 2 * r >= 0 else {
            return Path(ellipseIn: rect)
        }

        var path = Path()

        // Start just right of bottom-center (the "start line")
        let start = CGPoint(x: rect.midX + gapHalf, y: rect.maxY)
        path.move(to: start)

        // Bottom-right straight
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))

        // Right semicircle (up)
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.midY),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)

        // Top straight (right to left)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))

        // Left semicircle (down)
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.midY),
                     radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)

        // Bottom-left straight — stop just left of bottom-center (the "finish line")
        let finish = CGPoint(x: rect.midX - gapHalf, y: rect.maxY)
        path.addLine(to: finish)

        return path
    }

    /// Returns the point at a given fraction (0…1) along the open track path.
    func point(at fraction: Double, in rect: CGRect) -> CGPoint {
        let p = path(in: rect)
        let clamped = max(0.001, min(1.0, fraction))
        let trimmed = p.trimmedPath(from: 0, to: clamped)
        return trimmed.currentPoint ?? CGPoint(x: rect.midX + Self.gapHalf, y: rect.maxY)
    }
}

struct WeeklyProgressCard: View {
    let completedMiles: Double
    let targetMiles: Double
    let units: UnitSystem

    private var fraction: Double {
        guard targetMiles > 0 else { return 0 }
        return min(1.0, completedMiles / targetMiles)
    }

    private let trackLineWidth: CGFloat = 6
    private let trackShape = TrackShape()

    private var mileageText: String {
        "\(String(format: "%.1f", units.convert(completedMiles))) / \(String(format: "%.1f", units.convert(targetMiles))) \(units.shortLabel)"
    }

    var body: some View {
        GlassCard {
            if fraction >= 1.0 {
                WeekCompleteView(mileageText: mileageText)
            } else {
                VStack(alignment: .leading, spacing: .strideSM) {
                    Text("This Week")
                        .font(Font.stride.headingSmall)

                    TrackView(
                        fraction: fraction,
                        trackLineWidth: trackLineWidth,
                        mileageText: mileageText
                    )
                    .frame(height: 110)
                }
            }
        }
    }
}

/// Celebration card shown when the user completes their weekly mileage goal.
/// Shows a checkered finish banner spanning the card, split in the middle
/// with a runner bursting through.
private struct WeekCompleteView: View {
    let mileageText: String

    private let bannerHeight: CGFloat = 36
    private let checkerSize: CGFloat = 9
    private let tearGap: CGFloat = 40

    var body: some View {
        VStack(spacing: .strideSM) {
            Text("This Week")
                .font(Font.stride.headingSmall)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                let midX = geo.size.width / 2
                let midY = geo.size.height / 2

                ZStack {
                    // Left half of checkered banner — slight downward rotation
                    CheckeredBanner(checkerSize: checkerSize)
                        .fill(Color.stride.lavenderDeep)
                        .frame(width: midX - tearGap / 2, height: bannerHeight)
                        .rotationEffect(.degrees(4), anchor: .trailing)
                        .position(x: (midX - tearGap / 2) / 2, y: midY)

                    // Right half of checkered banner — slight upward rotation
                    CheckeredBanner(checkerSize: checkerSize)
                        .fill(Color.stride.lavenderDeep)
                        .frame(width: midX - tearGap / 2, height: bannerHeight)
                        .rotationEffect(.degrees(-4), anchor: .leading)
                        .position(x: midX + tearGap / 2 + (midX - tearGap / 2) / 2, y: midY)

                    // Runner bursting through the center
                    Image(systemName: "figure.run")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.stride.lavenderDeep)
                        .position(x: midX, y: midY)
                }
            }
            .frame(height: 70)

            Text("Week complete!")
                .font(Font.stride.headingSmall)
                .foregroundStyle(Color.stride.lavenderDeep)

            Text(mileageText)
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Draws a checkered pattern (alternating filled squares in a grid).
private struct CheckeredBanner: Shape {
    let checkerSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cols = Int(ceil(rect.width / checkerSize))
        let rows = Int(ceil(rect.height / checkerSize))

        for row in 0..<rows {
            for col in 0..<cols {
                // Only draw filled squares in a checkerboard pattern
                guard (row + col) % 2 == 0 else { continue }
                let x = rect.minX + CGFloat(col) * checkerSize
                let y = rect.minY + CGFloat(row) * checkerSize
                let w = min(checkerSize, rect.maxX - x)
                let h = min(checkerSize, rect.maxY - y)
                path.addRect(CGRect(x: x, y: y, width: w, height: h))
            }
        }
        return path
    }
}

/// Renders the oval track with a gap, progress overlay, center label, and runner icon.
private struct TrackView: View {
    let fraction: Double
    let trackLineWidth: CGFloat
    let mileageText: String

    /// Small offset so the colored line ends just before the runner icon.
    private let runnerGap: Double = 0.015

    var body: some View {
        GeometryReader { geo in
            let insetRect = CGRect(
                x: trackLineWidth / 2,
                y: trackLineWidth / 2,
                width: geo.size.width - trackLineWidth,
                height: geo.size.height - trackLineWidth
            )

            ZStack {
                // Background track (full open path)
                TrackShape()
                    .stroke(Color.stride.lavenderLight,
                            style: StrokeStyle(lineWidth: trackLineWidth, lineCap: .round))
                    .padding(trackLineWidth / 2)

                // Progress overlay — ends slightly before the runner for spacing
                if fraction > 0 {
                    let trimEnd = max(0.001, fraction - runnerGap)
                    TrackShape()
                        .trim(from: 0, to: trimEnd)
                        .stroke(Color.stride.lavenderDeep,
                                style: StrokeStyle(lineWidth: trackLineWidth, lineCap: .round))
                        .padding(trackLineWidth / 2)
                        .animation(.easeInOut(duration: 0.8), value: fraction)
                }

                // Center mileage label
                Text(mileageText)
                    .font(Font.stride.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.stride.lavenderDeep)
                    .position(x: insetRect.midX, y: insetRect.midY)

                // Runner icon — flip horizontally when heading left
                let runnerPos = TrackShape().point(at: fraction, in: insetRect)
                let aheadPos = TrackShape().point(at: min(1.0, fraction + 0.01), in: insetRect)
                let headingLeft = aheadPos.x < runnerPos.x

                Image(systemName: "figure.run")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.stride.lavenderDeep)
                    .scaleEffect(x: headingLeft ? -1 : 1, y: 1)
                    .position(runnerPos)
                    .animation(.easeInOut(duration: 0.8), value: fraction)

            }
        }
    }
}

// MARK: - Weekly Consistency Card

struct WeeklyConsistencyCard: View {
    let completed: Int
    let planned: Int

    private var fraction: Double {
        guard planned > 0 else { return 0 }
        return Double(completed) / Double(planned)
    }

    var body: some View {
        GlassCard(cornerRadius: .strideRadiusLG) {
            VStack(spacing: 4) {
                Image(systemName: fraction >= 1.0 ? "checkmark.seal.fill" : "figure.run")
                    .font(.system(size: 28))
                    .foregroundStyle(fraction >= 1.0 ? Color.stride.mint : Color.stride.lavenderDeep)

                Text("\(completed)/\(planned)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("this week")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Plan Progress Card

struct PlanProgressCard: View {
    let completion: Double

    var body: some View {
        GlassCard(cornerRadius: .strideRadiusLG) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.stride.lavenderLight, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: completion)
                        .stroke(Color.stride.lavender, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.8), value: completion)
                }
                .frame(width: 52, height: 52)

                Text("\(Int(completion * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text("complete")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Ready Check Prompt Card

struct ReadyCheckPromptCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassCard {
                HStack(spacing: .strideSM) {
                    ZStack {
                        Circle()
                            .fill(Color.stride.lavender.opacity(0.3))
                            .frame(width: 40, height: 40)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.stride.lavenderDeep)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready Check")
                            .font(Font.stride.headingSmall)
                        Text("How are you feeling before today's workout?")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Type Badge

struct WorkoutTypeBadge: View {
    let type: WorkoutType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.sfSymbol)
                .font(.system(size: 10, weight: .semibold))
            Text(type.rawValue)
                .font(Font.stride.label)
        }
        .foregroundStyle(type.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(type.accentFill)
                .overlay(
                    Capsule()
                        .strokeBorder(type.accentColor.opacity(0.4), lineWidth: 1)
                )
        )
    }
}

// MARK: - HealthKit Run Banner

struct HealthKitRunBanner: View {
    let hkRun: HealthKitWorkoutData
    let units: UnitSystem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassCard {
                HStack(spacing: .strideSM) {
                    // Apple Health icon
                    ZStack {
                        Circle()
                            .fill(Color.stride.mint.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.stride.mint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Run Detected")
                            .font(Font.stride.headingSmall)

                        HStack(spacing: .strideSM) {
                            Text(String(format: "%.1f %@", units.convert(hkRun.distanceMiles), units.shortLabel))
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)

                            Text(formatDuration(hkRun.durationSeconds))
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text("Log")
                        .font(Font.stride.bodyMedium.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.stride.lavenderDeep)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
