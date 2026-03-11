import Foundation
import SwiftData

/// Owns all user-initiated mutations to workout scheduling.
/// The plan structure (WorkoutDay.date) is never touched — only
/// WorkoutDay.isSkipped and WorkoutDay.rescheduledDate are modified.
final class WorkoutAdjustmentService {

    func markSkipped(_ workout: WorkoutDay) {
        guard !workout.isCompleted else { return }
        workout.isSkipped = true
    }

    func unmarkSkipped(_ workout: WorkoutDay) {
        workout.isSkipped = false
    }

    /// Moves `workout` to `targetDate`.
    /// If `conflicting` is provided the two workouts swap effective dates.
    func reschedule(_ workout: WorkoutDay, to targetDate: Date, swappingWith conflicting: WorkoutDay? = nil) {
        guard !workout.isCompleted else { return }

        let fromEffective = workout.effectiveDate

        // Set workout's new display date (nil = back to original)
        workout.rescheduledDate = Calendar.current.isDate(targetDate, inSameDayAs: workout.date)
            ? nil
            : targetDate

        // Give the conflicting workout the date the moved workout came from
        if let conflicting {
            conflicting.rescheduledDate = Calendar.current.isDate(fromEffective, inSameDayAs: conflicting.date)
                ? nil
                : fromEffective
        }
    }
}
