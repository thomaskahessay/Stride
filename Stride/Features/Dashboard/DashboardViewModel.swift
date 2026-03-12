import SwiftUI
import SwiftData

@Observable
final class DashboardViewModel {

    // MARK: - State
    var todayWorkout: WorkoutDay?
    var currentWeekDays: [WorkoutDay] = []
    var weeklyCompletedMiles: Double = 0
    var weeklyTargetMiles: Double = 0
    var currentStreak: Int = 0
    var daysToRace: Int = 0
    var planCompletionPercent: Double = 0
    var hasCompletedReadyCheckToday: Bool = false
    var pendingAdaptations: [AdaptationRecord] = []

    // MARK: - Init
    private let profile: UserProfile
    private var modelContext: ModelContext?

    init(profile: UserProfile, modelContext: ModelContext? = nil) {
        self.profile = profile
        self.modelContext = modelContext
        refresh()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Refresh

    func refresh() {
        guard let plan = profile.activePlan else { return }
        let today = Calendar.current.startOfDay(for: Date())

        // Today's workout — match by effectiveDate so moved workouts appear correctly
        todayWorkout = plan.workoutDays.first {
            Calendar.current.isDateInToday($0.effectiveDate)
        }

        // Current week days — Sunday to Saturday of the current week.
        // For past days, only include completed workouts — unlogged past plan entries are hidden
        // since the plan was generated retroactively and the user never ran those days in-app.
        let weekday = Calendar.current.component(.weekday, from: today) // 1 = Sunday
        let stripStart = Calendar.current.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let stripEnd   = Calendar.current.date(byAdding: .day, value: 7, to: stripStart) ?? today
        currentWeekDays = plan.workoutDays
            .filter { day in
                guard day.effectiveDate >= stripStart && day.effectiveDate < stripEnd else { return false }
                if day.effectiveDate < today { return day.isCompleted }
                return true
            }
            .sorted { $0.effectiveDate < $1.effectiveDate }

        // Separate ISO-week bounds used only for mileage calculations
        let weekStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? today
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? today

        // Days to race
        let components = Calendar.current.dateComponents([.day], from: today, to: profile.raceDate)
        daysToRace = max(0, components.day ?? 0)

        // Plan completion
        planCompletionPercent = plan.completionPercentage

        // Weekly miles — use effectiveDate so moved workouts count in the right week
        // Completed: only days up to today that have a log
        weeklyCompletedMiles = plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate <= Date() }
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)
        // Target: the full week's planned mileage (Sun–Sat), excluding days before the plan was generated
        let weekEndSat = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let planCreated = Calendar.current.startOfDay(for: plan.generatedAt)
        let targetStart = max(weekStart, planCreated)
        weeklyTargetMiles = plan.workoutDays
            .filter { $0.effectiveDate >= targetStart && $0.effectiveDate < weekEndSat && $0.workoutType.isRun && !$0.isSkipped }
            .map { $0.targetDistanceMiles }
            .reduce(0, +)

        // Streak
        currentStreak = calculateStreak(plan: plan)

        // Ready Check — has one been completed today?
        if let ctx = modelContext {
            let todayStart = Calendar.current.startOfDay(for: Date())
            let descriptor = FetchDescriptor<ReadinessCheck>(
                predicate: #Predicate { $0.date >= todayStart }
            )
            hasCompletedReadyCheckToday = (try? ctx.fetchCount(descriptor)) ?? 0 > 0
        }

        // Run adaptation engine
        runAdaptationEngine()
    }

    // MARK: - Adaptation Engine

    private let adaptationEngine = PlanAdaptationEngine()

    func runAdaptationEngine() {
        guard let plan = profile.activePlan, let ctx = modelContext else { return }

        // Fetch today's readiness checks
        let todayStart = Calendar.current.startOfDay(for: Date())
        let checkDescriptor = FetchDescriptor<ReadinessCheck>(
            predicate: #Predicate { $0.date >= todayStart }
        )
        let readinessChecks = (try? ctx.fetch(checkDescriptor)) ?? []

        let result = adaptationEngine.evaluateAndAdapt(
            plan: plan,
            profile: profile,
            readinessChecks: readinessChecks,
            context: ctx
        )

        // Merge auto-applied records into pending (show banner)
        if !result.autoApplied.isEmpty {
            pendingAdaptations = result.autoApplied
        }

        // Also fetch any existing undismissed records
        let descriptor = FetchDescriptor<AdaptationRecord>(
            predicate: #Predicate { !$0.wasDismissed && !$0.wasRevertedByUser }
        )
        if let existing = try? ctx.fetch(descriptor) {
            // Show records from today only
            pendingAdaptations = existing.filter {
                Calendar.current.isDateInToday($0.date)
            }
        }
    }

    func dismissAdaptation(_ record: AdaptationRecord) {
        record.wasDismissed = true
        pendingAdaptations.removeAll { $0.id == record.id }
        if let ctx = modelContext {
            try? ctx.save()
        }
    }

    func dismissAllAdaptations() {
        for record in pendingAdaptations {
            record.wasDismissed = true
        }
        pendingAdaptations.removeAll()
        if let ctx = modelContext {
            try? ctx.save()
        }
    }

    func revertAllAdaptations() {
        guard let plan = profile.activePlan, let ctx = modelContext else { return }

        for record in pendingAdaptations {
            if let workout = plan.workoutDays.first(where: { $0.id == record.workoutDayID }) {
                adaptationEngine.revertAdaptation(record: record, workout: workout, context: ctx)
            }
        }
        pendingAdaptations.removeAll()
        refresh()
    }

    // MARK: - Factory

    func makeWorkoutDetailViewModel(for workout: WorkoutDay) -> WorkoutDetailViewModel? {
        guard let plan = profile.activePlan else { return nil }
        return WorkoutDetailViewModel(workout: workout, plan: plan)
    }

    // MARK: - Streak calculation
    //
    // Streak = consecutive days of plan adherence.
    // - Workout day + completed → streak continues (+1)
    // - Rest day + no log → streak continues (+1, resting IS the plan)
    // - Rest day + any log → streak continues (+1, bonus effort)
    // - Workout day + missed (past, not completed, not skipped) → streak breaks
    // - Today's workout not yet done → don't break (day isn't over)

    private func calculateStreak(plan: TrainingPlan) -> Int {
        let cal = Calendar.current
        var streak = 0
        var checkDate = cal.startOfDay(for: Date())

        while true {
            let day = plan.workoutDays.first {
                cal.isDate($0.effectiveDate, inSameDayAs: checkDate)
            }

            // No plan day for this date — we've gone past the plan boundary
            guard let day else { break }

            let isToday = cal.isDateInToday(checkDate)

            if day.workoutType == .restDay {
                // Rest days always count — resting is following the plan
                streak += 1
            } else if day.isCompleted {
                streak += 1
            } else if isToday {
                // Today's workout isn't done yet — don't break, but don't count
                // (day isn't over, skip to yesterday)
            } else if day.isPast {
                break // missed workout breaks the streak
            }

            guard let prev = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }

    // MARK: - Computed helpers

    var weeklyProgressFraction: Double {
        guard weeklyTargetMiles > 0 else { return 0 }
        return min(1.0, weeklyCompletedMiles / weeklyTargetMiles)
    }

    var raceName: String {
        profile.raceType.displayName
    }

    var isRestDay: Bool {
        todayWorkout?.workoutType == .restDay || todayWorkout == nil
    }

    var motivationalMessage: String {
        switch daysToRace {
        case 0: return "Race day is here. You've got this."
        case 1...7: return "One week out. Trust your training."
        case 8...21: return "The hay is in the barn. Keep stacking miles."
        case 22...42: return "You're in the thick of it. This is where champions are made."
        default: return "Every run counts. Keep showing up."
        }
    }
}
