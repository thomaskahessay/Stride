import Foundation

/// Implements the Riegel formula for race finish time projection.
/// T2 = T1 × (D2 / D1)^1.06
final class FinishTimeEstimator {

    /// Project a finish time for a target race from a known time trial result.
    /// - Parameters:
    ///   - knownTime: `RaceTime` from the user's recent race
    ///   - targetRace: The race type to project toward
    /// - Returns: Projected finish time in seconds, or nil if inputs are invalid
    func projectedTime(from knownTime: RaceTime, for targetRace: RaceType) -> Int? {
        let t1 = Double(knownTime.finishTimeSeconds)
        let d1 = knownTime.raceDistance.distanceMiles
        let d2 = targetRace.distanceMiles

        guard t1 > 0, d1 > 0, d2 > 0 else { return nil }

        let t2 = t1 * pow(d2 / d1, 1.06)
        return Int(t2)
    }

    /// Format a time in seconds to a human-readable string (e.g. "4h 31m" or "28:05")
    func formatted(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    /// Average pace per mile for a given finish time and distance
    func pacePerMile(totalSeconds: Int, distanceMiles: Double) -> String {
        guard distanceMiles > 0 else { return "--:--" }
        let secondsPerMile = Double(totalSeconds) / distanceMiles
        let minutes = Int(secondsPerMile) / 60
        let seconds = Int(secondsPerMile) % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    /// Projects a finish time from a raw distance/time pair (not tied to a standard race distance).
    /// Used for longest-run fallback where the distance is arbitrary.
    func projectedTime(fromDistanceMiles: Double, durationSeconds: Double, for targetRace: RaceType) -> Int? {
        let d2 = targetRace.distanceMiles
        guard fromDistanceMiles > 0, durationSeconds > 0, d2 > 0 else { return nil }
        let t2 = durationSeconds * pow(d2 / fromDistanceMiles, 1.06)
        return Int(t2)
    }

    /// Tiered historical estimate:
    /// 1. Race-distance match (most accurate) → returns `.raceMatch`
    /// 2. Longest run fallback (rough estimate) → returns `.longestRun`
    /// 3. No usable data → returns nil
    func bestHistoricalEstimate(from runs: [HistoricalRun]) -> HistoricalEstimate? {
        // Tier 1: Race-distance match
        let candidates: [(race: RaceType, tolerance: Double)] = [
            (.fiveK, 0.3),
            (.tenK, 0.5),
            (.halfMarathon, 0.8)
        ]

        for candidate in candidates {
            let target = candidate.race.distanceMiles
            let matches = runs.filter {
                abs($0.distanceMiles - target) <= candidate.tolerance && $0.durationSeconds > 0
            }
            if let best = matches.min(by: { $0.durationSeconds < $1.durationSeconds }) {
                return .raceMatch(RaceTime(
                    raceDistance: candidate.race,
                    finishTimeSeconds: Int(best.durationSeconds),
                    raceDate: best.date
                ))
            }
        }

        // Tier 2: Longest run (minimum 2 miles to be meaningful)
        let validRuns = runs.filter { $0.distanceMiles >= 2.0 && $0.durationSeconds > 0 }
        if let longest = validRuns.max(by: { $0.distanceMiles < $1.distanceMiles }) {
            return .longestRun(
                distanceMiles: longest.distanceMiles,
                durationSeconds: longest.durationSeconds,
                date: longest.date
            )
        }

        return nil
    }

    /// Source label shown beneath the projected time
    func sourceLabel(for raceTime: RaceTime, fromHealthKit: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let base = "Based on your \(raceTime.raceDistance.displayName) on \(formatter.string(from: raceTime.raceDate))"
        return fromHealthKit ? "\(base) (from Apple Health)" : base
    }
}

/// Result of searching historical runs for a projection source.
enum HistoricalEstimate {
    /// Found a run matching a standard race distance — most accurate.
    case raceMatch(RaceTime)
    /// No race match; using the longest run as a rough estimate.
    case longestRun(distanceMiles: Double, durationSeconds: Double, date: Date)
}

// MARK: - Cumulative Projection Types

/// A single run normalised for projection input — source-agnostic.
struct QualifyingRun {
    let date: Date
    let distanceMiles: Double
    let durationSeconds: Double
    let rpe: Int?  // nil for historical runs (no RPE data)
}

/// Confidence level of a cumulative projection.
enum ProjectionConfidence: String {
    case early    = "Early Estimate"
    case building = "Building Confidence"
    case strong   = "Strong Estimate"
}

/// A projected finish time for a single calendar week.
struct WeeklyProjection: Identifiable {
    let id: Int           // sequential index
    let weekStart: Date
    let projectedSeconds: Int
}

/// Rich projection result from cumulative training data.
struct CumulativeProjection {
    let projectedSeconds: Int
    let optimisticSeconds: Int       // 10th percentile (faster)
    let pessimisticSeconds: Int      // 90th percentile (slower)
    let confidence: ProjectionConfidence
    let qualifyingRunCount: Int
    let latestDataDate: Date
    let weeklyTrend: [WeeklyProjection]
}

// MARK: - QualifyingRun Builders

extension FinishTimeEstimator {

    /// Extract qualifying runs from completed plan workouts.
    static func qualifyingRuns(from workoutDays: [WorkoutDay]) -> [QualifyingRun] {
        workoutDays.compactMap { workout -> QualifyingRun? in
            guard workout.workoutType.isRun,
                  let log = workout.log,
                  log.actualDistanceMiles > 0,
                  log.actualDurationSeconds > 0 else { return nil }
            return QualifyingRun(
                date: workout.effectiveDate,
                distanceMiles: log.actualDistanceMiles,
                durationSeconds: Double(log.actualDurationSeconds),
                rpe: log.effortRating
            )
        }
    }

    /// Extract qualifying runs from HealthKit historical imports.
    static func qualifyingRuns(from historicalRuns: [HistoricalRun]) -> [QualifyingRun] {
        historicalRuns.compactMap { run -> QualifyingRun? in
            guard run.distanceMiles > 0, run.durationSeconds > 0 else { return nil }
            return QualifyingRun(
                date: run.date,
                distanceMiles: run.distanceMiles,
                durationSeconds: run.durationSeconds,
                rpe: nil
            )
        }
    }
}

// MARK: - Cumulative Projection Algorithm

/// Internal type for weighted projection data points.
private struct WeightedPoint {
    let projectedSeconds: Int
    let weight: Double
    let date: Date
}

extension FinishTimeEstimator {

    /// Produce a weighted, cumulative finish time projection from all available training data.
    ///
    /// Blends plan workout logs, historical HealthKit runs, and an optional manual race time.
    /// Returns nil only when there are zero usable data points.
    func cumulativeProjection(
        planLogs: [QualifyingRun],
        historicalRuns: [QualifyingRun],
        manualRaceTime: RaceTime?,
        targetRace: RaceType
    ) -> CumulativeProjection? {
        let today = DateProvider.shared.now
        let cal = Calendar.current

        // 1. Merge and apply basic filters
        var allRuns = planLogs + historicalRuns
        allRuns = allRuns.filter { $0.distanceMiles >= 1.5 }
        allRuns = allRuns.filter { run in
            // Exclude recovery jogs (RPE 1-3) from plan logs
            if let rpe = run.rpe, rpe <= 3 { return false }
            return true
        }

        // Compute average pace to filter outliers
        let paces = allRuns.map { $0.durationSeconds / $0.distanceMiles }
        let avgPace: Double
        if paces.isEmpty {
            avgPace = 0
        } else {
            avgPace = paces.reduce(0, +) / Double(paces.count)
        }

        if avgPace > 0 {
            allRuns = allRuns.filter { run in
                let pace = run.durationSeconds / run.distanceMiles
                return pace >= avgPace * 0.5 && pace <= avgPace * 2.0
            }
        }

        // 2. Build weighted projections
        var points: [WeightedPoint] = []

        for run in allRuns {
            guard let projected = projectedTime(
                fromDistanceMiles: run.distanceMiles,
                durationSeconds: run.durationSeconds,
                for: targetRace
            ) else { continue }

            let daysAgo = max(0, Double(cal.dateComponents([.day], from: run.date, to: today).day ?? 0))
            let recencyWeight = exp(-daysAgo / 28.0)
            let distanceWeight = min(1.0, run.distanceMiles / (targetRace.distanceMiles * 0.5))
            let totalWeight = recencyWeight * distanceWeight

            points.append(WeightedPoint(
                projectedSeconds: projected,
                weight: totalWeight,
                date: run.date
            ))
        }

        // 3. Blend manual race time (3x weight multiplier)
        if let manual = manualRaceTime,
           let projected = projectedTime(from: manual, for: targetRace) {
            let daysAgo = max(0, Double(cal.dateComponents([.day], from: manual.raceDate, to: today).day ?? 0))
            let recencyWeight = exp(-daysAgo / 28.0)
            points.append(WeightedPoint(
                projectedSeconds: projected,
                weight: 3.0 * recencyWeight,
                date: manual.raceDate
            ))
        }

        guard !points.isEmpty else { return nil }

        // 4. Weighted average
        let totalWeight = points.reduce(0.0) { $0 + $1.weight }
        let weightedSum = points.reduce(0.0) { $0 + Double($1.projectedSeconds) * $1.weight }
        let projectedSeconds = Int(weightedSum / totalWeight)

        // 5. Percentiles (optimistic = 10th, pessimistic = 90th)
        let sorted = points.sorted { $0.projectedSeconds < $1.projectedSeconds }
        let optimisticSeconds = weightedPercentile(sorted, percentile: 0.10, totalWeight: totalWeight)
        let pessimisticSeconds = weightedPercentile(sorted, percentile: 0.90, totalWeight: totalWeight)

        // 6. Confidence
        let runCount = allRuns.count  // excludes manual race time from count
        let hasLongRun = allRuns.contains { $0.distanceMiles > targetRace.distanceMiles * 0.5 }
        let confidence: ProjectionConfidence
        if runCount >= 15 && hasLongRun {
            confidence = .strong
        } else if runCount >= 5 {
            confidence = .building
        } else {
            confidence = .early
        }

        // 7. Latest data date
        let latestDate = points.map(\.date).max() ?? today

        // 8. Weekly trend — cumulative projection at each calendar week
        let weeklyTrend = buildWeeklyTrend(allRuns: allRuns, manualRaceTime: manualRaceTime, targetRace: targetRace)

        return CumulativeProjection(
            projectedSeconds: projectedSeconds,
            optimisticSeconds: optimisticSeconds,
            pessimisticSeconds: pessimisticSeconds,
            confidence: confidence,
            qualifyingRunCount: runCount,
            latestDataDate: latestDate,
            weeklyTrend: weeklyTrend
        )
    }

    // MARK: - Private Helpers

    /// Compute a weighted percentile from sorted weighted points.
    private func weightedPercentile(
        _ sorted: [WeightedPoint],
        percentile: Double,
        totalWeight: Double
    ) -> Int {
        let target = percentile * totalWeight
        var accumulated = 0.0
        for point in sorted {
            accumulated += point.weight
            if accumulated >= target {
                return point.projectedSeconds
            }
        }
        return sorted.last?.projectedSeconds ?? 0
    }

    /// Build weekly trend: for each calendar week with data, compute cumulative weighted projection.
    private func buildWeeklyTrend(
        allRuns: [QualifyingRun],
        manualRaceTime: RaceTime?,
        targetRace: RaceType
    ) -> [WeeklyProjection] {
        let cal = Calendar.current
        guard !allRuns.isEmpty else { return [] }

        // Group runs by calendar week
        let sortedRuns = allRuns.sorted { $0.date < $1.date }

        // Collect unique week starts
        var weekStarts: [Date] = []
        var seen = Set<Int>()
        for run in sortedRuns {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: run.date)
            let hash = (comps.yearForWeekOfYear ?? 0) * 100 + (comps.weekOfYear ?? 0)
            if seen.insert(hash).inserted {
                let weekStart = cal.date(from: comps) ?? run.date
                weekStarts.append(weekStart)
            }
        }

        // For each week, compute projection using all runs up to end of that week
        var trend: [WeeklyProjection] = []
        for (index, weekStart) in weekStarts.enumerated() {
            let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
            let runsUpToWeek = sortedRuns.filter { $0.date < weekEnd }

            // Compute weighted projection for runs up to this week
            var weightedSum = 0.0
            var totalWeight = 0.0

            for run in runsUpToWeek {
                guard let projected = projectedTime(
                    fromDistanceMiles: run.distanceMiles,
                    durationSeconds: run.durationSeconds,
                    for: targetRace
                ) else { continue }

                let daysAgo = max(0, Double(cal.dateComponents([.day], from: run.date, to: weekEnd).day ?? 0))
                let recencyWeight = exp(-daysAgo / 28.0)
                let distanceWeight = min(1.0, run.distanceMiles / (targetRace.distanceMiles * 0.5))
                let weight = recencyWeight * distanceWeight

                weightedSum += Double(projected) * weight
                totalWeight += weight
            }

            // Blend manual race time if available
            if let manual = manualRaceTime,
               let projected = projectedTime(from: manual, for: targetRace) {
                let daysAgo = max(0, Double(cal.dateComponents([.day], from: manual.raceDate, to: weekEnd).day ?? 0))
                let recencyWeight = exp(-daysAgo / 28.0)
                weightedSum += Double(projected) * 3.0 * recencyWeight
                totalWeight += 3.0 * recencyWeight
            }

            guard totalWeight > 0 else { continue }

            trend.append(WeeklyProjection(
                id: index,
                weekStart: weekStart,
                projectedSeconds: Int(weightedSum / totalWeight)
            ))
        }

        return trend
    }
}
