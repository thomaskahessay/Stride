import SwiftUI
import SwiftData
import UserNotifications

@main
struct StrideApp: App {

    @UIApplicationDelegateAdaptor(StrideAppDelegate.self) var appDelegate
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for:
                UserProfile.self,
                TrainingPlan.self,
                WorkoutDay.self,
                WorkoutLog.self,
                HistoricalRun.self,
                ReadinessCheck.self,
                AdaptationRecord.self,
                Route.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modelContainer(container)
                .preferredColorScheme(.light)
        }
    }
}

// MARK: - App Root

struct AppRootView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext

    private var profile: UserProfile? { profiles.first }
    private var needsOnboarding: Bool { profile == nil || profile?.onboardingComplete == false }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView()
            } else if let profile {
                ContentView(profile: profile)
            }
        }
        .task {
            if !needsOnboarding {
                await HealthKitManager.shared.requestAuthorisation()
                await NotificationManager.shared.requestAuthorisation()
                refreshNotifications()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshNotifications()
            Task { await HealthKitManager.shared.fetchRecentWorkouts() }
        }
        .onChange(of: profile?.activePlan?.workoutDays.count) {
            refreshNotifications()
        }
    }

    private func refreshNotifications() {
        guard let profile = profile, profile.onboardingComplete else { return }
        NotificationManager.shared.scheduleAll(for: profile)
    }
}

// MARK: - App Delegate (Notification Delegate)

class StrideAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show notifications even when app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
