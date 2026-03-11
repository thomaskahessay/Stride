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
