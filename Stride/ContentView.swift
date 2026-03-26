import SwiftUI

struct ContentView: View {
    let profile: UserProfile

    @State private var selectedTab: Tab = .home
    @State private var showLogWorkout = false
    @State private var showAlreadyLoggedAlert = false
    @State private var showConfetti = false
    @State private var showWorkoutDetail: WorkoutDay? = nil

    enum Tab {
        case home, plan, routes, progress, profileTab
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            #if DEBUG
            if DateProvider.shared.isTimeTraveling {
                VStack {
                    TimeTravelBanner()
                    Spacer()
                }
                .zIndex(100)
            }
            #endif

            TabView(selection: $selectedTab) {
                DashboardView(profile: profile)
                    .tag(Tab.home)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }

                TrainingCalendarView(profile: profile)
                    .tag(Tab.plan)
                    .tabItem {
                        Label("Plan", systemImage: "calendar")
                    }

                NavigationStack {
                    SavedRoutesView(unitSystem: profile.unitPreference)
                }
                    .tag(Tab.routes)
                    .tabItem {
                        Label("Routes", systemImage: "map.fill")
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
                        // Open detail view so user can swap or log
                        if let workout = todayWorkout {
                            showWorkoutDetail = workout
                        }
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
        .sheet(isPresented: $showLogWorkout, onDismiss: {
            // After logging, show the workout detail so the user sees their summary
            if let workout = profile.activePlan?.workoutDays.first(where: \.isToday),
               workout.isCompleted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showWorkoutDetail = workout
                }
            }
        }) {
            LogWorkoutView(
                workoutDay: profile.activePlan?.workoutDays.first(where: \.isToday),
                units: profile.unitPreference,
                weeklyLoggedMiles: weeklyLoggedMiles,
                weeklyTargetMiles: weeklyTargetMiles,
                plan: profile.activePlan,
                showConfettiOnParent: $showConfetti
            )
        }
        .sheet(item: $showWorkoutDetail) { workout in
            if let plan = profile.activePlan {
                WorkoutDetailView(
                    viewModel: WorkoutDetailViewModel(workout: workout, plan: plan),
                    units: profile.unitPreference
                )
            }
        }
        .alert("Already Logged", isPresented: $showAlreadyLoggedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You've already logged a workout for today. View or edit it from the workout detail screen.")
        }
    }

    // MARK: - Weekly mileage helpers

    private var weeklyLoggedMiles: Double {
        guard let plan = profile.activePlan else { return 0 }
        let cal = Calendar.current
        let now = DateProvider.shared.now
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? now
        return plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate <= now }
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
        let now = DateProvider.shared.now
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? now
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? now
        return plan.workoutDays
            .filter { $0.effectiveDate >= weekStart && $0.effectiveDate < weekEnd && $0.workoutType.isRun }
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

// MARK: - Time Travel Banner

#if DEBUG
struct TimeTravelBanner: View {
    var body: some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "E, MMM d yyyy"
            return f
        }()

        HStack {
            Image(systemName: "clock.arrow.circlepath")
            Text("TIME TRAVEL: \(formatter.string(from: DateProvider.shared.now))")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.gradient)
        .clipShape(Capsule())
        .padding(.top, 4)
    }
}
#endif
