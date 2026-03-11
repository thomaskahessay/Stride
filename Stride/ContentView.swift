import SwiftUI

struct ContentView: View {
    let profile: UserProfile

    @State private var selectedTab: Tab = .home
    @State private var showLogWorkout = false
    @State private var showWorkoutDetail: WorkoutDay? = nil

    enum Tab {
        case home, calendar, progress, profileTab
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                DashboardView(profile: profile)
                    .tag(Tab.home)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }

                TrainingCalendarView(profile: profile)
                    .tag(Tab.calendar)
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }

                StatsView(profile: profile)
                    .tag(Tab.progress)
                    .tabItem {
                        Label("Progress", systemImage: "chart.bar.fill")
                    }

                ProfileView(profile: profile)
                    .tag(Tab.profileTab)
                    .tabItem {
                        Label("Profile", systemImage: "person.circle.fill")
                    }
            }
            .tint(Color.stride.lavenderDeep)

            // Floating Action Button — Log Workout (home tab only)
            if selectedTab == .home {
                FABButton {
                    showLogWorkout = true
                }
                .padding(.bottom, 72) // above tab bar
                .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showLogWorkout) {
            LogWorkoutView(
                workoutDay: profile.activePlan?.workoutDays.first(where: \.isToday),
                units: profile.unitPreference
            )
        }
    }
}

// MARK: - Floating Action Button

private struct FABButton: View {
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.stride.lavender)
                .background(
                    Circle()
                        .fill(.white)
                        .frame(width: 48, height: 48)
                )
                .shadow(
                    color: Color.stride.lavenderDeep.opacity(0.35),
                    radius: 12, x: 0, y: 4
                )
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: isPressed)
    }
}
