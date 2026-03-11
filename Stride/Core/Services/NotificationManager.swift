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

        scheduleDailyReminder(hour: profile.dailyReminderHour, minute: profile.dailyReminderMinute)
        scheduleWeeklySummary()
    }

    // MARK: - Daily Workout Reminder

    private func scheduleDailyReminder(hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time to stride 👟"
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
