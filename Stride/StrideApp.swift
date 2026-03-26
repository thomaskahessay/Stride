import SwiftUI
import SwiftData
import UserNotifications
import UniformTypeIdentifiers

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

// MARK: - Shared import state (accessible from scene delegate + SwiftUI)

@Observable
final class RouteImportState {
    static let shared = RouteImportState()
    var pendingURL: URL?
}

// MARK: - App Root

struct AppRootView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @State private var importURL: ImportableURL?

    private let importState = RouteImportState.shared

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
        .onOpenURL { url in
            handleIncomingFile(url)
        }
        .onChange(of: importState.pendingURL) { _, newURL in
            if let url = newURL {
                handleIncomingFile(url)
                importState.pendingURL = nil
            }
        }
        .onAppear {
            // Pick up any file URL that arrived before the view appeared
            if let url = importState.pendingURL {
                handleIncomingFile(url)
                importState.pendingURL = nil
            }
        }
        .sheet(item: $importURL) { item in
            RouteImportView(url: item.url)
        }
    }

    private func handleIncomingFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "stride" || ext == "gpx" else { return }

        // Copy the file to a local temp location so it survives sandbox restrictions
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let localURL: URL
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let dest = tempDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            localURL = dest
        } catch {
            // Fall back to original URL if copy fails
            localURL = url
        }

        importURL = ImportableURL(url: localURL)
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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Handle file opens that arrive at app launch
        if let url = options.urlContexts.first?.url {
            RouteImportState.shared.pendingURL = url
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = StrideSceneDelegate.self
        return config
    }

    // Show notifications even when app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - Scene Delegate (handles file opens when app is already running)

class StrideSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        let ext = url.pathExtension.lowercased()
        if ext == "stride" || ext == "gpx" {
            RouteImportState.shared.pendingURL = url
        }
    }
}
