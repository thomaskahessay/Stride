import SwiftUI

struct WorkoutDetailView: View {
    @Bindable var viewModel: WorkoutDetailViewModel
    var units: UnitSystem = .kilometers

    @Environment(\.dismiss) private var dismiss

    private var workout: WorkoutDay { viewModel.workout }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: .strideMD) {
                        headerCard

                        if workout.workoutType != .restDay {
                            statsRow
                        }

                        if workout.isCompleted, let log = workout.log {
                            actualStatsSection(log: log)
                        }

                        if workout.workoutType != .restDay && !workout.steps.isEmpty {
                            workoutSteps
                        }

                        coachingNote
                    }
                    .padding(.strideMD)
                    .padding(.bottom, 120)
                }

                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color(.systemBackground).opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .allowsHitTesting(false)
                    bottomActions
                        .padding(.horizontal, .strideMD)
                        .padding(.bottom, .strideMD)
                        .background(Color(.systemBackground).opacity(0.9))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
        .sheet(isPresented: $viewModel.showLogWorkout) {
            LogWorkoutView(workoutDay: workout)
        }
        .sheet(isPresented: $viewModel.showReschedule) {
            RescheduleWorkoutView(viewModel: viewModel)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HeroGlassCard(tint: workout.workoutType.accentColor) {
            VStack(alignment: .leading, spacing: .strideSM) {
                WorkoutTypeBadge(type: workout.workoutType)

                Text(workout.workoutTitle)
                    .font(Font.stride.displayMedium)

                Text(workout.effectiveDate.formatted(date: .complete, time: .omitted))
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)

                // Status badges
                if workout.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(Font.stride.bodyMedium.weight(.semibold))
                        .foregroundStyle(Color.stride.mint)
                } else if workout.isSkipped {
                    Label("Skipped", systemImage: "minus.circle.fill")
                        .font(Font.stride.bodyMedium.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if workout.rescheduledDate != nil {
                    Label(
                        "Moved from \(workout.date.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "arrow.left.arrow.right"
                    )
                    .font(Font.stride.caption)
                    .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: .strideMD) {
            StatPill(
                icon: "road.lanes",
                value: String(format: "%.1f %@", units.convert(workout.targetDistanceMiles), units.shortLabel),
                label: "Distance"
            )
            StatPill(
                icon: "figure.run",
                value: workout.targetPaceSecPerMile.map { $0.formattedPace(unit: units) } ?? durationLabel,
                label: workout.targetPaceSecPerMile != nil ? "Pace" : "Est. Time"
            )
            StatPill(
                icon: "speedometer",
                value: workout.effortLevel.rawValue,
                label: "Effort"
            )
        }
    }

    // MARK: - Workout Steps

    private var workoutSteps: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideMD) {
                Text("Workout Structure")
                    .font(Font.stride.headingSmall)

                ForEach(workout.steps.sorted(by: { $0.order < $1.order })) { step in
                    HStack(alignment: .top, spacing: .strideSM) {
                        Text("\(step.order)")
                            .font(Font.stride.label)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.stride.lavender))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(step.label)
                                    .font(Font.stride.bodyMedium.weight(.semibold))

                                Spacer()

                                if let dist = step.distanceMiles {
                                    Text(String(format: "%.1f %@", units.convert(dist), units.shortLabel))
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                } else if let dur = step.durationMinutes {
                                    Text("\(dur) min")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text(localised(step.description))
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }
                    }

                    if step.order < workout.steps.count {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
    }

    // MARK: - Actual Stats (post-run)

    private func actualStatsSection(log: WorkoutLog) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("What You Did", systemImage: "figure.run.circle.fill")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.mint)

                Divider()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .strideSM) {
                    actualStatCell(
                        icon: "road.lanes",
                        label: "Distance",
                        value: "\(log.actualDistanceMiles.formattedDistance(unit: units)) \(units.shortLabel)"
                    )
                    actualStatCell(
                        icon: "timer",
                        label: "Duration",
                        value: log.formattedDuration
                    )
                    actualStatCell(
                        icon: "hare",
                        label: "Avg Pace",
                        value: actualPace(log: log)
                    )
                    if let hr = log.averageHeartRate {
                        actualStatCell(
                            icon: "heart.fill",
                            label: "Avg Heart Rate",
                            value: "\(Int(hr)) bpm"
                        )
                    }
                }
            }
        }
    }

    private func actualStatCell(icon: String, label: String, value: String) -> some View {
        HStack(spacing: .strideXS) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.stride.lavenderDeep)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(Font.stride.bodyMedium.weight(.semibold))
                Text(label)
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actualPace(log: WorkoutLog) -> String {
        guard log.actualDistanceMiles > 0 else { return "—" }
        let secPerMile = Int(Double(log.actualDurationSeconds) / log.actualDistanceMiles)
        return secPerMile.formattedPace(unit: units)
    }

    // MARK: - Coaching Note

    private var coachingNote: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Coach's Note", systemImage: "text.bubble.fill")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)

                Text(workout.coachingNote)
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: .strideSM) {
            if workout.isCompleted {
                Button("Edit Log") {
                    viewModel.showLogWorkout = true
                }
                .buttonStyle(StrideSecondaryButtonStyle())
            } else {
                Button("Log This Workout") {
                    viewModel.showLogWorkout = true
                }
                .buttonStyle(StridePrimaryButtonStyle())

                if viewModel.canAdjust {
                    HStack(spacing: .strideSM) {
                        Button(viewModel.skipButtonLabel) {
                            viewModel.toggleSkipped()
                        }
                        .buttonStyle(StrideSecondaryButtonStyle())

                        Button("Move") {
                            viewModel.showReschedule = true
                        }
                        .buttonStyle(StrideSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var durationLabel: String {
        let h = workout.targetDurationMinutes / 60
        let m = workout.targetDurationMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func localised(_ text: String) -> String {
        guard units == .kilometers else { return text }
        return text
            .replacingOccurrences(of: "miles", with: "km", options: .caseInsensitive)
            .replacingOccurrences(of: "mile", with: "km", options: .caseInsensitive)
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        GlassCard(cornerRadius: .strideRadiusMD, padding: .strideSM) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.stride.lavenderDeep)
                Text(value)
                    .font(Font.stride.headingSmall)
                Text(label)
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
