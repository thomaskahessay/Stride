import Foundation

/// Computes a readiness score and recommendation from self-reported inputs,
/// optional HealthKit sleep data, and training context.
final class ReadinessEngine {

    struct Input {
        // Self-reported (1-5 scale, 5 = best)
        let sleepQuality: Int
        let muscleSoreness: Int   // 1 = very sore, 5 = fresh
        let energyLevel: Int
        let motivation: Int

        // HealthKit sleep (nil if unavailable)
        let healthKitSleepHours: Double?
        let healthKitSleepEfficiency: Double?

        // Training context
        let yesterdayRPE: Int?           // 1-10 from last logged workout
        let currentWeekMileage: Double   // miles logged so far this week
        let weeklyTargetMileage: Double  // planned miles for the week
        let daysToRace: Int
        let trainingPhase: TrainingPhase
        let todayWorkoutType: WorkoutType?
    }

    enum TrainingPhase {
        case base
        case build
        case peak
        case taper
        case raceWeek
    }

    struct Result {
        let score: Double                          // 0-100
        let recommendation: ReadinessRecommendation
    }

    // MARK: - Weights

    // When HealthKit sleep data is available, we weight it more heavily than self-reported sleep.
    private static let weightSleep: Double = 0.30
    private static let weightSoreness: Double = 0.25
    private static let weightEnergy: Double = 0.25
    private static let weightMotivation: Double = 0.20

    // MARK: - Public API

    func evaluate(_ input: Input) -> Result {
        // 1. Compute base score from self-reported metrics (each 1-5 → normalised 0-100)
        let sleepScore = computeSleepScore(input: input)
        let sorenessScore = Double(input.muscleSoreness - 1) * 25.0
        let energyScore = Double(input.energyLevel - 1) * 25.0
        let motivationScore = Double(input.motivation - 1) * 25.0

        var composite = sleepScore * Self.weightSleep
            + sorenessScore * Self.weightSoreness
            + energyScore * Self.weightEnergy
            + motivationScore * Self.weightMotivation

        // 2. Apply contextual modifiers
        composite += yesterdayLoadModifier(rpe: input.yesterdayRPE)
        composite += weeklyLoadModifier(logged: input.currentWeekMileage, target: input.weeklyTargetMileage)
        composite += phaseModifier(phase: input.trainingPhase)

        // 3. Clamp to 0-100
        let finalScore = min(100, max(0, composite))

        // 4. Map to recommendation
        let recommendation = recommend(score: finalScore, input: input)

        return Result(score: finalScore, recommendation: recommendation)
    }

    // MARK: - Sleep Score

    /// Blends HealthKit objective data with self-reported quality.
    /// If HealthKit data is available, it gets 60% weight; self-report gets 40%.
    private func computeSleepScore(input: Input) -> Double {
        let selfReportScore = Double(input.sleepQuality - 1) * 25.0

        guard let hkHours = input.healthKitSleepHours else {
            return selfReportScore
        }

        // Score HealthKit sleep hours: < 5h = 0, 5h = 25, 6h = 50, 7h = 75, 8h+ = 100
        let hoursScore = min(100, max(0, (hkHours - 5.0) * 33.3))

        // Factor in sleep efficiency if available
        let efficiencyBonus: Double
        if let eff = input.healthKitSleepEfficiency {
            // Efficiency > 85% is good, < 75% is poor
            efficiencyBonus = min(10, max(-10, (eff - 0.80) * 100))
        } else {
            efficiencyBonus = 0
        }

        let hkScore = min(100, max(0, hoursScore + efficiencyBonus))

        // Blend: 60% objective, 40% subjective
        return hkScore * 0.6 + selfReportScore * 0.4
    }

    // MARK: - Contextual Modifiers

    /// If yesterday's workout was very hard (RPE 8+), penalise readiness slightly.
    private func yesterdayLoadModifier(rpe: Int?) -> Double {
        guard let rpe else { return 0 }
        switch rpe {
        case 9...10: return -8
        case 8: return -4
        case 1...3: return 3 // easy day yesterday = slight recovery bonus
        default: return 0
        }
    }

    /// If already over target mileage for the week, nudge toward rest.
    private func weeklyLoadModifier(logged: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        let ratio = logged / target
        if ratio > 1.0 { return -6 }
        if ratio > 0.85 { return -2 }
        return 0
    }

    /// During taper and race week, bias toward rest/recovery.
    private func phaseModifier(phase: TrainingPhase) -> Double {
        switch phase {
        case .taper: return 5     // slight boost — taper should feel good
        case .raceWeek: return -5 // conservative — protect for race day
        case .peak: return -3     // peak weeks are stressful, be cautious
        default: return 0
        }
    }

    // MARK: - Recommendation

    private func recommend(score: Double, input: Input) -> ReadinessRecommendation {
        // Rest days don't need a recommendation — but if someone opens Ready Check
        // on a rest day, confirm the rest.
        if input.todayWorkoutType == .restDay {
            return score < 30 ? .restToday : .sendIt
        }

        // Hard workouts (tempo, intervals) require higher readiness
        let isHardWorkout = input.todayWorkoutType == .tempoRun || input.todayWorkoutType == .intervalRun
        let threshold = isHardWorkout ? 10.0 : 0.0

        switch score {
        case (70 + threshold)...: return .sendIt
        case (45 + threshold)..<(70 + threshold): return .dialBack
        case (25 + threshold)..<(45 + threshold): return .swapRecovery
        default: return .restToday
        }
    }
}
