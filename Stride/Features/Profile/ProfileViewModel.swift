import Foundation
import SwiftData

@Observable
final class ProfileViewModel {

    // MARK: - Published State

    // Personal stats
    var totalRuns: Int = 0
    var totalDistanceMiles: Double = 0
    var longestRunMiles: Double = 0
    var averagePaceSecPerMile: Int = 0
    var averageRPE: Double = 0
    var totalDurationSeconds: Int = 0

    // Training snapshot
    var currentPhase: String = "—"
    var currentWeek: Int = 0
    var totalWeeks: Int = 0
    var workoutsCompleted: Int = 0
    var workoutsPlanned: Int = 0
    var currentStreak: Int = 0

    // Race projection
    var projectedFinishTimeSeconds: Int?

    // HealthKit
    var healthKitConnected: Bool = false
    var lastSyncDate: Date?
    var historicalRunsImported: Int = 0

    // MARK: - Dependencies

    private let profile: UserProfile
    private let finishTimeEstimator = FinishTimeEstimator()

    init(profile: UserProfile) {
        self.profile = profile
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        computePersonalStats()
        computeTrainingSnapshot()
        computeRaceProjection()
        computeHealthKitStatus()
    }

    // MARK: - Personal Stats

    private func computePersonalStats() {
        guard let plan = profile.activePlan else { return }

        let completedDays = plan.workoutDays.filter { $0.isCompleted && $0.log != nil }

        totalRuns = completedDays.count
        totalDistanceMiles = completedDays.compactMap { $0.log?.actualDistanceMiles }.reduce(0, +)
        longestRunMiles = completedDays.compactMap { $0.log?.actualDistanceMiles }.max() ?? 0
        totalDurationSeconds = completedDays.compactMap { $0.log?.actualDurationSeconds }.reduce(0, +)

        let paces = completedDays.compactMap { $0.log?.averagePaceSecPerMile }
        averagePaceSecPerMile = paces.isEmpty ? 0 : paces.reduce(0, +) / paces.count

        let rpes = completedDays.compactMap { $0.log?.effortRating }
        averageRPE = rpes.isEmpty ? 0 : Double(rpes.reduce(0, +)) / Double(rpes.count)
    }

    // MARK: - Training Snapshot

    private func computeTrainingSnapshot() {
        guard let plan = profile.activePlan else { return }

        currentWeek = plan.currentWeekNumber
        totalWeeks = plan.totalWeeks

        let today = Calendar.current.startOfDay(for: Date())

        // Only count run/strength workouts (not rest days) as "planned"
        let planned = plan.workoutDays.filter {
            $0.workoutType != .restDay && $0.effectiveDate <= today
        }
        workoutsPlanned = planned.count
        workoutsCompleted = planned.filter { $0.isCompleted }.count

        // Current phase based on week position
        currentPhase = trainingPhase(week: currentWeek, totalWeeks: totalWeeks)

        // Streak
        currentStreak = calculateStreak(plan: plan)
    }

    private func trainingPhase(week: Int, totalWeeks: Int) -> String {
        guard totalWeeks > 0 else { return "—" }
        let fraction = Double(week) / Double(totalWeeks)
        switch fraction {
        case ..<0.30: return "Base Building"
        case ..<0.60: return "Build Phase"
        case ..<0.85: return "Peak Phase"
        default:      return "Taper"
        }
    }

    private func calculateStreak(plan: TrainingPlan) -> Int {
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())

        while true {
            let day = plan.workoutDays.first {
                Calendar.current.isDate($0.effectiveDate, inSameDayAs: checkDate)
            }

            guard let day else { break }

            if day.workoutType == .restDay {
                // Rest days don't break streak
            } else if day.isCompleted {
                streak += 1
            } else if day.isPast {
                break
            }

            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }

    // MARK: - Race Projection

    private func computeRaceProjection() {
        if let raceTime = profile.recentRaceTime {
            projectedFinishTimeSeconds = finishTimeEstimator.projectedTime(
                from: raceTime,
                for: profile.raceType
            )
        } else {
            projectedFinishTimeSeconds = nil
        }
    }

    // MARK: - HealthKit Status

    private func computeHealthKitStatus() {
        // Check if HealthKit has been authorized by seeing if we have historical runs
        // In a real implementation this would query HealthKitManager
        healthKitConnected = !profile.recentRuns.isEmpty
        historicalRunsImported = profile.recentRuns.count
    }

    // MARK: - Computed Helpers

    var daysToRace: Int {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: profile.raceDate
        ).day ?? 0
        return max(0, days)
    }

    var memberSinceFormatted: String {
        profile.createdAt.formatted(.dateTime.month(.wide).year())
    }

    var workoutCompletionPercent: Double {
        guard workoutsPlanned > 0 else { return 0 }
        return Double(workoutsCompleted) / Double(workoutsPlanned)
    }

    var totalDistanceFormatted: String {
        let value = profile.unitPreference.convert(totalDistanceMiles)
        return String(format: value < 10 ? "%.1f" : "%.0f", value)
    }

    var longestRunFormatted: String {
        let value = profile.unitPreference.convert(longestRunMiles)
        return String(format: "%.1f", value)
    }

    var totalDurationFormatted: String {
        let hours = totalDurationSeconds / 3600
        let minutes = (totalDurationSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var projectedFinishFormatted: String? {
        guard let seconds = projectedFinishTimeSeconds else { return nil }
        return finishTimeEstimator.formatted(seconds: seconds)
    }

    var goalTimeFormatted: String? {
        guard profile.goalFinishTimeSeconds > 0 else { return nil }
        return finishTimeEstimator.formatted(seconds: profile.goalFinishTimeSeconds)
    }

    var paceZonesSummary: [(label: String, pace: String)]? {
        guard let plan = profile.activePlan, let zones = plan.paceZones else { return nil }
        let unit = profile.unitPreference
        return [
            ("Recovery", zones.recoveryPaceSecPerMile.formattedPace(unit: unit)),
            ("Easy", zones.easyPaceSecPerMile.formattedPace(unit: unit)),
            ("Tempo", zones.tempoPaceSecPerMile.formattedPace(unit: unit)),
            ("Race", zones.racePaceSecPerMile.formattedPace(unit: unit)),
            ("Interval", zones.intervalPaceSecPerMile.formattedPace(unit: unit)),
        ]
    }

    /// Training phase progress as a fraction (0.0–1.0) for the phase indicator
    var phaseProgress: Double {
        guard totalWeeks > 0 else { return 0 }
        return Double(currentWeek) / Double(totalWeeks)
    }

    /// Phase names for the phase indicator bar
    var phases: [(name: String, fraction: Double)] {
        [
            ("Base", 0.30),
            ("Build", 0.30),
            ("Peak", 0.25),
            ("Taper", 0.15),
        ]
    }
}
