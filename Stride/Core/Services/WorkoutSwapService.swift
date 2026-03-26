import Foundation

// MARK: - SwapSnapshot

/// In-memory snapshot of a WorkoutDay's properties before a swap.
/// Used to revert both days if the user cancels the log flow.
struct SwapSnapshot {
    let dayID: UUID
    let workoutType: WorkoutType
    let targetDistanceMiles: Double
    let targetDurationMinutes: Int
    let targetPaceSecPerMile: Int?
    let effortLevel: EffortLevel
    let workoutTitle: String
    let coachingNote: String
    let stepsData: Data?
    let isSwapped: Bool
    let swapNote: String?
    let swapPartnerID: UUID?
}

// MARK: - WorkoutSwapService

final class WorkoutSwapService {

    // MARK: - Available Targets

    /// Returns WorkoutDay objects eligible for swap: past uncompleted (up to 7 days back)
    /// and future (up to 7 days ahead). Excludes the source day, completed, skipped days,
    /// and any days before the plan was generated.
    func availableSwapTargets(for source: WorkoutDay, in plan: TrainingPlan) -> [WorkoutDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: DateProvider.shared.now)
        let planStart = calendar.startOfDay(for: plan.generatedAt)

        guard let windowStart = calendar.date(byAdding: .day, value: -7, to: today),
              let windowEnd = calendar.date(byAdding: .day, value: 7, to: today) else {
            return []
        }

        // Don't show workouts from before the plan was generated
        let effectiveStart = max(windowStart, planStart)

        return plan.workoutDays
            .filter { day in
                guard day.id != source.id else { return false }
                guard !day.isCompleted else { return false }
                guard !day.isSkipped else { return false }

                let effective = calendar.startOfDay(for: day.effectiveDate)
                return effective >= effectiveStart && effective <= windowEnd
            }
            .sorted { $0.effectiveDate < $1.effectiveDate }
    }

    /// Same as `availableSwapTargets` but filtered to run workouts only,
    /// for the strength day "Also Log a Run" picker.
    func availableRunTargets(for source: WorkoutDay, in plan: TrainingPlan) -> [WorkoutDay] {
        availableSwapTargets(for: source, in: plan).filter { $0.workoutType.isRun }
    }

    // MARK: - Snapshot

    func captureSnapshot(_ day: WorkoutDay) -> SwapSnapshot {
        SwapSnapshot(
            dayID: day.id,
            workoutType: day.workoutType,
            targetDistanceMiles: day.targetDistanceMiles,
            targetDurationMinutes: day.targetDurationMinutes,
            targetPaceSecPerMile: day.targetPaceSecPerMile,
            effortLevel: day.effortLevel,
            workoutTitle: day.workoutTitle,
            coachingNote: day.coachingNote,
            stepsData: day.stepsData,
            isSwapped: day.isSwapped,
            swapNote: day.swapNote,
            swapPartnerID: day.swapPartnerID
        )
    }

    func restoreSnapshot(_ snapshot: SwapSnapshot, onto day: WorkoutDay) {
        day.workoutType = snapshot.workoutType
        day.targetDistanceMiles = snapshot.targetDistanceMiles
        day.targetDurationMinutes = snapshot.targetDurationMinutes
        day.targetPaceSecPerMile = snapshot.targetPaceSecPerMile
        day.effortLevel = snapshot.effortLevel
        day.workoutTitle = snapshot.workoutTitle
        day.coachingNote = snapshot.coachingNote
        day.stepsData = snapshot.stepsData
        day.isSwapped = snapshot.isSwapped
        day.swapNote = snapshot.swapNote
        day.swapPartnerID = snapshot.swapPartnerID
    }

    // MARK: - Perform Swap

    /// Swaps workout properties between two days. Returns pre-swap snapshots for both.
    /// Original generator fields are write-once — only set if not already captured.
    func performSwap(_ a: WorkoutDay, _ b: WorkoutDay) -> (SwapSnapshot, SwapSnapshot) {
        let snapA = captureSnapshot(a)
        let snapB = captureSnapshot(b)

        storeOriginals(a)
        storeOriginals(b)

        // Exchange the 8 workout-defining properties
        let tempType = a.workoutType
        let tempDistance = a.targetDistanceMiles
        let tempDuration = a.targetDurationMinutes
        let tempPace = a.targetPaceSecPerMile
        let tempEffort = a.effortLevel
        let tempTitle = a.workoutTitle
        let tempNote = a.coachingNote
        let tempSteps = a.stepsData

        a.workoutType = b.workoutType
        a.targetDistanceMiles = b.targetDistanceMiles
        a.targetDurationMinutes = b.targetDurationMinutes
        a.targetPaceSecPerMile = b.targetPaceSecPerMile
        a.effortLevel = b.effortLevel
        a.workoutTitle = b.workoutTitle
        a.coachingNote = b.coachingNote
        a.stepsData = b.stepsData

        b.workoutType = tempType
        b.targetDistanceMiles = tempDistance
        b.targetDurationMinutes = tempDuration
        b.targetPaceSecPerMile = tempPace
        b.effortLevel = tempEffort
        b.workoutTitle = tempTitle
        b.coachingNote = tempNote
        b.stepsData = tempSteps

        // Mark both as swapped
        a.isSwapped = true
        a.swapPartnerID = b.id
        a.swapNote = swapNoteText(from: snapB)

        b.isSwapped = true
        b.swapPartnerID = a.id
        b.swapNote = swapNoteText(from: snapA)

        // If either day ended up back at its generator-original, clear swap flags
        clearSwapIfRestored(a)
        clearSwapIfRestored(b)

        return (snapA, snapB)
    }

    // MARK: - Consecutive Hard Days Check

    /// Returns true if performing the swap would place hard workouts on consecutive days
    /// for either day involved.
    func wouldCreateConsecutiveHardDays(
        swapping source: WorkoutDay,
        with target: WorkoutDay,
        in plan: TrainingPlan
    ) -> Bool {
        // After swap: source gets target's type, target gets source's type
        let sourcePostSwapType = target.workoutType
        let targetPostSwapType = source.workoutType

        let calendar = Calendar.current
        let allDays = plan.workoutDays

        if sourcePostSwapType.isHard {
            if hasAdjacentHardDay(for: source, excluding: target, postSwapType: sourcePostSwapType, allDays: allDays, calendar: calendar) {
                return true
            }
        }

        if targetPostSwapType.isHard {
            if hasAdjacentHardDay(for: target, excluding: source, postSwapType: targetPostSwapType, allDays: allDays, calendar: calendar) {
                return true
            }
        }

        // Check if source and target are adjacent and both would be hard
        let daysBetween = abs(calendar.dateComponents([.day], from: source.effectiveDate, to: target.effectiveDate).day ?? 0)
        if daysBetween == 1 && sourcePostSwapType.isHard && targetPostSwapType.isHard {
            return true
        }

        return false
    }

    // MARK: - Original Detection

    /// Returns true if the day's current properties match ALL of its generator-original fields.
    func matchesOriginal(_ day: WorkoutDay) -> Bool {
        guard let origType = day.originalWorkoutType else { return false }
        return day.workoutType == origType
            && day.targetDistanceMiles == (day.originalTargetDistanceMiles ?? 0)
            && day.effortLevel == (day.originalEffortLevel ?? .easy)
            && day.targetDurationMinutes == (day.originalTargetDurationMinutes ?? 0)
            && day.targetPaceSecPerMile == day.originalTargetPaceSecPerMile
            && day.workoutTitle == (day.originalWorkoutTitle ?? "")
            && day.coachingNote == (day.originalCoachingNote ?? "")
            && day.stepsData == day.originalStepsData
    }

    /// Returns true if the target's current properties match the source's generator-original fields.
    /// Used in the swap picker to label "Your original workout".
    func isOriginalWorkoutOf(target: WorkoutDay, source: WorkoutDay) -> Bool {
        guard let origType = source.originalWorkoutType else { return false }
        return target.workoutType == origType
            && target.targetDistanceMiles == (source.originalTargetDistanceMiles ?? 0)
            && target.effortLevel == (source.originalEffortLevel ?? .easy)
            && target.targetDurationMinutes == (source.originalTargetDurationMinutes ?? 0)
            && target.targetPaceSecPerMile == source.originalTargetPaceSecPerMile
            && target.workoutTitle == (source.originalWorkoutTitle ?? "")
            && target.coachingNote == (source.originalCoachingNote ?? "")
            && target.stepsData == source.originalStepsData
    }

    // MARK: - Private Helpers

    /// If a day's current properties match its generator-original, clear swap flags.
    private func clearSwapIfRestored(_ day: WorkoutDay) {
        guard matchesOriginal(day) else { return }
        day.isSwapped = false
        day.swapNote = nil
        day.swapPartnerID = nil
    }


    /// Stores generator-original values. Write-once: only sets fields if not already captured.
    private func storeOriginals(_ day: WorkoutDay) {
        guard day.originalWorkoutType == nil else { return }
        day.originalWorkoutType = day.workoutType
        day.originalTargetDistanceMiles = day.targetDistanceMiles
        day.originalEffortLevel = day.effortLevel
        day.originalTargetDurationMinutes = day.targetDurationMinutes
        day.originalTargetPaceSecPerMile = day.targetPaceSecPerMile
        day.originalWorkoutTitle = day.workoutTitle
        day.originalCoachingNote = day.coachingNote
        day.originalStepsData = day.stepsData
    }

    private func swapNoteText(from snapshot: SwapSnapshot) -> String {
        "Swapped with \(snapshot.workoutType.rawValue)"
    }

    private func hasAdjacentHardDay(
        for day: WorkoutDay,
        excluding other: WorkoutDay,
        postSwapType: WorkoutType,
        allDays: [WorkoutDay],
        calendar: Calendar
    ) -> Bool {
        guard postSwapType.isHard else { return false }

        let dayDate = calendar.startOfDay(for: day.effectiveDate)

        for neighbor in allDays {
            guard neighbor.id != day.id, neighbor.id != other.id else { continue }
            guard !neighbor.isCompleted, !neighbor.isSkipped else { continue }
            let neighborDate = calendar.startOfDay(for: neighbor.effectiveDate)
            let diff = abs(calendar.dateComponents([.day], from: dayDate, to: neighborDate).day ?? 0)
            if diff == 1 && neighbor.workoutType.isHard {
                return true
            }
        }

        return false
    }
}
