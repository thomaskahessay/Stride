import Foundation
import SwiftData

@Observable
final class WorkoutDetailViewModel {

    let workout: WorkoutDay
    let plan: TrainingPlan
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

    /// Future workouts cannot be logged — only today and past workouts.
    var isFutureWorkout: Bool {
        workout.isFuture
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
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate < weekEnd && $0.workoutType.isRun }
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
    /// If this was a strength+run swap, reverts both days to their generator originals.
    func deleteLog(context: ModelContext) {
        guard let log = workout.log else { return }
        workout.log = nil
        workout.isCompleted = false
        context.delete(log)

        // If this was a strength+run swap (original was strength, now it's a run),
        // revert both days — the swap only existed to facilitate the log.
        if workout.isSwapped,
           workout.originalWorkoutType == .strengthDay,
           let partnerID = workout.swapPartnerID,
           let partner = plan.workoutDays.first(where: { $0.id == partnerID }),
           !partner.isCompleted {
            restoreToOriginal(workout)
            restoreToOriginal(partner)
        }

        try? context.save()
    }

    /// Restores a workout day to its generator-original properties and clears swap flags.
    private func restoreToOriginal(_ day: WorkoutDay) {
        if let type = day.originalWorkoutType { day.workoutType = type }
        if let dist = day.originalTargetDistanceMiles { day.targetDistanceMiles = dist }
        if let effort = day.originalEffortLevel { day.effortLevel = effort }
        if let dur = day.originalTargetDurationMinutes { day.targetDurationMinutes = dur }
        day.targetPaceSecPerMile = day.originalTargetPaceSecPerMile
        if let title = day.originalWorkoutTitle { day.workoutTitle = title }
        if let note = day.originalCoachingNote { day.coachingNote = note }
        day.stepsData = day.originalStepsData

        day.isSwapped = false
        day.swapNote = nil
        day.swapPartnerID = nil
        day.originalWorkoutType = nil
        day.originalTargetDistanceMiles = nil
        day.originalEffortLevel = nil
        day.originalTargetDurationMinutes = nil
        day.originalTargetPaceSecPerMile = nil
        day.originalWorkoutTitle = nil
        day.originalCoachingNote = nil
        day.originalStepsData = nil
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
