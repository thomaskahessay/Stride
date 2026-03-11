import Foundation
import SwiftData

/// Aggregated stats from imported HealthKit runs.
struct HistoricalSummary {
    let totalRuns: Int
    let totalMiles: Double
    let avgWeeklyMiles: Double
    let avgPaceSecondsPerMile: Double
    let longestRunMiles: Double
    let longestRunDate: Date?
    let earliestDate: Date

    func formattedAvgPace(units: UnitSystem) -> String {
        let paceSeconds = units == .miles
            ? avgPaceSecondsPerMile
            : avgPaceSecondsPerMile / 1.60934
        let total = Int(paceSeconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d /%@", mins, secs, units.shortLabel)
    }
}

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

    /// Returns weekly mileage totals grouped by ISO week, sorted oldest → newest.
    /// Used by StatsView to show pre-plan mileage in the chart.
    func weeklyMileageBreakdown(weeks: Int = 12) -> [(weekStart: Date, miles: Double)] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .weekOfYear, value: -weeks, to: Date()) else { return [] }

        let predicate = #Predicate<HistoricalRun> { run in run.date >= cutoff }
        let descriptor = FetchDescriptor<HistoricalRun>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let runs = (try? modelContext.fetch(descriptor)) ?? []
        guard !runs.isEmpty else { return [] }

        // Group runs by the Monday of their week
        var buckets: [Date: Double] = [:]
        for run in runs {
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: run.date)) ?? run.date
            buckets[weekStart, default: 0] += run.distanceMiles
        }

        return buckets.sorted { $0.key < $1.key }.map { (weekStart: $0.key, miles: $0.value) }
    }

    /// Returns summary stats for all historical runs (for the "Your Running History" card).
    func historicalSummary() -> HistoricalSummary? {
        let runs = allRuns()
        guard !runs.isEmpty else { return nil }

        let totalMiles = runs.reduce(0) { $0 + $1.distanceMiles }
        let longestRun = runs.max(by: { $0.distanceMiles < $1.distanceMiles })
        let totalPaceSum = runs.reduce(0.0) { $0 + $1.averagePaceSecondsPerMile }
        let avgPace = totalPaceSum / Double(runs.count)

        // Weeks spanned
        let cal = Calendar.current
        if let earliest = runs.first?.date, let latest = runs.last?.date {
            let weeksSpanned = max(1, (cal.dateComponents([.weekOfYear], from: earliest, to: latest).weekOfYear ?? 0) + 1)
            let avgWeeklyMiles = totalMiles / Double(weeksSpanned)

            return HistoricalSummary(
                totalRuns: runs.count,
                totalMiles: totalMiles,
                avgWeeklyMiles: avgWeeklyMiles,
                avgPaceSecondsPerMile: avgPace,
                longestRunMiles: longestRun?.distanceMiles ?? 0,
                longestRunDate: longestRun?.date,
                earliestDate: earliest
            )
        }

        return nil
    }

    // MARK: - Private

    private func fetchExistingUUIDs() -> Set<String> {
        let descriptor = FetchDescriptor<HistoricalRun>()
        let runs = (try? modelContext.fetch(descriptor)) ?? []
        return Set(runs.map { $0.sourceHKUUID })
    }
}
