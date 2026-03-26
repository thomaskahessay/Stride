import SwiftUI

struct WorkoutDetailView: View {
    @Bindable var viewModel: WorkoutDetailViewModel
    var units: UnitSystem = .kilometers

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showConfetti = false

    private var workout: WorkoutDay { viewModel.workout }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: .strideMD) {
                        headerCard

                        if workout.isCompleted, let log = workout.log {
                            // Completed: actual stats as hero, then planned below
                            actualStatsRow(log: log)

                            // Route map (if a route was attached to this log)
                            if let route = log.route {
                                NavigationLink {
                                    RouteDetailView(route: route, unitSystem: units)
                                } label: {
                                    routeCard(route: route, venue: log.runVenue)
                                }
                                .buttonStyle(.plain)
                            } else if let venue = log.runVenue {
                                venueLabel(venue: venue)
                            }

                            plannedStatsSection
                        } else if workout.workoutType.isRun {
                            // Not completed: planned stats as hero
                            statsRow
                        }

                        if let check = viewModel.readinessCheck(context: modelContext) {
                            readinessScoreCard(check: check)
                        }

                        if workout.workoutType != .restDay && !workout.steps.isEmpty {
                            workoutSteps
                        }

                        coachingNote

                        if workout.isAdapted, let note = workout.adaptationNote {
                            adaptationCallout(note: note)
                        }

                        // Future workouts: inline message instead of floating buttons
                        if viewModel.isFutureWorkout && !workout.isCompleted && workout.workoutType != .restDay {
                            Text("You can log this workout on the day or after")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.strideMD)
                    .padding(.bottom, hasFloatingButtons ? 180 : .strideMD)
                }

                // Floating bottom actions (only when there are buttons)
                if hasFloatingButtons {
                    VStack(spacing: 0) {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, Color.stride.lavenderLight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        .allowsHitTesting(false)
                        bottomActions
                            .padding(.horizontal, .strideMD)
                            .padding(.bottom, .strideMD)
                            .background(Color.stride.lavenderLight)
                    }
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
        .sheet(isPresented: $viewModel.showLogWorkout) {
            LogWorkoutView(
                workoutDay: workout,
                weeklyLoggedMiles: viewModel.weeklyLoggedMiles,
                weeklyTargetMiles: viewModel.weeklyTargetMiles,
                isEditing: workout.isCompleted,
                showConfettiOnParent: $showConfetti
            )
        }
        .alert("Delete Log?", isPresented: $viewModel.showDeleteLogConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.deleteLog(context: modelContext)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove your logged data for this workout. You'll be able to skip it again.")
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        let displayType: WorkoutType = {
            if workout.isCompleted, let log = workout.log, let actual = log.actualWorkoutType {
                return actual
            }
            return workout.workoutType
        }()

        let displayTitle: String = {
            if workout.isCompleted, let log = workout.log, let actual = log.actualWorkoutType, actual != workout.workoutType {
                return actual.rawValue
            }
            return workout.workoutTitle
        }()

        return HeroGlassCard(tint: displayType.accentColor) {
            VStack(alignment: .leading, spacing: .strideSM) {
                WorkoutTypeBadge(type: displayType)

                Text(displayTitle)
                    .font(Font.stride.displayMedium)

                Text(workout.effectiveDate.formatted(date: .complete, time: .omitted))
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)

                // Status badges
                if workout.isAdapted {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Adapted")
                            .font(Font.stride.label)
                    }
                    .foregroundStyle(Color.stride.warmOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.stride.warmOrange.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.stride.warmOrange.opacity(0.4), lineWidth: 1)
                            )
                    )
                }

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

    // MARK: - Actual Stats Row (hero pills for completed workouts)

    private func actualStatsRow(log: WorkoutLog) -> some View {
        let showRunStats = workout.workoutType.isRun || log.actualDistanceMiles > 0

        return VStack(spacing: .strideMD) {
            if showRunStats {
                HStack(spacing: .strideMD) {
                    StatPill(
                        icon: "road.lanes",
                        value: log.actualDistanceMiles.formattedDistance(unit: units),
                        label: "Distance"
                    )
                    StatPill(
                        icon: "hare",
                        value: actualPace(log: log),
                        label: "Avg Pace"
                    )
                    StatPill(
                        icon: "timer",
                        value: log.formattedDuration,
                        label: "Duration"
                    )
                }
            }

            // Additional actual stats card
            GlassCard {
                VStack(alignment: .leading, spacing: .strideSM) {
                    if log.strengthCompleted {
                        HStack(spacing: 6) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.stride.sky)
                            Text("Strength completed")
                                .font(Font.stride.bodyMedium.weight(.semibold))
                                .foregroundStyle(Color.stride.sky)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.stride.sky.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.stride.sky.opacity(0.4), lineWidth: 1)
                                )
                        )
                    }

                    if showRunStats {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .strideSM) {
                            if let hr = log.averageHeartRate {
                                actualStatCell(
                                    icon: "heart.fill",
                                    label: "Avg Heart Rate",
                                    value: "\(Int(hr)) bpm"
                                )
                            }
                            actualStatCell(
                                icon: "flame.fill",
                                label: "Effort (RPE)",
                                value: "\(log.effortRating) / 10"
                            )
                        }
                    }

                    if !log.notes.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Notes", systemImage: "text.bubble")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                            Text(log.notes)
                                .font(Font.stride.bodyMedium)
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Route Card

    private func routeCard(route: Route, venue: RunVenue?) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.stride.lavenderDeep)
                    Text("Route")
                        .font(Font.stride.headingSmall)

                    Spacer()

                    if let venue {
                        HStack(spacing: 4) {
                            Image(systemName: venue.sfSymbol)
                                .font(.system(size: 10))
                            Text(venue.rawValue)
                                .font(Font.stride.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: .strideSM) {
                    RouteThumbnail(
                        waypoints: route.waypoints,
                        polyline: route.polylineCoordinates,
                        isLoop: route.isLoop,
                        size: 64
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.name)
                            .font(Font.stride.bodyMedium.weight(.semibold))
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(String(format: "%.1f km", route.distance / 1000))
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)

                            if route.isLoop {
                                Label("Loop", systemImage: "arrow.triangle.capsulepath")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let elevation = route.elevationGain {
                                Label(
                                    String(format: "%.0fm", elevation),
                                    systemImage: "arrow.up.right"
                                )
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func venueLabel(venue: RunVenue) -> some View {
        HStack(spacing: 6) {
            Image(systemName: venue.sfSymbol)
                .font(.system(size: 12))
            Text(venue.rawValue)
                .font(Font.stride.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    // MARK: - Planned Stats Section (shown below actuals for completed workouts)

    private var plannedStatsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Planned", systemImage: "calendar")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(.secondary)

                if workout.workoutType.isRun {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: .strideSM) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", units.convert(workout.targetDistanceMiles)))
                                .font(Font.stride.bodyMedium.weight(.semibold))
                            Text(units.shortLabel)
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 2) {
                            Text(workout.targetPaceSecPerMile.map { $0.formattedPace(unit: units) } ?? durationLabel)
                                .font(Font.stride.bodyMedium.weight(.semibold))
                            Text(workout.targetPaceSecPerMile != nil ? "pace" : "est. time")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 2) {
                            Text(workout.effortLevel.rawValue)
                                .font(Font.stride.bodyMedium.weight(.semibold))
                            Text("effort")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: .strideLG) {
                        VStack(spacing: 2) {
                            Text(durationLabel)
                                .font(Font.stride.bodyMedium.weight(.semibold))
                            Text("duration")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 2) {
                            Text(workout.effortLevel.rawValue)
                                .font(Font.stride.bodyMedium.weight(.semibold))
                            Text("effort")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
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

    // MARK: - Adaptation Callout

    private func adaptationCallout(note: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: .strideSM) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.stride.warmOrange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan Adjusted")
                        .font(Font.stride.bodyMedium.weight(.semibold))
                        .foregroundStyle(Color.stride.warmOrange)
                    Text(note)
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - Readiness Score Card

    private func readinessScoreCard(check: ReadinessCheck) -> some View {
        let color = readinessColor(for: check.recommendation)
        return GlassCard {
            HStack(spacing: .strideMD) {
                // Mini score ring
                ZStack {
                    Circle()
                        .stroke(Color.stride.lavenderLight, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: check.readinessScore / 100.0)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(check.readinessScore))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: check.recommendation.sfSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                        Text(check.recommendation.rawValue)
                            .font(Font.stride.bodyMedium.weight(.semibold))
                    }

                    Text(check.recommendation.description)
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func readinessColor(for recommendation: ReadinessRecommendation) -> Color {
        switch recommendation {
        case .sendIt: return Color.stride.mint
        case .dialBack: return Color.stride.lavenderDeep
        case .swapRecovery: return Color.stride.warmOrange
        case .restToday: return Color.stride.coral
        }
    }

    // MARK: - Bottom Actions

    private var hasFloatingButtons: Bool {
        if workout.isCompleted { return true }
        if viewModel.isFutureWorkout && workout.workoutType != .restDay { return false }
        return true
    }

    private var bottomActions: some View {
        VStack(spacing: .strideSM) {
            if workout.isCompleted {
                Button("Edit Log") {
                    viewModel.showLogWorkout = true
                }
                .buttonStyle(StrideSecondaryButtonStyle())

                // Delete log — escape hatch to re-open swap/skip
                Button("Delete Log") {
                    viewModel.showDeleteLogConfirmation = true
                }
                .font(Font.stride.caption)
                .foregroundStyle(.red.opacity(0.8))
            } else {
                if !workout.isSkipped {
                    Button(workout.workoutType == .strengthDay ? "Mark as Complete" : "Log This Workout") {
                        viewModel.showLogWorkout = true
                    }
                    .buttonStyle(StridePrimaryButtonStyle())
                }

                if viewModel.canAdjust {
                    Button(viewModel.skipButtonLabel) {
                        viewModel.toggleSkipped()
                    }
                    .buttonStyle(StrideSecondaryButtonStyle())
                } else if viewModel.isLocked && workout.workoutType != .restDay {
                    Button(viewModel.skipButtonLabel) { }
                        .buttonStyle(StrideSecondaryButtonStyle())
                        .disabled(true)
                    Text("Already logged — delete log to adjust")
                        .font(Font.stride.caption)
                        .foregroundStyle(.tertiary)
                }

                if workout.isAdapted && !workout.isCompleted {
                    Button("Restore Original") {
                        viewModel.revertAdaptation(context: modelContext)
                    }
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(Color.stride.warmOrange)
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
