import Foundation
import SwiftData

@Observable
final class WorkoutDetailViewModel {

    let workout: WorkoutDay
    private let plan: TrainingPlan
    private let adjustmentService: WorkoutAdjustmentService

    var showLogWorkout = false
    var showDeleteLogConfirmation = false

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

    /// Skip is only available when:
    /// - The workout is not completed (no log exists)
    /// - It's not a rest day
    var canAdjust: Bool {
        !workout.isCompleted && workout.log == nil && workout.workoutType != .restDay
    }

    /// True when the workout has a log attached — used to show disabled state messaging.
    var isLocked: Bool {
        workout.log != nil
    }

    var skipButtonLabel: String {
        workout.isSkipped ? "Unmark as Skipped" : "Skip Workout"
    }

    // MARK: - Weekly mileage (for rest-day log sheet)

    var weeklyLoggedMiles: Double {
        let cal = Calendar.current
        let now = DateProvider.shared.now
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? now
        return plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate <= now }
            .compactMap { day in
                guard let log = day.log else { return nil as Double? }
                if let activityType = log.restDayActivityType, !activityType.countsTowardRunningVolume {
                    return nil
                }
                return log.actualDistanceMiles
            }
            .reduce(0, +)
    }

    var weeklyTargetMiles: Double {
        let cal = Calendar.current
        let now = DateProvider.shared.now
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? now
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? now
        return plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate < weekEnd && $0.workoutType.isRun && !$0.isSkipped }
            .map { $0.targetDistanceMiles }
            .reduce(0, +)
    }

    // MARK: - Readiness Check

    /// Fetches the readiness check recorded on the same day as this workout, if any.
    func readinessCheck(context: ModelContext) -> ReadinessCheck? {
        let cal = Calendar.current
        let workoutDate = cal.startOfDay(for: workout.effectiveDate)
        let nextDay = cal.date(byAdding: .day, value: 1, to: workoutDate) ?? workoutDate
        let descriptor = FetchDescriptor<ReadinessCheck>(
            predicate: #Predicate { $0.date >= workoutDate && $0.date < nextDay }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Actions

    func toggleSkipped() {
        if workout.isSkipped {
            adjustmentService.unmarkSkipped(workout)
        } else {
            adjustmentService.markSkipped(workout)
        }
    }

    /// Deletes the workout log, re-opening swap/skip actions.
    func deleteLog(context: ModelContext) {
        guard let log = workout.log else { return }
        workout.log = nil
        workout.isCompleted = false
        context.delete(log)
        try? context.save()
    }

    /// Reverts any readiness-based adaptation on this workout, restoring original values.
    func revertAdaptation(context: ModelContext) {
        guard workout.isAdapted else { return }

        let workoutID = workout.id
        let descriptor = FetchDescriptor<AdaptationRecord>(
            predicate: #Predicate { $0.workoutDayID == workoutID && !$0.wasRevertedByUser }
        )

        if let record = try? context.fetch(descriptor).first {
            let engine = PlanAdaptationEngine()
            engine.revertAdaptation(record: record, workout: workout, context: context)
        } else {
            // Fallback: restore directly from stored originals
            if let origType = workout.originalWorkoutType {
                workout.workoutType = origType
                workout.workoutTitle = origType.rawValue
            }
            if let origDist = workout.originalTargetDistanceMiles {
                workout.targetDistanceMiles = origDist
            }
            if let origEffort = workout.originalEffortLevel {
                workout.effortLevel = origEffort
            }
            workout.isAdapted = false
            workout.originalWorkoutType = nil
            workout.originalTargetDistanceMiles = nil
            workout.originalEffortLevel = nil
            workout.adaptationNote = nil
            try? context.save()
        }
    }
}
