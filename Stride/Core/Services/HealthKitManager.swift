import Foundation
import HealthKit

// MARK: - DTOs

/// Lightweight data bag for a recent workout used to pre-fill LogWorkoutView.
struct HealthKitWorkoutData {
    let workoutDate: Date
    let distanceMiles: Double
    let durationSeconds: Int
    let averageHeartRate: Double?

    var averagePaceSecPerMile: Int? {
        guard distanceMiles > 0, durationSeconds > 0 else { return nil }
        return Int(Double(durationSeconds) / distanceMiles)
    }
}

/// Full data bag for a historical run — handed to HistoricalRunService for persistence.
struct HistoricalRunImportData {
    let startDate: Date
    let endDate: Date
    let sourceHKUUID: String
    let isIndoorRun: Bool
    let distanceMiles: Double
    let durationSeconds: Double
    let totalCalories: Double?
    let averagePaceSecondsPerMile: Double
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let averageCadenceSPM: Double?
    let averageStrideLengthMeters: Double?
}

// MARK: - HealthKitManager

@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    var isAuthorized = false
    var recentWorkouts: [HealthKitWorkoutData] = []

    private let store = HKHealthStore()

    // iOS 18+ target — all running-dynamics types (added iOS 16) are unconditionally available.
    // Note: HealthKit has no standalone runningCadence quantity type; cadence is derived from stepCount.
    private let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
        HKObjectType.quantityType(forIdentifier: .runningStrideLength)!,
    ]

    private init() {}

    // MARK: - Authorisation

    func requestAuthorisation() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            await fetchRecentWorkouts()
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Fetch Recent Running Workouts (last 7 days, for log pre-fill)

    func fetchRecentWorkouts() async {
        guard isAuthorized else { return }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-7 * 24 * 3600),
            end: Date(),
            options: .strictStartDate
        )
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, workoutPredicate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let results = await withCheckedContinuation { (continuation: CheckedContinuation<[HKWorkout], Never>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: compound,
                limit: 20,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        let workoutData = await withTaskGroup(of: HealthKitWorkoutData?.self) { group in
            for workout in results {
                group.addTask { [weak self] in await self?.mapToRecentData(workout: workout) }
            }
            var collected: [HealthKitWorkoutData] = []
            for await result in group {
                if let data = result { collected.append(data) }
            }
            return collected
        }

        recentWorkouts = workoutData.sorted { $0.workoutDate > $1.workoutDate }
    }

    // MARK: - Match to Workout Day

    func workoutData(for date: Date) -> HealthKitWorkoutData? {
        recentWorkouts.first {
            Calendar.current.isDate($0.workoutDate, inSameDayAs: date)
        }
    }

    // MARK: - Fetch Historical Runs (onboarding import)

    /// Queries all running workouts from the past `months` months.
    /// Returns raw import data — call HistoricalRunService.importIfNeeded to persist.
    func fetchHistoricalRuns(months: Int = 3) async -> [HistoricalRunImportData] {
        guard isAuthorized else { return [] }

        let startDate = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )
        let runPredicate = HKQuery.predicateForWorkouts(with: .running)
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runPredicate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let workouts = await withCheckedContinuation { (continuation: CheckedContinuation<[HKWorkout], Never>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: compound,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        return await withTaskGroup(of: HistoricalRunImportData?.self) { group in
            for workout in workouts {
                group.addTask { [weak self] in await self?.mapToHistoricalRunData(workout: workout) }
            }
            var collected: [HistoricalRunImportData] = []
            for await result in group {
                if let data = result { collected.append(data) }
            }
            return collected.sorted { $0.startDate < $1.startDate }
        }
    }

    // MARK: - Private: Map HKWorkout → HistoricalRunImportData

    private func mapToHistoricalRunData(workout: HKWorkout) async -> HistoricalRunImportData? {
        let distanceMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        guard distanceMiles(from: distanceMeters) > 0 else { return nil }
        let miles = distanceMiles(from: distanceMeters)
        let duration = workout.duration
        let isIndoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false

        // Fetch all associated stats in parallel.
        // Cadence (steps/min) = total steps in workout ÷ duration in minutes —
        // HealthKit has no standalone runningCadence quantity type.
        async let hrStats      = fetchHeartRateStats(for: workout)
        async let totalSteps   = fetchCumulativeStat(for: workout, typeID: .stepCount, unit: .count())
        async let calories     = fetchCumulativeStat(for: workout, typeID: .activeEnergyBurned, unit: .kilocalorie())
        async let speed        = fetchAverageStat(for: workout, typeID: .runningSpeed,
                                                   unit: .meter().unitDivided(by: .second()))
        async let strideLength = fetchAverageStat(for: workout, typeID: .runningStrideLength,
                                                   unit: .meter())

        let (hr, steps, kcal, spd, stride) = await (hrStats, totalSteps, calories, speed, strideLength)

        let durationMinutes = duration / 60.0
        let cad: Double? = steps.map { durationMinutes > 0 ? $0 / durationMinutes : nil } ?? nil

        // Speed (m/s) → seconds per mile; fallback to duration/distance
        let avgPace: Double
        if let spd, spd > 0 {
            avgPace = 1609.34 / spd
        } else {
            avgPace = miles > 0 ? duration / miles : 0
        }

        return HistoricalRunImportData(
            startDate: workout.startDate,
            endDate: workout.endDate,
            sourceHKUUID: workout.uuid.uuidString,
            isIndoorRun: isIndoor,
            distanceMiles: miles,
            durationSeconds: duration,
            totalCalories: kcal,
            averagePaceSecondsPerMile: avgPace,
            averageHeartRate: hr?.average,
            maxHeartRate: hr?.max,
            averageCadenceSPM: cad,
            averageStrideLengthMeters: stride
        )
    }

    // MARK: - Private: Map HKWorkout → HealthKitWorkoutData (recent log pre-fill)

    private func mapToRecentData(workout: HKWorkout) async -> HealthKitWorkoutData? {
        let distanceMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let miles = distanceMiles(from: distanceMeters)
        let heartRate = await fetchAverageHeartRate(for: workout)
        return HealthKitWorkoutData(
            workoutDate: workout.startDate,
            distanceMiles: miles,
            durationSeconds: Int(workout.duration),
            averageHeartRate: heartRate
        )
    }

    // MARK: - Private: Stat Queries

    private typealias HRStats = (average: Double, max: Double)

    /// Fetches average + max heart rate for a workout using predicateForObjects scoping.
    private func fetchHeartRateStats(for workout: HKWorkout) async -> HRStats? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, stats, _ in
                guard let stats,
                      let avg = stats.averageQuantity()?.doubleValue(for: bpmUnit),
                      let max = stats.maximumQuantity()?.doubleValue(for: bpmUnit)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (average: avg, max: max))
            }
            store.execute(query)
        }
    }

    /// Fetches the average value for a quantity type scoped to a specific workout.
    private func fetchAverageStat(
        for workout: HKWorkout,
        typeID: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double? {
        guard let qType = HKQuantityType.quantityType(forIdentifier: typeID) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: qType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Fetches the cumulative sum for a quantity type scoped to a specific workout.
    private func fetchCumulativeStat(
        for workout: HKWorkout,
        typeID: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double? {
        guard let qType = HKQuantityType.quantityType(forIdentifier: typeID) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: qType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Retained for backward compat with mapToRecentData.
    private func fetchAverageHeartRate(for workout: HKWorkout) async -> Double? {
        await fetchHeartRateStats(for: workout).map { $0.average }
    }

    // MARK: - Utilities

    private func distanceMiles(from meters: Double) -> Double {
        meters / 1609.34
    }
}
