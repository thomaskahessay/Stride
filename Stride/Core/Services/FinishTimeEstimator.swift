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

    /// Source label shown beneath the projected time
    func sourceLabel(for raceTime: RaceTime) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Based on your \(raceTime.raceDistance.displayName) on \(formatter.string(from: raceTime.raceDate))"
    }
}
