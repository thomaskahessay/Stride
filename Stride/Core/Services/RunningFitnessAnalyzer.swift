import Foundation

// MARK: - Fitness Analysis Result

struct FitnessAnalysis {
    let averageWeeklyMiles: Double
    let estimatedZone2PaceSecPerMile: Int
    let fitnessLevel: FitnessLevel
    let longestRunMiles: Double
    let runsPerWeek: Double
    let preferredRunDays: [Weekday]
    let likelyLongRunDay: Weekday?
    let likelyRestDays: [Weekday]
    let hasEnoughData: Bool

    /// Human-readable summary of how the fitness level was derived.
    var fitnessExplanation: String {
        let weeklyKm = averageWeeklyMiles * 1.60934
        let paceMin = estimatedZone2PaceSecPerMile / 60
        let paceSec = estimatedZone2PaceSecPerMile % 60
        let pacePerKm = Double(estimatedZone2PaceSecPerMile) / 1.60934
        let kmMin = Int(pacePerKm) / 60
        let kmSec = Int(pacePerKm) % 60

        switch fitnessLevel {
        case .beginner:
            return String(format: "You're running ~%.0f km/week at %d:%02d /km — a solid starting point to build from.", weeklyKm, kmMin, kmSec)
        case .intermediate:
            return String(format: "You're running ~%.0f km/week at %d:%02d /km — that's a solid intermediate base.", weeklyKm, kmMin, kmSec)
        case .advanced:
            return String(format: "You're running ~%.0f km/week at %d:%02d /km — you've got a strong training base.", weeklyKm, kmMin, kmSec)
        }
    }
}

// MARK: - Running Fitness Analyzer

/// Rule-based analyzer that derives fitness metrics from HealthKit historical run data.
/// No CoreML — the data is structured and low-dimensional.
struct RunningFitnessAnalyzer {

    /// Minimum number of runs required for a meaningful analysis.
    static let minimumRunCount = 5

    /// Analyze historical run data and produce a fitness profile.
    func analyze(_ runs: [HistoricalRunImportData]) -> FitnessAnalysis {
        let hasEnoughData = runs.count >= Self.minimumRunCount

        guard hasEnoughData else {
            return FitnessAnalysis(
                averageWeeklyMiles: 0,
                estimatedZone2PaceSecPerMile: 0,
                fitnessLevel: .intermediate,
                longestRunMiles: 0,
                runsPerWeek: 0,
                preferredRunDays: [],
                likelyLongRunDay: nil,
                likelyRestDays: [],
                hasEnoughData: false
            )
        }

        let weeklyMiles = computeAverageWeeklyMiles(runs)
        let zone2Pace = estimateZone2Pace(runs)
        let runsPerWeek = computeRunsPerWeek(runs)
        let longestRun = runs.map(\.distanceMiles).max() ?? 0
        let preferredDays = computePreferredRunDays(runs)
        let longRunDay = computeLikelyLongRunDay(runs)
        let restDays = computeLikelyRestDays(runs)
        let level = classifyFitnessLevel(
            weeklyMiles: weeklyMiles,
            zone2PaceSecPerMile: zone2Pace,
            runsPerWeek: runsPerWeek
        )

        return FitnessAnalysis(
            averageWeeklyMiles: weeklyMiles,
            estimatedZone2PaceSecPerMile: zone2Pace,
            fitnessLevel: level,
            longestRunMiles: longestRun,
            runsPerWeek: runsPerWeek,
            preferredRunDays: preferredDays,
            likelyLongRunDay: longRunDay,
            likelyRestDays: restDays,
            hasEnoughData: true
        )
    }

    // MARK: - Weekly Mileage

    private func computeAverageWeeklyMiles(_ runs: [HistoricalRunImportData]) -> Double {
        guard let earliest = runs.first?.startDate,
              let latest = runs.last?.startDate else { return 0 }

        let totalMiles = runs.reduce(0.0) { $0 + $1.distanceMiles }
        let daySpan = max(1, Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 1)
        let weeks = max(1.0, Double(daySpan) / 7.0)
        return totalMiles / weeks
    }

    // MARK: - Runs Per Week

    private func computeRunsPerWeek(_ runs: [HistoricalRunImportData]) -> Double {
        guard let earliest = runs.first?.startDate,
              let latest = runs.last?.startDate else { return 0 }

        let daySpan = max(1, Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 1)
        let weeks = max(1.0, Double(daySpan) / 7.0)
        return Double(runs.count) / weeks
    }

    // MARK: - Zone 2 Pace Estimation

    /// 1. If HR data on 50%+ of runs → filter runs with avg HR < 150 bpm, take median pace
    /// 2. If limited HR → sort all runs by pace, take median of the slower 60%
    /// 3. Result is sec/mile
    private func estimateZone2Pace(_ runs: [HistoricalRunImportData]) -> Int {
        let runsWithHR = runs.filter { $0.averageHeartRate != nil }
        let hrCoverage = Double(runsWithHR.count) / Double(runs.count)

        if hrCoverage >= 0.5 {
            // Strategy 1: HR-based — filter easy runs (avg HR < 150 bpm), take median pace
            let easyRuns = runsWithHR.filter { ($0.averageHeartRate ?? 200) < 150 }
            if !easyRuns.isEmpty {
                let paces = easyRuns.map(\.averagePaceSecondsPerMile).sorted()
                return Int(median(paces))
            }
        }

        // Strategy 2: Pace-based — take median of the slower 60%
        let allPaces = runs.map(\.averagePaceSecondsPerMile).sorted() // ascending = fastest first
        let slowerCount = max(1, Int(ceil(Double(allPaces.count) * 0.6)))
        let slowerPaces = Array(allPaces.suffix(slowerCount))
        return Int(median(slowerPaces))
    }

    // MARK: - Schedule Detection

    /// Returns the weekdays the runner runs most often, sorted by frequency (most frequent first).
    private func computePreferredRunDays(_ runs: [HistoricalRunImportData]) -> [Weekday] {
        var counts: [Weekday: Int] = [:]
        let calendar = Calendar.current

        for run in runs {
            let weekdayNum = calendar.component(.weekday, from: run.startDate)
            if let day = Weekday(rawValue: weekdayNum) {
                counts[day, default: 0] += 1
            }
        }

        // Return days that have at least 20% of the max day's count
        let maxCount = counts.values.max() ?? 0
        let threshold = max(1, Int(Double(maxCount) * 0.2))

        return counts
            .filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    /// The day of the week with the longest average distance.
    private func computeLikelyLongRunDay(_ runs: [HistoricalRunImportData]) -> Weekday? {
        var totalDistance: [Weekday: Double] = [:]
        var dayCounts: [Weekday: Int] = [:]
        let calendar = Calendar.current

        for run in runs {
            let weekdayNum = calendar.component(.weekday, from: run.startDate)
            if let day = Weekday(rawValue: weekdayNum) {
                totalDistance[day, default: 0] += run.distanceMiles
                dayCounts[day, default: 0] += 1
            }
        }

        let avgDistance = totalDistance.compactMapValues { total -> Double? in
            guard let count = dayCounts.first(where: { $0.key.rawValue == totalDistance.first(where: { $0.value == total })?.key.rawValue })?.value,
                  count > 0 else { return nil }
            return nil
        }

        // Simpler approach: compute average distance per day
        var averages: [(Weekday, Double)] = []
        for (day, total) in totalDistance {
            let count = dayCounts[day] ?? 1
            averages.append((day, total / Double(count)))
        }

        return averages.max(by: { $0.1 < $1.1 })?.0
    }

    /// Days with zero or near-zero runs across the history.
    private func computeLikelyRestDays(_ runs: [HistoricalRunImportData]) -> [Weekday] {
        var counts: [Weekday: Int] = [:]
        let calendar = Calendar.current

        for run in runs {
            let weekdayNum = calendar.component(.weekday, from: run.startDate)
            if let day = Weekday(rawValue: weekdayNum) {
                counts[day, default: 0] += 1
            }
        }

        let maxCount = counts.values.max() ?? 0
        guard maxCount > 0 else { return [] }

        // Days with < 15% of the most popular day's run count are likely rest days
        let threshold = max(1, Int(Double(maxCount) * 0.15))

        return Weekday.allCases.filter { day in
            (counts[day] ?? 0) < threshold
        }
    }

    // MARK: - Fitness Level Classification

    /// Rules:
    /// - Beginner: < 15 km/week OR < 2 runs/week OR pace > 8:00/km
    /// - Intermediate: 15-40 km/week AND 2-4 runs/week AND pace 5:30-8:00/km
    /// - Advanced: > 40 km/week AND 4+ runs/week AND pace < 5:30/km
    private func classifyFitnessLevel(
        weeklyMiles: Double,
        zone2PaceSecPerMile: Int,
        runsPerWeek: Double
    ) -> FitnessLevel {
        let weeklyKm = weeklyMiles * 1.60934
        // Convert sec/mile to sec/km for classification
        let paceSecPerKm = Double(zone2PaceSecPerMile) / 1.60934

        // Beginner thresholds
        if weeklyKm < 15 || runsPerWeek < 2 || paceSecPerKm > 480 { // 8:00/km = 480 sec/km
            return .beginner
        }

        // Advanced thresholds
        if weeklyKm > 40 && runsPerWeek >= 4 && paceSecPerKm < 330 { // 5:30/km = 330 sec/km
            return .advanced
        }

        return .intermediate
    }

    // MARK: - Helpers

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }
}
