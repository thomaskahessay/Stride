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

        // Current week days — Sunday to Saturday of the current week.
        // For past days, only include completed workouts — unlogged past plan entries are hidden
        // since the plan was generated retroactively and the user never ran those days in-app.
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let stripStart = cal.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let stripEnd   = cal.date(byAdding: .day, value: 7, to: stripStart) ?? today
        currentWeekDays = plan.workoutDays
            .filter { day in
                guard day.effectiveDate >= stripStart && day.effectiveDate < stripEnd else { return false }
                if day.effectiveDate < today { return day.isCompleted }
                return true
            }
            .sorted { $0.effectiveDate < $1.effectiveDate }

        // Separate ISO-week bounds used only for mileage calculations
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? today
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? today

        // Days to race
        let components = cal.dateComponents([.day], from: today, to: profile.raceDate)
        daysToRace = max(0, components.day ?? 0)

        // Plan completion
        planCompletionPercent = plan.completionPercentage

        // Weekly miles — use effectiveDate so moved workouts count in the right week
        // Completed: only days up to today that have a log
        weeklyCompletedMiles = plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate <= now }
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)
        // Target: the full week's planned mileage (Sun–Sat), excluding days before the plan was generated
        let weekEndSat = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let planCreated = cal.startOfDay(for: plan.generatedAt)
        let targetStart = max(weekStart, planCreated)
        weeklyTargetMiles = plan.workoutDays
            .filter { $0.effectiveDate >= targetStart && $0.effectiveDate < weekEndSat && $0.workoutType.isRun && !$0.isSkipped }
            .map { $0.targetDistanceMiles }
            .reduce(0, +)

        // Streak
        currentStreak = calculateStreak(plan: plan)

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

    // MARK: - Streak calculation
    //
    // Streak = consecutive days of plan adherence.
    // - Workout day + completed → streak continues (+1)
    // - Rest day + no log → streak continues (+1, resting IS the plan)
    // - Rest day + any log → streak continues (+1, bonus effort)
    // - Key workout missed (past, not completed, not skipped) → streak breaks
    // - Flexible workout missed → streak continues (easy runs are flexible)
    // - Today's workout not yet done → don't break (day isn't over)

    private func calculateStreak(plan: TrainingPlan) -> Int {
        let cal = Calendar.current
        let now = DateProvider.shared.now
        var streak = 0
        var hasCompletedAny = false
        var checkDate = cal.startOfDay(for: now)

        while true {
            let day = plan.workoutDays.first {
                cal.isDate($0.effectiveDate, inSameDayAs: checkDate)
            }

            // No plan day for this date — we've gone past the plan boundary
            guard let day else { break }

            let isToday = cal.isDate(checkDate, inSameDayAs: now)

            if day.workoutType == .restDay || day.workoutType == .strengthDay {
                // Rest days and strength days are neutral — continue a streak but can't start one
                if hasCompletedAny {
                    streak += 1
                }
            } else if day.isCompleted {
                hasCompletedAny = true
                streak += 1
            } else if isToday {
                // Today's workout isn't done yet — don't break, don't count
            } else if day.isPast && day.workoutType.isHard {
                break // only missed KEY workouts break the streak
            } else if day.isPast {
                // Missed flexible workout (easy run, recovery, strength) — don't break
                if hasCompletedAny {
                    streak += 1
                }
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

    var isStrengthDay: Bool {
        todayWorkout?.workoutType == .strengthDay
    }

    /// True when today's workout doesn't need a Ready Check (rest days, strength days).
    var skipReadyCheck: Bool {
        isRestDay || isStrengthDay
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
