import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - Permission

    @discardableResult
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
            for: profile,
            hour: profile.dailyReminderHour,
            minute: profile.dailyReminderMinute
        )
        scheduleWeeklySummary()
    }

    // MARK: - Daily Workout Reminders (dynamic, next 7 days)

    private func scheduleDailyWorkoutReminders(for profile: UserProfile, hour: Int, minute: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plan = profile.activePlan

        // Get upcoming workouts for the next 7 days
        let upcomingWorkouts: [WorkoutDay] = {
            guard let plan else { return [] }
            return plan.workoutDays.filter { workout in
                let workoutDate = calendar.startOfDay(for: workout.date)
                let daysAhead = calendar.dateComponents([.day], from: today, to: workoutDate).day ?? -1
                return daysAhead >= 0 && daysAhead < 7 && !workout.isCompleted && !workout.isSkipped
            }
        }()

        for workout in upcomingWorkouts {
            let content = UNMutableNotificationContent()
            content.sound = .default

            let context = NotificationContext(
                workout: workout,
                profile: profile,
                plan: plan,
                today: today
            )

            let (title, body) = dynamicMessage(for: context)
            content.title = title
            content.body = body

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

    // MARK: - Dynamic Notification Messages

    private struct NotificationContext {
        let workout: WorkoutDay
        let profile: UserProfile
        let plan: TrainingPlan?
        let today: Date

        var daysToRace: Int {
            max(0, Calendar.current.dateComponents([.day], from: today, to: profile.raceDate).day ?? 0)
        }

        var weekNumber: Int { workout.weekNumber }

        var totalWeeks: Int { plan?.totalWeeks ?? 1 }

        var trainingPhase: String {
            guard let plan else { return "base" }
            let progress = Double(plan.currentWeekNumber) / Double(plan.totalWeeks)
            if daysToRace <= 7 { return "raceWeek" }
            switch progress {
            case ..<0.3: return "base"
            case 0.3..<0.6: return "build"
            case 0.6..<0.85: return "peak"
            default: return "taper"
            }
        }

        var dayOfWeek: Int {
            Calendar.current.component(.weekday, from: workout.date) // 1=Sun, 2=Mon, ...
        }

        var distanceLabel: String {
            let d = profile.unitPreference.convert(workout.targetDistanceMiles)
            return String(format: "%.1f %@", d, profile.unitPreference.shortLabel)
        }
    }

    private func dynamicMessage(for ctx: NotificationContext) -> (title: String, body: String) {
        let workout = ctx.workout

        // Rest days — short and affirming
        if workout.workoutType == .restDay {
            return restDayMessage(ctx: ctx)
        }

        // Race week — special urgency
        if ctx.trainingPhase == "raceWeek" {
            return raceWeekMessage(ctx: ctx)
        }

        // Taper — reassurance
        if ctx.trainingPhase == "taper" {
            return taperMessage(ctx: ctx)
        }

        // Workout-type-specific dynamic messages
        switch workout.workoutType {
        case .longRun:     return longRunMessage(ctx: ctx)
        case .tempoRun:    return tempoMessage(ctx: ctx)
        case .intervalRun: return intervalMessage(ctx: ctx)
        case .easyRun:     return easyRunMessage(ctx: ctx)
        case .recoveryRun: return recoveryMessage(ctx: ctx)
        case .strengthDay: return strengthMessage(ctx: ctx)
        default:           return defaultMessage(ctx: ctx)
        }
    }

    // MARK: - Rest Day Messages

    private func restDayMessage(ctx: NotificationContext) -> (String, String) {
        let pool: [(String, String)] = [
            ("Rest day", "Recovery is where fitness is built. Enjoy the break."),
            ("No run today", "Your muscles are rebuilding right now. Let them."),
            ("Earned rest", "You've been putting in the work. Today, recharge."),
            ("Recovery mode", "Stretch, hydrate, and come back stronger tomorrow."),
        ]
        return pickByDate(from: pool, date: ctx.workout.date)
    }

    // MARK: - Race Week Messages

    private func raceWeekMessage(ctx: NotificationContext) -> (String, String) {
        let title = "\(ctx.daysToRace) days to race day"
        let pool: [String] = [
            "\(ctx.workout.workoutType.rawValue) today — \(ctx.distanceLabel). Keep it controlled. Trust the training.",
            "Easy does it. \(ctx.distanceLabel) at a comfortable pace. Save the fire for race day.",
            "Short and sharp today — \(ctx.distanceLabel). The hay is in the barn.",
            "Light shakeout — \(ctx.distanceLabel). Your body is ready. Your mind will follow.",
        ]
        return (title, pickByDate(from: pool, date: ctx.workout.date))
    }

    // MARK: - Taper Messages

    private func taperMessage(ctx: NotificationContext) -> (String, String) {
        let pool: [(String, String)] = [
            ("Taper time: \(ctx.workout.workoutTitle)",
             "\(ctx.distanceLabel) today. Less volume, same sharpness. You've earned this."),
            ("\(ctx.workout.workoutTitle) — taper mode",
             "The hard work is done. \(ctx.distanceLabel) to stay loose. Check in when you're ready."),
            ("Easy \(ctx.distanceLabel) today",
             "Taper feels weird — that's normal. Your body is absorbing weeks of work."),
        ]
        return pickByDate(from: pool, date: ctx.workout.date)
    }

    // MARK: - Long Run Messages

    private func longRunMessage(ctx: NotificationContext) -> (String, String) {
        let pool: [(String, String)] = [
            ("Long run day: \(ctx.distanceLabel)",
             "This is where endurance is built. Slow start, strong finish. Check in first."),
            ("\(ctx.distanceLabel) on the schedule",
             "Your biggest run this week. Hydrate, fuel up, and enjoy the miles."),
            ("Long run: \(ctx.workout.workoutTitle)",
             "Week \(ctx.weekNumber) of \(ctx.totalWeeks). This run is why you'll be ready on race day."),
            ("Time to go long — \(ctx.distanceLabel)",
             "Easy pace, big miles. The long run is your best friend in training."),
        ]
        return pickByDate(from: pool, date: ctx.workout.date)
    }

    // MARK: - Tempo Messages

    private func tempoMessage(ctx: NotificationContext) -> (String, String) {
        let pool: [(String, String)] = [
            ("Tempo day: \(ctx.workout.workoutTitle)",
             "\(ctx.distanceLabel) at a comfortably hard effort. How are you feeling? Check in."),
            ("Push the pace — \(ctx.distanceLabel)",
             "Tempo runs build your threshold. Find the effort where talking gets tough."),
            ("\(ctx.workout.workoutTitle) today",
             "Controlled discomfort for \(ctx.distanceLabel). This is where speed is forged."),
        ]
        return pickByDate(from: pool, date: ctx.workout.date)
    }

    // MARK: - Interval Messages

    private func intervalMessage(ctx: NotificationContext) -> (String, String) {
        let pool: [(String, String)] = [
            ("Intervals today: \(ctx.workout.workoutTitle)",
             "Fast reps, full recovery. \(ctx.distanceLabel) total. Check how you're feeling first."),
            ("Speed work: \(ctx.distanceLabel)",
             "Today's the day you get faster. Warm up well and attack the reps."),
            ("\(ctx.workout.workoutTitle) on deck",
             "Intervals sharpen the blade. \(ctx.distanceLabel) with purpose."),
        ]
        return pickByDate(from: pool, date: ctx.workout.date)
    }

    // MARK: - Easy Run Messages

    private func easyRunMessage(ctx: NotificationContext) -> (String, String) {
        let pool: [(String, String)] = [
            ("Easy run: \(ctx.distanceLabel)",
             "Conversational pace. If you can't chat, slow down. How's the body feeling?"),
            ("\(ctx.distanceLabel) easy today",
             "The easy days make the hard days possible. Keep it relaxed."),
            ("\(ctx.workout.workoutTitle) — \(ctx.distanceLabel)",
             "No pressure today. Just get out there and enjoy the run."),
            ("Lace up for \(ctx.distanceLabel)",
             "Easy effort, big impact. These runs build your aerobic engine."),
        ]
        return pickByDate(from: pool, date: ctx.workout.date)
    }

    // MARK: - Recovery Run Messages

    private func recoveryMessage(ctx: NotificationContext) -> (String, String) {
        let pool: [(String, String)] = [
            ("Recovery run: \(ctx.distanceLabel)",
             "Shake out the legs. Slower than you think — this is active recovery."),
            ("Easy shakeout: \(ctx.distanceLabel)",
             "Yesterday was tough. Today is about blood flow, not effort."),
            ("\(ctx.distanceLabel) recovery",
             "Keep it genuinely easy. If it feels like work, slow down more."),
        ]
        return pickByDate(from: pool, date: ctx.workout.date)
    }

    // MARK: - Strength Messages

    private func strengthMessage(ctx: NotificationContext) -> (String, String) {
        let pool: [(String, String)] = [
            ("Strength day",
             "No miles today — build the foundation that keeps you injury-free."),
            ("Cross-training today",
             "Strong legs, strong core. This work pays dividends on race day."),
            ("Off the road today",
             "Strength and mobility work. Your future self will thank you."),
        ]
        return pickByDate(from: pool, date: ctx.workout.date)
    }

    // MARK: - Default Messages

    private func defaultMessage(ctx: NotificationContext) -> (String, String) {
        let title = "\(ctx.workout.workoutTitle) — \(ctx.distanceLabel)"
        let body = "Week \(ctx.weekNumber) of \(ctx.totalWeeks). Open up and check in before you head out."
        return (title, body)
    }

    // MARK: - Deterministic Picker

    /// Picks a message deterministically based on the date so the same day always gets
    /// the same message, but different days get different ones.
    private func pickByDate<T>(from pool: [T], date: Date) -> T {
        let dayHash = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[dayHash % pool.count]
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
