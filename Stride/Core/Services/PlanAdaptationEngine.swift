import Foundation
import SwiftData

// MARK: - Plan Adaptation Engine (Simplified)
//
// The engine no longer auto-mutates the plan. It provides:
// 1. Readiness-based adaptation (user-approved only)
// 2. Missed key workout detection (advisory, no plan mutation)

final class PlanAdaptationEngine {

    // MARK: - Readiness Adaptation (user-approved)

    /// Applies a readiness-based adaptation when user accepts the coach recommendation.
    @discardableResult
    func applyReadinessAdaptation(
        workout: WorkoutDay,
        recommendation: ReadinessRecommendation,
        context: ModelContext
    ) -> AdaptationRecord {
        let originalType = workout.workoutType
        let originalDist = workout.targetDistanceMiles
        let originalEffort = workout.effortLevel

        switch recommendation {
        case .sendIt:
            break // no change
        case .dialBack:
            storeOriginals(workout)
            workout.targetDistanceMiles *= 0.80
            workout.adaptationNote = "Distance reduced ~20% based on your readiness check"
            workout.isAdapted = true
        case .swapRecovery:
            storeOriginals(workout)
            applyDowngrade(workout, toType: .recoveryRun, effort: .easy, distanceFactor: 0.5)
            workout.adaptationNote = "Swapped to recovery run — your body needs a lighter effort today"
            workout.isAdapted = true
        case .restToday:
            storeOriginals(workout)
            applyDowngrade(workout, toType: .strengthDay, effort: .easy, distanceFactor: 0)
            workout.adaptationNote = "Converted to strength/mobility — 10-15 min bodyweight routine recommended"
            workout.isAdapted = true
        }

        let adaptationType: AdaptationType = recommendation == .restToday
            ? .strengthSubstituted
            : (recommendation == .swapRecovery ? .recoveryInserted : .downgraded)

        let record = AdaptationRecord(
            adaptationType: adaptationType,
            reason: workout.adaptationNote ?? "Readiness-based adaptation",
            workoutDayID: workout.id,
            originalWorkoutType: originalType,
            originalDistanceMiles: originalDist,
            originalEffortLevel: originalEffort
        )
        context.insert(record)
        try? context.save()
        return record
    }

    /// Reverts an adaptation, restoring original workout values.
    func revertAdaptation(
        record: AdaptationRecord,
        workout: WorkoutDay,
        context: ModelContext
    ) {
        if let origType = workout.originalWorkoutType {
            workout.workoutType = origType
            workout.workoutTitle = titleFor(origType)
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

        record.wasRevertedByUser = true
        try? context.save()
    }

    // MARK: - Helpers

    private func storeOriginals(_ workout: WorkoutDay) {
        guard workout.originalWorkoutType == nil else { return }
        workout.originalWorkoutType = workout.workoutType
        workout.originalTargetDistanceMiles = workout.targetDistanceMiles
        workout.originalEffortLevel = workout.effortLevel
    }

    private func applyDowngrade(
        _ workout: WorkoutDay,
        toType: WorkoutType,
        effort: EffortLevel,
        distanceFactor: Double
    ) {
        workout.workoutType = toType
        workout.effortLevel = effort
        workout.workoutTitle = titleFor(toType)
        if distanceFactor <= 0 {
            workout.targetDistanceMiles = 0
        } else {
            workout.targetDistanceMiles *= distanceFactor
        }
    }

    private func titleFor(_ type: WorkoutType) -> String {
        switch type {
        case .easyRun: return "Easy Run"
        case .longRun: return "Long Run"
        case .tempoRun: return "Tempo Run"
        case .intervalRun: return "Intervals"
        case .recoveryRun: return "Recovery Run"
        case .strengthDay: return "Strength & Mobility"
        case .restDay: return "Rest Day"
        }
    }
}

// MARK: - Coach Recommendation (Advisory Only)

struct CoachRecommendation: Identifiable {
    let id: UUID
    let title: String
    let message: String
    let missedWorkoutType: WorkoutType
    let severity: Severity

    enum Severity {
        case info     // single missed key workout
        case warning  // multiple missed key workouts or extended absence
    }
}

// MARK: - Missed Key Workout Detection

extension PlanAdaptationEngine {

    /// Scans the last 7 days for missed key workouts (long run, tempo, intervals).
    /// Returns an advisory recommendation — does NOT modify the plan.
    func checkForMissedKeyWorkouts(plan: TrainingPlan) -> CoachRecommendation? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: DateProvider.shared.now)
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let planStart = cal.startOfDay(for: plan.generatedAt)

        let missedKeyWorkouts = plan.workoutDays.filter { day in
            let ed = day.effectiveDate
            return ed >= max(sevenDaysAgo, planStart)
                && ed < today
                && day.workoutType.isHard
                && day.isMissed
        }

        guard let firstMissed = missedKeyWorkouts.first else { return nil }

        if missedKeyWorkouts.count >= 2 {
            return CoachRecommendation(
                id: UUID(),
                title: "Missed Key Workouts",
                message: "You missed \(missedKeyWorkouts.count) key workouts this week. If you're dealing with an injury or illness, consider taking a few easy days. Otherwise, just keep going — next week is a fresh start.",
                missedWorkoutType: firstMissed.workoutType,
                severity: .warning
            )
        }

        let missed = firstMissed
        let daysSinceMissed = cal.dateComponents([.day], from: missed.effectiveDate, to: today).day ?? 0

        if missed.workoutType == .longRun {
            if daysSinceMissed <= 3 {
                return CoachRecommendation(
                    id: missed.id,
                    title: "Missed Long Run",
                    message: "Your long run from \(missed.dayOfWeek.displayName) was missed. You could still do it in the next day or two if you're feeling good.",
                    missedWorkoutType: .longRun,
                    severity: .info
                )
            } else {
                return CoachRecommendation(
                    id: missed.id,
                    title: "Missed Long Run",
                    message: "You missed last week's long run. No stress — this week's plan still works. Just focus on this week's key workouts.",
                    missedWorkoutType: .longRun,
                    severity: .info
                )
            }
        }

        return CoachRecommendation(
            id: missed.id,
            title: "Missed \(missed.workoutType.rawValue)",
            message: "Your \(missed.workoutType.rawValue.lowercased()) was missed this week. No stress — focus on completing the remaining key workouts.",
            missedWorkoutType: missed.workoutType,
            severity: .info
        )
    }
}
