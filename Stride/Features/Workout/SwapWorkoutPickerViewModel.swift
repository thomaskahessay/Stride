import Foundation

// MARK: - SwapWorkoutPickerViewModel

@Observable
final class SwapWorkoutPickerViewModel {
    let source: WorkoutDay
    let plan: TrainingPlan
    let showCustomRunOption: Bool
    var availableTargets: [WorkoutDay]
    var showConsecutiveHardWarning = false
    var pendingTarget: WorkoutDay?

    private let swapService = WorkoutSwapService()

    init(source: WorkoutDay, plan: TrainingPlan, runOnly: Bool = false, showCustomRunOption: Bool = false) {
        self.source = source
        self.plan = plan
        self.showCustomRunOption = showCustomRunOption
        if runOnly {
            self.availableTargets = swapService.availableRunTargets(for: source, in: plan)
        } else {
            self.availableTargets = swapService.availableSwapTargets(for: source, in: plan)
        }
    }

    /// Attempts to select a swap target. Returns snapshots if swap proceeds,
    /// or nil if a warning is shown (user must confirm via `confirmHardDaySwap`).
    func selectTarget(_ target: WorkoutDay) -> (source: SwapSnapshot, target: SwapSnapshot)? {
        if swapService.wouldCreateConsecutiveHardDays(swapping: source, with: target, in: plan) {
            pendingTarget = target
            showConsecutiveHardWarning = true
            return nil
        }
        let (snapA, snapB) = swapService.performSwap(source, target)
        return (source: snapA, target: snapB)
    }

    /// Returns true if the target currently holds the source day's original planned workout.
    func isOriginalWorkout(_ target: WorkoutDay) -> Bool {
        swapService.isOriginalWorkoutOf(target: target, source: source)
    }

    /// Proceeds with the swap after the user confirms the consecutive hard day warning.
    /// Returns snapshots and the target day that was swapped.
    func confirmHardDaySwap() -> (source: SwapSnapshot, target: SwapSnapshot, targetDay: WorkoutDay)? {
        guard let target = pendingTarget else { return nil }
        pendingTarget = nil
        showConsecutiveHardWarning = false
        let (snapA, snapB) = swapService.performSwap(source, target)
        return (source: snapA, target: snapB, targetDay: target)
    }

    /// Cancels the pending hard day swap warning.
    func cancelHardDayWarning() {
        pendingTarget = nil
        showConsecutiveHardWarning = false
    }
}
