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
}
