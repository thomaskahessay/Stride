import Foundation
import SwiftData

@Model
final class AdaptationRecord {
    var id: UUID
    var date: Date
    var adaptationType: AdaptationType
    var reason: String
    var workoutDayID: UUID
    var originalWorkoutType: WorkoutType
    var originalDistanceMiles: Double
    var originalEffortLevel: EffortLevel
    var wasRevertedByUser: Bool
    var wasDismissed: Bool

    init(
        adaptationType: AdaptationType,
        reason: String,
        workoutDayID: UUID,
        originalWorkoutType: WorkoutType,
        originalDistanceMiles: Double,
        originalEffortLevel: EffortLevel
    ) {
        self.id = UUID()
        self.date = Date()
        self.adaptationType = adaptationType
        self.reason = reason
        self.workoutDayID = workoutDayID
        self.originalWorkoutType = originalWorkoutType
        self.originalDistanceMiles = originalDistanceMiles
        self.originalEffortLevel = originalEffortLevel
        self.wasRevertedByUser = false
        self.wasDismissed = false
    }
}
