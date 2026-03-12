import Foundation
import SwiftData

@Observable
final class ReadyCheckViewModel {

    // MARK: - Input State (sliders)
    var sleepQuality: Int = 3
    var muscleSoreness: Int = 3
    var energyLevel: Int = 3
    var motivation: Int = 3

    // MARK: - HealthKit Sleep
    var sleepData: HealthKitSleepData?
    var isFetchingSleep = false
    var useSleepOverride = false // user disagrees with HK data

    // MARK: - Output
    var result: ReadinessEngine.Result?
    var hasEvaluated = false

    // MARK: - Dependencies
    private let profile: UserProfile
    private let modelContext: ModelContext
    private let engine = ReadinessEngine()
    private let healthKit = HealthKitManager.shared

    init(profile: UserProfile, modelContext: ModelContext) {
        self.profile = profile
        self.modelContext = modelContext
    }

    // MARK: - Sleep Fetch

    func fetchSleepData() async {
        isFetchingSleep = true
        sleepData = await healthKit.fetchLastNightSleep()
        isFetchingSleep = false

        // Auto-map HealthKit sleep hours to the 1-5 slider as a default
        if let data = sleepData {
            sleepQuality = sleepQualityFromHours(data.totalSleepHours)
        }
    }

    // MARK: - Evaluate

    func evaluate() {
        let input = ReadinessEngine.Input(
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            energyLevel: energyLevel,
            motivation: motivation,
            healthKitSleepHours: useSleepOverride ? nil : sleepData?.totalSleepHours,
            healthKitSleepEfficiency: useSleepOverride ? nil : sleepData?.sleepEfficiency,
            yesterdayRPE: yesterdayRPE,
            currentWeekMileage: currentWeekMileage,
            weeklyTargetMileage: weeklyTargetMileage,
            daysToRace: daysToRace,
            trainingPhase: currentTrainingPhase,
            todayWorkoutType: todayWorkout?.workoutType
        )

        result = engine.evaluate(input)
        hasEvaluated = true
    }

    // MARK: - Accept Recommendation

    func accept() {
        guard let result else { return }
        persistCheck(accepted: true)
    }

    /// Accepts the recommendation and applies the adaptation to today's workout.
    func acceptWithAdaptation() {
        guard let result else { return }
        persistCheck(accepted: true)

        guard let workout = todayWorkout, result.recommendation != .sendIt else { return }
        let engine = PlanAdaptationEngine()
        engine.applyReadinessAdaptation(
            workout: workout,
            recommendation: result.recommendation,
            context: modelContext
        )
    }

    /// Accepts the readiness check but keeps the original workout unchanged.
    func acceptWithoutAdaptation() {
        persistCheck(accepted: true)
    }

    private func persistCheck(accepted: Bool) {
        guard let result else { return }

        let check = ReadinessCheck(
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            energyLevel: energyLevel,
            motivation: motivation,
            healthKitSleepHours: sleepData?.totalSleepHours,
            healthKitSleepEfficiency: sleepData?.sleepEfficiency,
            recommendation: result.recommendation,
            readinessScore: result.score
        )
        check.wasAccepted = accepted
        modelContext.insert(check)
        try? modelContext.save()
    }

    // MARK: - Today's Workout

    var todayWorkout: WorkoutDay? {
        profile.activePlan?.workoutDays.first { $0.isToday }
    }

    // MARK: - Private Helpers

    private var yesterdayRPE: Int? {
        guard let plan = profile.activePlan else { return nil }
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))
        return plan.workoutDays
            .first { day in
                guard let yesterday else { return false }
                return cal.isDate(day.effectiveDate, inSameDayAs: yesterday)
            }?
            .log?.effortRating
    }

    private var currentWeekMileage: Double {
        guard let plan = profile.activePlan else { return 0 }
        let cal = Calendar.current
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        return plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate <= Date() }
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +)
    }

    private var weeklyTargetMileage: Double {
        guard let plan = profile.activePlan else { return 0 }
        let cal = Calendar.current
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
        return plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate < weekEnd && $0.workoutType.isRun && !$0.isSkipped }
            .map { $0.targetDistanceMiles }
            .reduce(0, +)
    }

    private var daysToRace: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: profile.raceDate).day ?? 0
        return max(0, days)
    }

    private var currentTrainingPhase: ReadinessEngine.TrainingPhase {
        guard let plan = profile.activePlan else { return .base }
        let totalWeeks = plan.totalWeeks
        let currentWeek = plan.currentWeekNumber

        if daysToRace <= 7 { return .raceWeek }

        let progress = Double(currentWeek) / Double(totalWeeks)
        switch progress {
        case ..<0.3: return .base
        case 0.3..<0.6: return .build
        case 0.6..<0.85: return .peak
        default: return .taper
        }
    }

    private func sleepQualityFromHours(_ hours: Double) -> Int {
        switch hours {
        case ..<5: return 1
        case 5..<6: return 2
        case 6..<7: return 3
        case 7..<8: return 4
        default: return 5
        }
    }

    // MARK: - Display Helpers

    var sleepHoursFormatted: String? {
        guard let hours = sleepData?.totalSleepHours else { return nil }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var sleepEfficiencyFormatted: String? {
        guard let eff = sleepData?.sleepEfficiency else { return nil }
        return "\(Int(eff * 100))%"
    }
}
