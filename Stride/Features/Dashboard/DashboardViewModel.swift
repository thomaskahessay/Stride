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

    // MARK: - Init
    private let profile: UserProfile

    init(profile: UserProfile) {
        self.profile = profile
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        guard let plan = profile.activePlan else { return }
        let today = Calendar.current.startOfDay(for: Date())

        // Today's workout — match by effectiveDate so moved workouts appear correctly
        todayWorkout = plan.workoutDays.first {
            Calendar.current.isDateInToday($0.effectiveDate)
        }

        // Current week days — use the same ±3 day window as the strip so they always align.
        // For past days, only include completed workouts — unlogged past plan entries are hidden
        // since the plan was generated retroactively and the user never ran those days in-app.
        let stripStart = Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today
        let stripEnd   = Calendar.current.date(byAdding: .day, value:  4, to: today) ?? today
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
        let weekDays = plan.workoutDays.filter { $0.effectiveDate >= weekStart && $0.effectiveDate <= Date() }
        weeklyCompletedMiles = weekDays
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)
        weeklyTargetMiles = weekDays
            .filter { $0.workoutType.isRun && !$0.isSkipped }
            .map { $0.targetDistanceMiles }
            .reduce(0, +)

        // Streak
        currentStreak = calculateStreak(plan: plan)
    }

    // MARK: - Factory

    func makeWorkoutDetailViewModel(for workout: WorkoutDay) -> WorkoutDetailViewModel? {
        guard let plan = profile.activePlan else { return nil }
        return WorkoutDetailViewModel(workout: workout, plan: plan)
    }

    // MARK: - Streak calculation

    private func calculateStreak(plan: TrainingPlan) -> Int {
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())

        while true {
            let day = plan.workoutDays.first {
                Calendar.current.isDate($0.effectiveDate, inSameDayAs: checkDate)
            }

            guard let day else { break }

            if day.workoutType == .restDay {
                // Rest days don't break streak but don't count
            } else if day.isCompleted {
                streak += 1
            } else if day.isPast {
                break // missed workout breaks streak
            }

            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) else { break }
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
