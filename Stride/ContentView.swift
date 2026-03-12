import SwiftUI

struct ContentView: View {
    let profile: UserProfile

    @State private var selectedTab: Tab = .home
    @State private var showLogWorkout = false
    @State private var showAlreadyLoggedAlert = false
    @State private var showConfetti = false
    @State private var showRestDayInterstitial = false
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
                    let todayWorkout = profile.activePlan?.workoutDays.first(where: \.isToday)
                    if todayWorkout?.log != nil {
                        showAlreadyLoggedAlert = true
                    } else if todayWorkout?.workoutType == .restDay {
                        showRestDayInterstitial = true
                    } else {
                        showLogWorkout = true
                    }
                }
                .padding(.bottom, 72) // above tab bar
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay {
            if showConfetti {
                ConfettiOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            withAnimation { showConfetti = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showLogWorkout) {
            LogWorkoutView(
                workoutDay: profile.activePlan?.workoutDays.first(where: \.isToday),
                units: profile.unitPreference,
                weeklyLoggedMiles: weeklyLoggedMiles,
                weeklyTargetMiles: weeklyTargetMiles,
                showConfettiOnParent: $showConfetti
            )
        }
        .alert("Already Logged", isPresented: $showAlreadyLoggedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You've already logged a workout for today. View or edit it from the workout detail screen.")
        }
        .alert("It's a Rest Day", isPresented: $showRestDayInterstitial) {
            Button("Log Anyway") { showLogWorkout = true }
            Button("Got It, I'll Rest", role: .cancel) { }
        } message: {
            Text("Recovery is where fitness is built. Rest days are part of the plan — your body needs them to get stronger.")
        }
    }

    // MARK: - Weekly mileage helpers

    private var weeklyLoggedMiles: Double {
        guard let plan = profile.activePlan else { return 0 }
        let cal = Calendar.current
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        return plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate <= Date() }
            .compactMap { day in
                guard let log = day.log else { return nil as Double? }
                // Don't count cross-training toward running volume
                if let activityType = log.restDayActivityType, !activityType.countsTowardRunningVolume {
                    return nil
                }
                return log.actualDistanceMiles
            }
            .reduce(0, +)
    }

    private var weeklyTargetMiles: Double {
        guard let plan = profile.activePlan else { return 0 }
        let cal = Calendar.current
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
        return plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate < weekEnd && $0.workoutType.isRun && !$0.isSkipped }
            .map { $0.targetDistanceMiles }
            .reduce(0, +)
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
