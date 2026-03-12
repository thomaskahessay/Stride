import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - Permission

    func requestAuthorisation() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Schedule All Notifications

    func scheduleAll(for profile: UserProfile) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        guard profile.notificationsEnabled else { return }

        scheduleDailyWorkoutReminders(
            for: profile.activePlan,
            hour: profile.dailyReminderHour,
            minute: profile.dailyReminderMinute
        )
        scheduleWeeklySummary()
    }

    // MARK: - Daily Workout Reminders (workout-specific, next 7 days)

    private func scheduleDailyWorkoutReminders(for plan: TrainingPlan?, hour: Int, minute: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get upcoming workouts for the next 7 days
        let upcomingWorkouts: [WorkoutDay] = {
            guard let plan = plan else { return [] }
            return plan.workoutDays.filter { workout in
                let workoutDate = calendar.startOfDay(for: workout.date)
                let daysAhead = calendar.dateComponents([.day], from: today, to: workoutDate).day ?? -1
                return daysAhead >= 0 && daysAhead < 7 && !workout.isCompleted && !workout.isSkipped
            }
        }()

        for workout in upcomingWorkouts {
            let content = UNMutableNotificationContent()
            content.sound = .default

            if workout.workoutType == .restDay {
                content.title = "Rest day"
                content.body = "No run today — recover and come back stronger."
            } else {
                content.title = "Today's run: \(workout.workoutTitle)"
                let distance = String(format: "%.1f mi", workout.targetDistanceMiles)
                content.body = "\(workout.workoutType.rawValue) — \(distance). Let's go!"
            }

            var dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.date)
            dateComponents.hour = hour
            dateComponents.minute = minute

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: false
            )

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateString = formatter.string(from: workout.date)
            let request = UNNotificationRequest(
                identifier: "stride.daily.\(dateString)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }

        // Fallback: if no plan or no upcoming workouts, schedule a generic repeating reminder
        if upcomingWorkouts.isEmpty {
            let content = UNMutableNotificationContent()
            content.title = "Time to stride"
            content.body = "Your workout is waiting. Let's get it done."
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: true
            )
            let request = UNNotificationRequest(
                identifier: "stride.daily.reminder",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Weekly Summary (Sunday 8pm)

    private func scheduleWeeklySummary() {
        let content = UNMutableNotificationContent()
        content.title = "Weekly recap"
        content.body = "Check in on this week's training — your progress is building."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = 1  // Sunday
        dateComponents.hour = 20
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: "stride.weekly.summary",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Missed Workout Nudge

    /// Call this after detecting a missed workout. Fires a nudge the next morning.
    func scheduleMissedWorkoutNudge(for workoutTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Hey, life happens."
        content.body = "You missed your \(workoutTitle). No guilt — just lace up and go when you're ready."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 20 * 3600,  // 20 hours later
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "stride.missed.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cancel

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
