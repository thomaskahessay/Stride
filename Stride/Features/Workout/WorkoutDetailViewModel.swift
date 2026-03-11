import Foundation
import SwiftData

@Observable
final class WorkoutDetailViewModel {

    let workout: WorkoutDay
    private let plan: TrainingPlan
    private let adjustmentService: WorkoutAdjustmentService

    var showLogWorkout = false
    var showReschedule = false

    init(
        workout: WorkoutDay,
        plan: TrainingPlan,
        adjustmentService: WorkoutAdjustmentService = WorkoutAdjustmentService()
    ) {
        self.workout = workout
        self.plan = plan
        self.adjustmentService = adjustmentService
    }

    // MARK: - Computed

    var canAdjust: Bool {
        !workout.isCompleted && workout.workoutType != .restDay
    }

    var raceDate: Date {
        plan.raceDate
    }

    var skipButtonLabel: String {
        workout.isSkipped ? "Unmark as Skipped" : "Skip Workout"
    }

    // MARK: - Actions

    func toggleSkipped() {
        if workout.isSkipped {
            adjustmentService.unmarkSkipped(workout)
        } else {
            adjustmentService.markSkipped(workout)
        }
    }

    func reschedule(to date: Date) {
        let conflicting = workout(on: date)
        adjustmentService.reschedule(workout, to: date, swappingWith: conflicting)
    }

    // MARK: - Helpers

    /// Returns the workout whose effectiveDate falls on `date`, excluding the current workout.
    func workout(on date: Date) -> WorkoutDay? {
        plan.workoutDays.first {
            Calendar.current.isDate($0.effectiveDate, inSameDayAs: date) && $0.id != workout.id
        }
    }
}
