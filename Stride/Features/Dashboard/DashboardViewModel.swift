import SwiftUI
import SwiftData

@Observable
final class DashboardViewModel {

    // MARK: - State
    var todayWorkout: WorkoutDay?
    var nextWorkout: WorkoutDay?
    var nextRunWorkout: WorkoutDay?
    var currentWeekDays: [WorkoutDay] = []
    var weeklyCompletedMiles: Double = 0
    var weeklyTargetMiles: Double = 0
    var weeklyWorkoutsCompleted: Int = 0
    var weeklyWorkoutsPlanned: Int = 0
    var daysToRace: Int = 0
    var planCompletionPercent: Double = 0
    var hasCompletedReadyCheckToday: Bool = false
    var coachRecommendation: CoachRecommendation?
    var dismissedRecommendationIDs: Set<UUID> = []

    // MARK: - Init
    private let profile: UserProfile
    private var modelContext: ModelContext?
    private let adaptationEngine = PlanAdaptationEngine()

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
        let cal = Calendar.current
        let now = DateProvider.shared.now
        let today = cal.startOfDay(for: now)

        // Today's workout — match by effectiveDate so moved workouts appear correctly
        todayWorkout = plan.workoutDays.first {
            cal.isDate($0.effectiveDate, inSameDayAs: today)
        }

        // Next workout — find the very next day after today (including rest days)
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: today) {
            let upcoming = plan.workoutDays
                .filter { $0.effectiveDate >= tomorrow }
                .sorted { $0.effectiveDate < $1.effectiveDate }
            nextWorkout = upcoming.first
            // Also find next non-rest workout (for use on rest days)
            nextRunWorkout = upcoming.first { $0.workoutType != .restDay }
        }

        // Current week days — Sunday to Saturday of the current week.
        // Show all days from when the plan was generated onwards (hide retroactive pre-plan days).
        let planCreated = cal.startOfDay(for: plan.generatedAt)
        let weekday = cal.component(.weekday, from: today)
        let stripStart = cal.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let stripEnd   = cal.date(byAdding: .day, value: 7, to: stripStart) ?? today
        currentWeekDays = plan.workoutDays
            .filter { day in
                guard day.effectiveDate >= stripStart && day.effectiveDate < stripEnd else { return false }
                return day.effectiveDate >= planCreated
            }
            .sorted { $0.effectiveDate < $1.effectiveDate }

        // Separate ISO-week bounds used only for mileage calculations
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? today
        // Days to race
        let components = cal.dateComponents([.day], from: today, to: profile.raceDate)
        daysToRace = max(0, components.day ?? 0)

        // Plan completion
        planCompletionPercent = plan.completionPercentage

        // Weekly miles — use effectiveDate so moved workouts count in the right week.
        // Both values are stored in raw miles; unit conversion happens at display time.

        // Completed: only days up to today that have a log
        weeklyCompletedMiles = plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate <= now }
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)
        // Target: the full week's planned mileage (Sun–Sat), excluding days before the plan was generated
        let weekEndSat = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let targetStart = max(weekStart, planCreated)
        // Sum raw miles — unit conversion happens at display time in WeeklyProgressCard
        weeklyTargetMiles = plan.workoutDays
            .filter { $0.effectiveDate >= targetStart && $0.effectiveDate < weekEndSat && $0.workoutType.isRun }
            .map { $0.targetDistanceMiles }
            .reduce(0, +)

        // Weekly consistency
        let thisWeekWorkouts = plan.workoutDays.filter {
            $0.effectiveDate >= weekStart && $0.effectiveDate < weekEndSat
            && $0.workoutType != .restDay
        }
        weeklyWorkoutsPlanned = thisWeekWorkouts.count
        weeklyWorkoutsCompleted = thisWeekWorkouts.filter { $0.isCompleted }.count

        // Ready Check — has one been completed today?
        if let ctx = modelContext {
            let todayStart = cal.startOfDay(for: now)
            let descriptor = FetchDescriptor<ReadinessCheck>(
                predicate: #Predicate { $0.date >= todayStart }
            )
            hasCompletedReadyCheckToday = (try? ctx.fetchCount(descriptor)) ?? 0 > 0
        }

        // Check for missed key workouts (advisory only)
        checkForCoachRecommendations()
    }

    // MARK: - Coach Recommendations

    private func checkForCoachRecommendations() {
        guard let plan = profile.activePlan else { return }

        if let recommendation = adaptationEngine.checkForMissedKeyWorkouts(plan: plan) {
            // Don't show if already dismissed
            if !dismissedRecommendationIDs.contains(recommendation.id) {
                coachRecommendation = recommendation
            }
        } else {
            coachRecommendation = nil
        }
    }

    func dismissRecommendation() {
        if let rec = coachRecommendation {
            dismissedRecommendationIDs.insert(rec.id)
        }
        coachRecommendation = nil
    }

    // MARK: - Factory

    func makeWorkoutDetailViewModel(for workout: WorkoutDay) -> WorkoutDetailViewModel? {
        guard let plan = profile.activePlan else { return nil }
        return WorkoutDetailViewModel(workout: workout, plan: plan)
    }

    // MARK: - Computed helpers

    var weeklyProgressFraction: Double {
        guard weeklyTargetMiles > 0 else { return 0 }
        return min(1.0, weeklyCompletedMiles / weeklyTargetMiles)
    }

    var raceName: String {
        profile.raceType.displayName
    }

    var todayIsCompleted: Bool {
        todayWorkout?.isCompleted == true
    }

    var isRestDay: Bool {
        todayWorkout?.workoutType == .restDay || todayWorkout == nil
    }

    var isStrengthDay: Bool {
        todayWorkout?.workoutType == .strengthDay
    }

    /// True when today's workout doesn't need a Ready Check (rest days, strength days).
    var skipReadyCheck: Bool {
        isRestDay || isStrengthDay
    }

    /// The most recent HealthKit run from today, if today's workout hasn't been logged yet.
    var todayHealthKitRun: HealthKitWorkoutData? {
        guard let workout = todayWorkout,
              !workout.isCompleted,
              workout.workoutType != .restDay else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: DateProvider.shared.now)
        return HealthKitManager.shared.recentWorkouts.first { hkRun in
            cal.isDate(hkRun.workoutDate, inSameDayAs: today)
        }
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
