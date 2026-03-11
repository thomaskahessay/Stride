import Foundation
import SwiftData

/// Orchestrates importing HealthKit historical runs into SwiftData.
/// Handles deduplication and persistence — HealthKitManager owns the HK queries,
/// this service owns the SwiftData side.
final class HistoricalRunService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public

    /// Imports all runs from the past `months` months.
    /// Skips any workout whose HK UUID is already persisted.
    /// Returns the number of newly imported runs.
    @discardableResult
    func importHistoricalRuns(months: Int = 3) async -> Int {
        let importData = await HealthKitManager.shared.fetchHistoricalRuns(months: months)
        guard !importData.isEmpty else { return 0 }

        let existingUUIDs = fetchExistingUUIDs()
        var importCount = 0

        for data in importData {
            guard !existingUUIDs.contains(data.sourceHKUUID) else { continue }
            let run = HistoricalRun(
                startDate: data.startDate,
                endDate: data.endDate,
                sourceHKUUID: data.sourceHKUUID,
                isIndoorRun: data.isIndoorRun,
                distanceMiles: data.distanceMiles,
                durationSeconds: data.durationSeconds,
                totalCalories: data.totalCalories,
                averagePaceSecondsPerMile: data.averagePaceSecondsPerMile,
                averageHeartRate: data.averageHeartRate,
                maxHeartRate: data.maxHeartRate,
                averageCadenceSPM: data.averageCadenceSPM,
                averageStrideLengthMeters: data.averageStrideLengthMeters
            )
            modelContext.insert(run)
            importCount += 1
        }

        if importCount > 0 {
            try? modelContext.save()
        }

        return importCount
    }

    /// Returns all historical runs sorted oldest → newest.
    func allRuns() -> [HistoricalRun] {
        let descriptor = FetchDescriptor<HistoricalRun>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Returns runs for a specific calendar day.
    func runs(on date: Date) -> [HistoricalRun] {
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = #Predicate<HistoricalRun> { run in
            run.date >= start && run.date < end
        }
        let descriptor = FetchDescriptor<HistoricalRun>(predicate: predicate)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Returns the average weekly mileage over the past `weeks` weeks.
    /// Used by TrainingPlanGenerator to seed a more accurate starting mileage.
    func averageWeeklyMileage(over weeks: Int = 4) -> Double {
        guard weeks > 0 else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: Date()) ?? Date()
        let predicate = #Predicate<HistoricalRun> { run in run.date >= cutoff }
        let descriptor = FetchDescriptor<HistoricalRun>(predicate: predicate)
        let recent = (try? modelContext.fetch(descriptor)) ?? []
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.distanceMiles } / Double(weeks)
    }

    /// Persists an already-fetched array of import data, deduplicating by HK UUID.
    /// Called by OnboardingViewModel.complete() with data from the background fetch task.
    func persist(_ importData: [HistoricalRunImportData]) {
        let existingUUIDs = fetchExistingUUIDs()
        var didInsert = false

        for data in importData {
            guard !existingUUIDs.contains(data.sourceHKUUID) else { continue }
            let run = HistoricalRun(
                startDate: data.startDate,
                endDate: data.endDate,
                sourceHKUUID: data.sourceHKUUID,
                isIndoorRun: data.isIndoorRun,
                distanceMiles: data.distanceMiles,
                durationSeconds: data.durationSeconds,
                totalCalories: data.totalCalories,
                averagePaceSecondsPerMile: data.averagePaceSecondsPerMile,
                averageHeartRate: data.averageHeartRate,
                maxHeartRate: data.maxHeartRate,
                averageCadenceSPM: data.averageCadenceSPM,
                averageStrideLengthMeters: data.averageStrideLengthMeters
            )
            modelContext.insert(run)
            didInsert = true
        }

        if didInsert {
            try? modelContext.save()
        }
    }

    // MARK: - Private

    private func fetchExistingUUIDs() -> Set<String> {
        let descriptor = FetchDescriptor<HistoricalRun>()
        let runs = (try? modelContext.fetch(descriptor)) ?? []
        return Set(runs.map { $0.sourceHKUUID })
    }
}
