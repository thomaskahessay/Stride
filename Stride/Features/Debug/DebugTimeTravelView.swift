#if DEBUG
import SwiftUI
import SwiftData

struct DebugTimeTravelView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let dateProvider = DateProvider.shared
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                timeTravelSection
                healthKitMockSection
                todayWorkoutSection
                upcomingWorkoutsSection
                adaptationSection
            }
            .navigationTitle("Debug Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Time Travel Controls

    private var timeTravelSection: some View {
        Section {
            VStack(spacing: 12) {
                if dateProvider.isTimeTraveling {
                    Text("SIMULATED DATE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                } else {
                    Text("REAL DATE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }

                Text(dateFormatter.string(from: dateProvider.now))
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)

                HStack(spacing: 16) {
                    Button { dateProvider.advanceDays(-7) } label: {
                        Label("-1w", systemImage: "chevron.backward.2")
                    }
                    Button { dateProvider.advanceDays(-1) } label: {
                        Label("-1d", systemImage: "chevron.backward")
                    }
                    Button { dateProvider.advanceDays(1) } label: {
                        Label("+1d", systemImage: "chevron.forward")
                    }
                    Button { dateProvider.advanceDays(7) } label: {
                        Label("+1w", systemImage: "chevron.forward.2")
                    }
                }
                .buttonStyle(.bordered)

                if dateProvider.isTimeTraveling {
                    Button("Reset to Real Time", role: .destructive) {
                        dateProvider.resetToRealTime()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Date Control")
        }
    }

    // MARK: - Today's Workout

    private var todayWorkout: WorkoutDay? {
        let cal = Calendar.current
        let now = dateProvider.now
        return profile.activePlan?.workoutDays.first {
            cal.isDate($0.effectiveDate, inSameDayAs: now)
        }
    }

    private var todayWorkoutSection: some View {
        Section {
            if let workout = todayWorkout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: workout.workoutType.sfSymbol)
                        Text(workout.workoutTitle)
                            .font(.headline)
                        Spacer()
                        statusBadge(for: workout)
                    }

                    if workout.workoutType.isRun {
                        Text("\(String(format: "%.1f", workout.targetDistanceMiles)) mi")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if workout.isAdapted, let note = workout.adaptationNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack(spacing: 12) {
                        Button("Mark Completed") {
                            markCompleted(workout)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(workout.isCompleted)

                        Button("Skip") {
                            workout.isSkipped.toggle()
                            try? modelContext.save()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Text("No workout scheduled for this date")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Today's Workout")
        }
    }

    // MARK: - Upcoming Workouts (next 7 days)

    private var upcomingWorkouts: [WorkoutDay] {
        let cal = Calendar.current
        let now = dateProvider.now
        let weekEnd = cal.date(byAdding: .day, value: 7, to: now) ?? now
        return (profile.activePlan?.workoutDays ?? [])
            .filter { $0.effectiveDate > now && $0.effectiveDate < weekEnd }
            .sorted { $0.effectiveDate < $1.effectiveDate }
    }

    private var upcomingWorkoutsSection: some View {
        Section {
            if upcomingWorkouts.isEmpty {
                Text("No upcoming workouts in the next 7 days")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcomingWorkouts, id: \.id) { workout in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(workout.workoutTitle)
                                .font(.subheadline.weight(.medium))
                            Text(shortDate(workout.effectiveDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusBadge(for: workout)
                    }
                }
            }
        } header: {
            Text("Next 7 Days")
        }
    }

    // MARK: - Adaptation Controls

    private var adaptationSection: some View {
        Section {
            if let plan = profile.activePlan {
                Button("Check for Missed Key Workouts") {
                    let engine = PlanAdaptationEngine()
                    if let recommendation = engine.checkForMissedKeyWorkouts(plan: plan) {
                        adaptationMessage = "\(recommendation.title): \(recommendation.message)"
                    } else {
                        adaptationMessage = "No missed key workouts"
                    }
                    showAdaptationResult = true
                }
                .foregroundStyle(.blue)
            } else {
                Text("No active plan")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Coach Engine")
        }
        .alert("Coach Check", isPresented: $showAdaptationResult) {
            Button("OK") { }
        } message: {
            Text(adaptationMessage)
        }
    }

    @State private var showAdaptationResult = false
    @State private var adaptationMessage = ""
    @State private var mockEnabled = HealthKitManager.useMock

    // MARK: - HealthKit Mock

    private var healthKitMockSection: some View {
        Section {
            Toggle("Enable Mock HealthKit", isOn: $mockEnabled)
                .onChange(of: mockEnabled) { _, newValue in
                    HealthKitManager.useMock = newValue
                    if newValue {
                        Task {
                            await HealthKitManager.shared.requestAuthorisation()
                        }
                    }
                }

            if mockEnabled {
                HStack {
                    Text("Mock workouts")
                    Spacer()
                    Text("\(HealthKitManager.mock.recentWorkouts.count)")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Mock Data") {
                    Task {
                        await HealthKitManager.shared.fetchRecentWorkouts()
                    }
                }
                .foregroundStyle(.blue)
            }
        } header: {
            Text("HealthKit Mock")
        } footer: {
            Text("Enables fake workout data so you can test the Apple Health import flow on the simulator.")
        }
    }

    // MARK: - Helpers

    private func markCompleted(_ workout: WorkoutDay) {
        workout.isCompleted = true
        workout.isSkipped = false

        if workout.log == nil {
            let log = WorkoutLog(
                actualDistanceMiles: workout.targetDistanceMiles,
                actualDurationSeconds: Int(workout.targetDistanceMiles * 600),
                effortRating: 5,
                notes: "[Debug] Auto-completed",
                sourceHealthKit: false
            )
            workout.log = log
            modelContext.insert(log)
        }
        try? modelContext.save()
    }

    private func statusBadge(for workout: WorkoutDay) -> some View {
        Group {
            if workout.isCompleted {
                Text("Done")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            } else if workout.isSkipped {
                Text("Skipped")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            } else if workout.isAdapted {
                Text("Adapted")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.purple.opacity(0.2))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            } else if workout.workoutType == .restDay {
                Text("Rest")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.gray.opacity(0.2))
                    .foregroundStyle(.gray)
                    .clipShape(Capsule())
            } else {
                Text("Pending")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "E MMM d"
        return f.string(from: date)
    }
}
#endif
