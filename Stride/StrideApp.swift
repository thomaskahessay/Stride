import SwiftUI
import SwiftData

@main
struct StrideApp: App {

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for:
                UserProfile.self,
                TrainingPlan.self,
                WorkoutDay.self,
                WorkoutLog.self,
                HistoricalRun.self
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
            } else {
                ContentView(profile: profile!)
            }
        }
        .task {
            // Request HealthKit auth after onboarding completes
            if !needsOnboarding {
                await HealthKitManager.shared.requestAuthorisation()
            }
        }
    }
}
