import Foundation
import SwiftData

// MARK: - Adaptation Result

struct AdaptationResult {
    let autoApplied: [AdaptationRecord]
    let pendingReadiness: ReadinessRecommendation?
}

// MARK: - Plan Adaptation Engine

final class PlanAdaptationEngine {

    // MARK: - Public API

    /// Runs all evaluation passes and applies objective adaptations (missed/spacing).
    /// Returns records for both auto-applied and pending readiness adaptations.
    func evaluateAndAdapt(
        plan: TrainingPlan,
        profile: UserProfile,
        readinessChecks: [ReadinessCheck],
        context: ModelContext
    ) -> AdaptationResult {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Guard: only run once per calendar day
        if let lastRun = plan.lastAdaptationDate,
           cal.isDate(lastRun, inSameDayAs: today) {
            return AdaptationResult(autoApplied: [], pendingReadiness: nil)
        }

        // Guard: skip if today's workout is already completed
        let todayWorkout = plan.workoutDays.first { cal.isDateInToday($0.effectiveDate) }
        if todayWorkout?.isCompleted == true {
            return AdaptationResult(autoApplied: [], pendingReadiness: nil)
        }

        var records: [AdaptationRecord] = []

        // Pass 1: Missed Workout Assessment
        records.append(contentsOf: passMissedWorkouts(plan: plan, today: today, cal: cal, context: context))

        // Pass 2: Load Spike Prevention
        records.append(contentsOf: passLoadSpikePrevention(plan: plan, today: today, cal: cal, context: context))

        // Pass 3: Hard Effort Spacing
        records.append(contentsOf: passHardEffortSpacing(plan: plan, today: today, cal: cal, context: context))

        // Pass 4: Readiness Integration (user choice — not auto-applied)
        let pendingReadiness = passReadinessIntegration(
            plan: plan,
            readinessChecks: readinessChecks,
            today: today,
            cal: cal
        )

        // Mark adaptation date
        plan.lastAdaptationDate = today
        try? context.save()

        return AdaptationResult(autoApplied: records, pendingReadiness: pendingReadiness)
    }

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
        // Restore original values
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

        // Clear adaptation state
        workout.isAdapted = false
        workout.originalWorkoutType = nil
        workout.originalTargetDistanceMiles = nil
        workout.originalEffortLevel = nil
        workout.adaptationNote = nil

        // Mark record as reverted
        record.wasRevertedByUser = true
        try? context.save()
    }

    // MARK: - Pass 1: Missed Workout Assessment

    private func passMissedWorkouts(
        plan: TrainingPlan,
        today: Date,
        cal: Calendar,
        context: ModelContext
    ) -> [AdaptationRecord] {
        var records: [AdaptationRecord] = []

        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let fourteenDaysAgo = cal.date(byAdding: .day, value: -14, to: today) ?? today

        // Count missed + past-skipped workouts (today guard: exclude today's skipped)
        let trailing7 = plan.workoutDays.filter { day in
            let ed = day.effectiveDate
            return ed >= sevenDaysAgo && ed < today && day.workoutType.isRun
        }

        let trailing14 = plan.workoutDays.filter { day in
            let ed = day.effectiveDate
            return ed >= fourteenDaysAgo && ed < today && day.workoutType.isRun
        }

        let missed7 = trailing7.filter { $0.isMissed || ($0.isSkipped && $0.isPast) }
        let completed14 = trailing14.filter { $0.isCompleted }
        let missedOrSkipped14 = trailing14.filter { $0.isMissed || ($0.isSkipped && $0.isPast) }

        let missedCount7 = missed7.count
        let totalRelevant14 = completed14.count + missedOrSkipped14.count
        let complianceRate = totalRelevant14 > 0
            ? Double(completed14.count) / Double(totalRelevant14)
            : 1.0

        // Get remaining future workouts this week
        let weekEnd = cal.date(byAdding: .day, value: 7, to: today) ?? today
        let remainingThisWeek = plan.workoutDays.filter { day in
            let ed = day.effectiveDate
            return ed >= today && ed < weekEnd && !day.isCompleted && !day.isAdapted
        }

        // Apply rules
        if missedCount7 >= 3 {
            // Hold progression for current + next week, downgrade all remaining hard sessions
            records.append(contentsOf: holdProgression(
                plan: plan, weeksToHold: 2, today: today, cal: cal,
                reason: "3+ workouts missed in 7 days — holding progression for 2 weeks",
                context: context
            ))
            for day in remainingThisWeek where day.workoutType.isHard {
                if let record = downgradeWorkout(
                    day,
                    reason: "Missed \(missedCount7) workouts this week — downgrading to protect recovery",
                    context: context
                ) {
                    records.append(record)
                }
            }
        } else if missedCount7 >= 2 {
            // Downgrade next hard session in remaining week
            if let nextHard = remainingThisWeek.sorted(by: { $0.effectiveDate < $1.effectiveDate })
                .first(where: { $0.workoutType.isHard }) {
                if let record = downgradeWorkout(
                    nextHard,
                    reason: "2 missed workouts this week — next hard session downgraded",
                    context: context
                ) {
                    records.append(record)
                }
            }
        }

        // Compliance < 50% over 14 days
        if complianceRate < 0.50 && totalRelevant14 >= 4 {
            records.append(contentsOf: holdProgression(
                plan: plan, weeksToHold: 2, today: today, cal: cal,
                reason: "Compliance below 50% over 2 weeks — holding progression",
                context: context
            ))
        }

        return records
    }

    // MARK: - Pass 2: Load Spike Prevention

    private func passLoadSpikePrevention(
        plan: TrainingPlan,
        today: Date,
        cal: Calendar,
        context: ModelContext
    ) -> [AdaptationRecord] {
        var records: [AdaptationRecord] = []

        // Get max actual completed mileage from past 2 weeks
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: today) ?? today
        let recentCompleted = plan.workoutDays.filter { day in
            let ed = day.effectiveDate
            return ed >= twoWeeksAgo && ed < today && day.isCompleted
        }

        // Calculate completed weekly mileages for each of the past 2 weeks
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today

        let week1Miles = recentCompleted
            .filter { $0.effectiveDate >= twoWeeksAgo && $0.effectiveDate < oneWeekAgo }
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)
        let week2Miles = recentCompleted
            .filter { $0.effectiveDate >= oneWeekAgo && $0.effectiveDate < today }
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)

        let maxRecentWeekMiles = max(week1Miles, week2Miles)
        guard maxRecentWeekMiles > 0 else { return records }

        // Get upcoming week's planned mileage
        let weekEnd = cal.date(byAdding: .day, value: 7, to: today) ?? today
        let upcomingWeek = plan.workoutDays.filter { day in
            let ed = day.effectiveDate
            return ed >= today && ed < weekEnd && day.workoutType.isRun && !day.isCompleted && !day.isAdapted
        }

        let plannedMileage = upcomingWeek.map(\.targetDistanceMiles).reduce(0, +)
        let maxAllowed = maxRecentWeekMiles * 1.10

        if plannedMileage > maxAllowed && plannedMileage > 0 {
            let reductionFactor = maxAllowed / plannedMileage
            for day in upcomingWeek {
                storeOriginals(day)
                let originalDist = day.targetDistanceMiles
                day.targetDistanceMiles *= reductionFactor
                day.isAdapted = true
                day.adaptationNote = "Distance reduced to prevent >10% weekly mileage increase"

                let record = AdaptationRecord(
                    adaptationType: .progressionHeld,
                    reason: "Weekly mileage capped at 10% increase over recent weeks",
                    workoutDayID: day.id,
                    originalWorkoutType: day.workoutType,
                    originalDistanceMiles: originalDist,
                    originalEffortLevel: day.effortLevel
                )
                context.insert(record)
                records.append(record)
            }
        }

        // Long run guard: cap if next long run > 10% beyond longest completed run in 30 days
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: today) ?? today
        let longestRecentRun = plan.workoutDays
            .filter { $0.effectiveDate >= thirtyDaysAgo && $0.effectiveDate < today && $0.isCompleted }
            .compactMap { $0.log?.actualDistanceMiles }
            .max() ?? 0

        if longestRecentRun > 0 {
            let maxLongRun = longestRecentRun * 1.10
            for day in upcomingWeek where day.workoutType == .longRun && day.targetDistanceMiles > maxLongRun && !day.isAdapted {
                storeOriginals(day)
                let originalDist = day.targetDistanceMiles
                day.targetDistanceMiles = maxLongRun
                day.isAdapted = true
                day.adaptationNote = "Long run capped — no more than 10% beyond your longest recent run"

                let record = AdaptationRecord(
                    adaptationType: .progressionHeld,
                    reason: "Long run distance capped at 10% over recent longest run (\(String(format: "%.1f", longestRecentRun)) mi)",
                    workoutDayID: day.id,
                    originalWorkoutType: day.workoutType,
                    originalDistanceMiles: originalDist,
                    originalEffortLevel: day.effortLevel
                )
                context.insert(record)
                records.append(record)
            }
        }

        return records
    }

    // MARK: - Pass 3: Hard Effort Spacing

    private func passHardEffortSpacing(
        plan: TrainingPlan,
        today: Date,
        cal: Calendar,
        context: ModelContext
    ) -> [AdaptationRecord] {
        var records: [AdaptationRecord] = []

        let weekEnd = cal.date(byAdding: .day, value: 7, to: today) ?? today
        var upcoming = plan.workoutDays
            .filter { $0.effectiveDate >= today && $0.effectiveDate < weekEnd && !$0.isCompleted }
            .sorted { $0.effectiveDate < $1.effectiveDate }

        // Scan for consecutive hard days
        var changed = true
        var iterations = 0
        while changed && iterations < 5 {
            changed = false
            iterations += 1

            for i in 0..<(upcoming.count - 1) {
                let current = upcoming[i]
                let next = upcoming[i + 1]

                guard current.workoutType.isHard && next.workoutType.isHard else { continue }
                guard !current.isAdapted || !next.isAdapted else { continue }

                // Determine which is the consecutive day
                let daysBetween = cal.dateComponents([.day], from: current.effectiveDate, to: next.effectiveDate).day ?? 0
                guard daysBetween <= 1 else { continue }

                // Determine which to downgrade: protect long run > tempo > interval
                let toDowngrade = hardPriority(current.workoutType) <= hardPriority(next.workoutType) ? next : current

                guard !toDowngrade.isAdapted else { continue }

                if let record = downgradeWorkout(
                    toDowngrade,
                    reason: "Back-to-back hard days — downgraded to protect recovery",
                    context: context
                ) {
                    records.append(record)
                    changed = true
                    // Re-fetch state
                    upcoming = plan.workoutDays
                        .filter { $0.effectiveDate >= today && $0.effectiveDate < weekEnd && !$0.isCompleted }
                        .sorted { $0.effectiveDate < $1.effectiveDate }
                    break
                }
            }
        }

        return records
    }

    // MARK: - Pass 4: Readiness Integration

    private func passReadinessIntegration(
        plan: TrainingPlan,
        readinessChecks: [ReadinessCheck],
        today: Date,
        cal: Calendar
    ) -> ReadinessRecommendation? {
        // Find today's readiness check
        guard let todayCheck = readinessChecks.first(where: {
            cal.isDate($0.date, inSameDayAs: today) && $0.wasAccepted
        }) else {
            return nil
        }

        let recommendation = todayCheck.recommendation
        guard recommendation != .sendIt else { return nil }

        // Check if today's workout is eligible for adaptation
        guard let todayWorkout = plan.workoutDays.first(where: { cal.isDateInToday($0.effectiveDate) }),
              !todayWorkout.isCompleted,
              !todayWorkout.isAdapted,
              todayWorkout.workoutType != .restDay else {
            return nil
        }

        return recommendation
    }

    // MARK: - Downgrade Logic

    /// Applies a level-1 downgrade to a workout. Returns an AdaptationRecord if changed.
    private func downgradeWorkout(
        _ workout: WorkoutDay,
        reason: String,
        context: ModelContext
    ) -> AdaptationRecord? {
        guard !workout.isAdapted else { return nil }

        let originalType = workout.workoutType
        let originalDist = workout.targetDistanceMiles
        let originalEffort = workout.effortLevel

        storeOriginals(workout)

        switch workout.workoutType {
        case .intervalRun:
            applyDowngrade(workout, toType: .tempoRun, effort: .moderate, distanceFactor: 1.0)
        case .tempoRun:
            applyDowngrade(workout, toType: .easyRun, effort: .easy, distanceFactor: 1.0)
        case .longRun:
            workout.targetDistanceMiles *= 0.85
            workout.effortLevel = .easy
        case .easyRun:
            applyDowngrade(workout, toType: .recoveryRun, effort: .easy, distanceFactor: 0.80)
        case .recoveryRun:
            // Level 2: convert to strength/mobility (Pass 5 integrated)
            applyDowngrade(workout, toType: .strengthDay, effort: .easy, distanceFactor: 0)
            workout.adaptationNote = (reason + " — 10-15 min bodyweight routine recommended")
        default:
            return nil
        }

        workout.isAdapted = true
        if workout.adaptationNote == nil {
            workout.adaptationNote = reason
        }

        let adaptationType: AdaptationType
        if workout.workoutType == .strengthDay {
            adaptationType = .strengthSubstituted
        } else if workout.workoutType == .recoveryRun && originalType != .recoveryRun {
            adaptationType = .recoveryInserted
        } else {
            adaptationType = .downgraded
        }

        let record = AdaptationRecord(
            adaptationType: adaptationType,
            reason: reason,
            workoutDayID: workout.id,
            originalWorkoutType: originalType,
            originalDistanceMiles: originalDist,
            originalEffortLevel: originalEffort
        )
        context.insert(record)
        return record
    }

    // MARK: - Progression Hold

    private func holdProgression(
        plan: TrainingPlan,
        weeksToHold: Int,
        today: Date,
        cal: Calendar,
        reason: String,
        context: ModelContext
    ) -> [AdaptationRecord] {
        var records: [AdaptationRecord] = []

        // Find max completed weekly mileage from past 2 weeks
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: today) ?? today
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today

        let week1Miles = plan.workoutDays
            .filter { $0.effectiveDate >= twoWeeksAgo && $0.effectiveDate < oneWeekAgo && $0.isCompleted }
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)
        let week2Miles = plan.workoutDays
            .filter { $0.effectiveDate >= oneWeekAgo && $0.effectiveDate < today && $0.isCompleted }
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)

        let capMileage = max(week1Miles, week2Miles)
        guard capMileage > 0 else { return records }

        // Apply cap to the next N weeks
        let holdEnd = cal.date(byAdding: .day, value: weeksToHold * 7, to: today) ?? today
        let upcomingWeeks = plan.workoutDays.filter { day in
            let ed = day.effectiveDate
            return ed >= today && ed < holdEnd && day.workoutType.isRun && !day.isCompleted && !day.isAdapted
        }

        // Group by week and cap each week's total at capMileage
        let grouped = Dictionary(grouping: upcomingWeeks) { $0.weekNumber }
        for (_, weekDays) in grouped {
            let weekTotal = weekDays.map(\.targetDistanceMiles).reduce(0, +)
            guard weekTotal > capMileage else { continue }

            let factor = capMileage / weekTotal
            for day in weekDays {
                storeOriginals(day)
                let originalDist = day.targetDistanceMiles
                day.targetDistanceMiles *= factor
                day.isAdapted = true
                day.adaptationNote = reason

                let record = AdaptationRecord(
                    adaptationType: .progressionHeld,
                    reason: reason,
                    workoutDayID: day.id,
                    originalWorkoutType: day.workoutType,
                    originalDistanceMiles: originalDist,
                    originalEffortLevel: day.effortLevel
                )
                context.insert(record)
                records.append(record)
            }
        }

        return records
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

    /// Priority for hard workout protection: lower = higher priority (protected).
    private func hardPriority(_ type: WorkoutType) -> Int {
        switch type {
        case .longRun: return 1
        case .tempoRun: return 2
        case .intervalRun: return 3
        default: return 4
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
