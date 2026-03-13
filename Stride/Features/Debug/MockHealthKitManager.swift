#if DEBUG
import Foundation

@Observable
final class MockHealthKitManager {
    var isAuthorized = true
    var recentWorkouts: [HealthKitWorkoutData] = []
    var isRefreshing = false

    func requestAuthorisation() async {
        isAuthorized = true
        await fetchRecentWorkouts()
    }

    func fetchRecentWorkouts() async {
        isRefreshing = true
        // Simulate network delay
        try? await Task.sleep(for: .milliseconds(500))

        let now = DateProvider.shared.now
        let cal = Calendar.current

        recentWorkouts = [
            HealthKitWorkoutData(
                workoutDate: cal.date(byAdding: .hour, value: -2, to: now) ?? now,
                distanceMiles: 3.1,
                durationSeconds: 28 * 60 + 15,
                averageHeartRate: 142
            ),
            HealthKitWorkoutData(
                workoutDate: cal.date(byAdding: .day, value: -1, to: now) ?? now,
                distanceMiles: 5.0,
                durationSeconds: 42 * 60 + 30,
                averageHeartRate: 158
            ),
            HealthKitWorkoutData(
                workoutDate: cal.date(byAdding: .day, value: -2, to: now) ?? now,
                distanceMiles: 3.5,
                durationSeconds: 32 * 60 + 45,
                averageHeartRate: 138
            ),
            HealthKitWorkoutData(
                workoutDate: cal.date(byAdding: .day, value: -4, to: now) ?? now,
                distanceMiles: 10.2,
                durationSeconds: 95 * 60 + 10,
                averageHeartRate: 152
            ),
            HealthKitWorkoutData(
                workoutDate: cal.date(byAdding: .day, value: -6, to: now) ?? now,
                distanceMiles: 4.0,
                durationSeconds: 36 * 60,
                averageHeartRate: 145
            ),
        ]
        isRefreshing = false
    }

    func workoutData(for date: Date) -> HealthKitWorkoutData? {
        recentWorkouts.first {
            Calendar.current.isDate($0.workoutDate, inSameDayAs: date)
        }
    }

    func fetchHistoricalRuns(months: Int = 3) async -> [HistoricalRunImportData] {
        try? await Task.sleep(for: .milliseconds(300))
        let now = DateProvider.shared.now
        let cal = Calendar.current

        return (0..<10).map { i in
            let date = cal.date(byAdding: .day, value: -i * 7, to: now) ?? now
            let miles = Double.random(in: 3.0...12.0)
            let pace = Double.random(in: 480...600) // 8:00-10:00 min/mi
            return HistoricalRunImportData(
                startDate: date,
                endDate: date.addingTimeInterval(miles * pace),
                sourceHKUUID: UUID().uuidString,
                isIndoorRun: false,
                distanceMiles: miles,
                durationSeconds: miles * pace,
                totalCalories: miles * 100,
                averagePaceSecondsPerMile: pace,
                averageHeartRate: Double.random(in: 135...165),
                maxHeartRate: Double.random(in: 170...190),
                averageCadenceSPM: Double.random(in: 160...180),
                averageStrideLengthMeters: Double.random(in: 1.0...1.3)
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    func fetchLastNightSleep() async -> HealthKitSleepData? {
        try? await Task.sleep(for: .milliseconds(200))
        let cal = Calendar.current
        let now = DateProvider.shared.now
        let bedtime = cal.date(bySettingHour: 22, minute: 30, second: 0, of: cal.date(byAdding: .day, value: -1, to: now) ?? now) ?? now
        let wakeTime = cal.date(bySettingHour: 6, minute: 45, second: 0, of: now) ?? now

        return HealthKitSleepData(
            totalSleepHours: 7.2,
            timeInBedHours: 8.25,
            sleepEfficiency: 0.87,
            bedtime: bedtime,
            wakeTime: wakeTime
        )
    }
}
#endif
