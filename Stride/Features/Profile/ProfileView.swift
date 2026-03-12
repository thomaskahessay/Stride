import SwiftUI
import SwiftData

struct ProfileView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ProfileViewModel
    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var showResetPlanConfirm = false
    @State private var showResetAllConfirm = false

    init(profile: UserProfile) {
        self.profile = profile
        self._viewModel = State(initialValue: ProfileViewModel(profile: profile))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {
                        runnerIdentityHeader
                        trainingSnapshotCard
                        personalStatsCard
                        raceGoalCard
                        if viewModel.paceZonesSummary != nil {
                            paceZonesCard
                        }
                        runningProfileCard
                        healthKitCard
                        settingsCard
                        dangerZone
                        appInfoFooter
                    }
                    .padding(.horizontal, .strideMD)
                    .padding(.vertical, .strideMD)
                }
            }
            .navigationBarHidden(true)
            .onAppear { viewModel.refresh() }
            .sheet(isPresented: $showSettings) {
                SettingsView(profile: profile)
            }
            .sheet(isPresented: $showEditProfile) {
                EditRunningProfileView(profile: profile)
            }
            .confirmationDialog("Reset training plan?", isPresented: $showResetPlanConfirm, titleVisibility: .visible) {
                Button("Regenerate Plan", role: .destructive) { regeneratePlan() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will create a new training plan based on your current settings. Your completed workout logs will be kept.")
            }
            .confirmationDialog("Delete all data?", isPresented: $showResetAllConfirm, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) { resetAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete your training plan, all logs, and your profile. This cannot be undone.")
            }
        }
    }

    // MARK: - Runner Identity Header

    private var runnerIdentityHeader: some View {
        HeroGlassCard(tint: Color.stride.lavender) {
            VStack(spacing: .strideMD) {
                // Avatar with gradient ring
                ZStack {
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [
                                    Color.stride.lavender,
                                    Color.stride.lavenderDeep,
                                    Color.stride.lavender,
                                ],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 84, height: 84)

                    Circle()
                        .fill(Color.stride.lavenderLight)
                        .frame(width: 74, height: 74)
                        .overlay(
                            Text(String(profile.firstName.prefix(1)).uppercased())
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.stride.lavenderDeep)
                        )
                }

                // Name and info
                VStack(spacing: 4) {
                    Text(profile.firstName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    HStack(spacing: .strideSM) {
                        Label(profile.fitnessLevel.rawValue, systemImage: "figure.run")
                        Text("·")
                        Text(profile.raceType.displayName)
                    }
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)

                    Text("Member since \(viewModel.memberSinceFormatted)")
                        .font(Font.stride.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Training Snapshot

    private var trainingSnapshotCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                HStack {
                    Text("Training Snapshot")
                        .font(Font.stride.headingSmall)
                    Spacer()
                    // Phase badge
                    Text(viewModel.currentPhase)
                        .font(Font.stride.label)
                        .foregroundStyle(Color.stride.lavenderDeep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.stride.lavender.opacity(0.25))
                        )
                }

                // Phase progress bar
                phaseProgressBar

                // Stats grid
                HStack(spacing: 0) {
                    snapshotStat(
                        value: "\(viewModel.currentWeek)/\(viewModel.totalWeeks)",
                        label: "Week"
                    )
                    snapshotDivider
                    snapshotStat(
                        value: "\(viewModel.workoutsCompleted)",
                        label: "Completed"
                    )
                    snapshotDivider
                    snapshotStat(
                        value: "\(Int(viewModel.workoutCompletionPercent * 100))%",
                        label: "Hit Rate"
                    )
                    snapshotDivider
                    snapshotStat(
                        value: "\(viewModel.currentStreak)",
                        label: "Streak",
                        icon: viewModel.currentStreak > 0 ? "flame.fill" : nil,
                        iconColor: .orange
                    )
                }
                .padding(.top, .strideXS)
            }
        }
    }

    private var phaseProgressBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(viewModel.phases.enumerated()), id: \.offset) { index, phase in
                    let width = geo.size.width * phase.fraction
                    let isActive = isPhaseActive(index: index)
                    let isCurrent = isCurrentPhase(index: index)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            isActive
                                ? Color.stride.lavender
                                : (isCurrent
                                    ? Color.stride.lavender.opacity(0.5)
                                    : Color.stride.lavenderLight)
                        )
                        .frame(width: width)
                        .overlay(alignment: .center) {
                            if geo.size.width * phase.fraction > 36 {
                                Text(phase.name)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(
                                        isActive ? .white : .secondary
                                    )
                            }
                        }
                }
            }
        }
        .frame(height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func isPhaseActive(index: Int) -> Bool {
        let cumulativeFraction = viewModel.phases.prefix(index + 1).map(\.fraction).reduce(0, +)
        return viewModel.phaseProgress >= cumulativeFraction
    }

    private func isCurrentPhase(index: Int) -> Bool {
        let prevFraction = viewModel.phases.prefix(index).map(\.fraction).reduce(0, +)
        let currentFraction = viewModel.phases.prefix(index + 1).map(\.fraction).reduce(0, +)
        return viewModel.phaseProgress >= prevFraction && viewModel.phaseProgress < currentFraction
    }

    private func snapshotStat(value: String, label: String, icon: String? = nil, iconColor: Color = .primary) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(iconColor)
                }
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            Text(label)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var snapshotDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 36)
    }

    // MARK: - Personal Stats

    private var personalStatsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("Your Running")
                    .font(Font.stride.headingSmall)

                if viewModel.totalRuns == 0 {
                    HStack {
                        Image(systemName: "figure.run")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.stride.lavender)
                        Text("Complete your first workout to see stats here.")
                            .font(Font.stride.bodyMedium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, .strideSM)
                } else {
                    // Top row — big hero numbers
                    HStack(spacing: 0) {
                        statBlock(
                            value: viewModel.totalDistanceFormatted,
                            unit: profile.unitPreference.shortLabel,
                            label: "Total Distance"
                        )
                        statDivider
                        statBlock(
                            value: "\(viewModel.totalRuns)",
                            unit: nil,
                            label: "Runs"
                        )
                        statDivider
                        statBlock(
                            value: viewModel.totalDurationFormatted,
                            unit: nil,
                            label: "Time"
                        )
                    }

                    Divider()

                    // Bottom row
                    HStack(spacing: 0) {
                        statBlock(
                            value: viewModel.longestRunFormatted,
                            unit: profile.unitPreference.shortLabel,
                            label: "Longest Run"
                        )
                        statDivider
                        statBlock(
                            value: viewModel.averagePaceSecPerMile > 0
                                ? viewModel.averagePaceSecPerMile.formattedPaceCompact(unit: profile.unitPreference)
                                : "—",
                            unit: viewModel.averagePaceSecPerMile > 0
                                ? "/\(profile.unitPreference.shortLabel)"
                                : nil,
                            label: "Avg Pace"
                        )
                        statDivider
                        statBlock(
                            value: viewModel.averageRPE > 0
                                ? String(format: "%.1f", viewModel.averageRPE)
                                : "—",
                            unit: viewModel.averageRPE > 0 ? "/10" : nil,
                            label: "Avg Effort"
                        )
                    }
                }
            }
        }
    }

    private func statBlock(value: String, unit: String?, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 36)
    }

    // MARK: - Race Goal

    private var raceGoalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                HStack {
                    Text("Race Goal")
                        .font(Font.stride.headingSmall)
                    Spacer()
                    // Days countdown pill
                    HStack(spacing: 4) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(viewModel.daysToRace) days")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.stride.lavenderDeep)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.stride.lavender.opacity(0.25))
                    )
                }

                // Race info row
                HStack(spacing: .strideMD) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.raceType.displayName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(profile.raceDate.formatted(date: .abbreviated, time: .omitted))
                            .font(Font.stride.bodyMedium)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Goal type
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: profile.goalType.sfSymbol)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.stride.lavenderDeep)
                        Text(profile.goalType.rawValue)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Goal time + projected time
                if let goalTime = viewModel.goalTimeFormatted {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Goal Time")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                            Text(goalTime)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.stride.lavenderDeep)
                        }
                        Spacer()
                        if let projected = viewModel.projectedFinishFormatted {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Projected")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                                Text(projected)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                            }
                        }
                    }
                } else if let projected = viewModel.projectedFinishFormatted {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Projected Finish")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                        Text(projected)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                }
            }
        }
    }

    // MARK: - Pace Zones

    private var paceZonesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("Pace Zones")
                    .font(Font.stride.headingSmall)

                if let zones = viewModel.paceZonesSummary {
                    ForEach(Array(zones.enumerated()), id: \.offset) { index, zone in
                        HStack {
                            Text(zone.label)
                                .font(Font.stride.bodyMedium)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)

                            // Visual pace bar
                            GeometryReader { geo in
                                let maxPace = zones.map { paceValue($0.pace) }.max() ?? 1
                                let thisPace = paceValue(zone.pace)
                                let fraction = maxPace > 0 ? thisPace / maxPace : 0

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(paceBarColor(index: index))
                                    .frame(width: geo.size.width * fraction)
                            }
                            .frame(height: 8)

                            Text(zone.pace)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .frame(width: 80, alignment: .trailing)
                        }

                        if index < zones.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func paceValue(_ pace: String) -> Double {
        // Extract numeric pace for relative bar sizing (slower = larger bar)
        let parts = pace.components(separatedBy: ":")
        guard let first = parts.first, let minutes = Double(first) else { return 0 }
        let secondsPart = parts.count > 1
            ? Double(parts[1].components(separatedBy: " ").first ?? "0") ?? 0
            : 0
        return minutes * 60 + secondsPart
    }

    private func paceBarColor(index: Int) -> Color {
        let colors: [Color] = [
            Color.stride.mint.opacity(0.6),
            Color.stride.mint,
            Color.stride.sage,
            Color.stride.lavenderDeep,
            Color.stride.coral.opacity(0.8),
        ]
        return colors[index % colors.count]
    }

    // MARK: - Running Profile (Editable)

    private var runningProfileCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideXS) {
                HStack {
                    Text("Running Profile")
                        .font(Font.stride.headingSmall)
                    Spacer()
                    Button {
                        showEditProfile = true
                    } label: {
                        Text("Edit")
                            .font(Font.stride.bodyMedium.weight(.semibold))
                            .foregroundStyle(Color.stride.lavenderDeep)
                    }
                }
                .padding(.bottom, .strideXS)

                profileInfoRow(icon: "calendar.badge.clock", label: "Experience", value: profile.runningExperience.rawValue)
                Divider()
                profileInfoRow(icon: "figure.run", label: "Weekly Mileage", value: "\(Int(profile.currentWeeklyMiles)) \(profile.unitPreference.shortLabel)/week")
                Divider()
                profileInfoRow(
                    icon: "speedometer",
                    label: "Zone 2 Pace",
                    value: profile.zone2PaceSecondsPerMile > 0
                        ? profile.zone2PaceSecondsPerMile.formattedPace(unit: profile.unitPreference)
                        : "Not set"
                )
                Divider()
                profileInfoRow(icon: "calendar", label: "Long Run Day", value: profile.preferredLongRunDay.displayName)
                Divider()
                profileInfoRow(icon: "moon.fill", label: "Rest Days", value: profile.restDays.map(\.shortName).joined(separator: ", "))
                Divider()
                profileInfoRow(
                    icon: "bandage.fill",
                    label: "Injury",
                    value: profile.currentInjuryRegion.rawValue
                )
                Divider()
                profileInfoRow(
                    icon: "dumbbell.fill",
                    label: "Strength Training",
                    value: profile.doesStrengthTraining ? "Yes" : "No"
                )
            }
        }
    }

    private func profileInfoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.stride.lavenderDeep)
                .frame(width: 24)
            Text(label)
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Font.stride.bodyMedium.weight(.medium))
        }
        .padding(.vertical, 2)
    }

    // MARK: - HealthKit Status

    private var healthKitCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                HStack {
                    Text("Apple Health")
                        .font(Font.stride.headingSmall)
                    Spacer()
                    // Connection status dot
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.healthKitConnected ? Color.stride.mint : Color(.systemGray3))
                            .frame(width: 8, height: 8)
                        Text(viewModel.healthKitConnected ? "Connected" : "Not Connected")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.healthKitConnected {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red.opacity(0.7))
                        Text("\(viewModel.historicalRunsImported) runs imported")
                            .font(Font.stride.bodyMedium)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Connect Apple Health to auto-fill workout data after your runs.")
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideXS) {
                Text("Settings")
                    .font(Font.stride.headingSmall)
                    .padding(.bottom, .strideXS)

                settingsButton(icon: "bell.fill", label: "Notifications", detail: profile.notificationsEnabled ? "On" : "Off") {
                    showSettings = true
                }
                Divider()
                settingsButton(icon: "ruler.fill", label: "Distance Units", detail: profile.unitPreference.rawValue) {
                    showSettings = true
                }
                Divider()
                settingsButton(icon: "arrow.triangle.2.circlepath", label: "Regenerate Plan", detail: nil) {
                    showResetPlanConfirm = true
                }
            }
        }
    }

    private func settingsButton(icon: String, label: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.stride.lavenderDeep)
                    .frame(width: 24)
                Text(label)
                    .font(Font.stride.bodyMedium)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(Font.stride.caption)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.systemGray3))
            }
            .padding(.vertical, .strideXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(spacing: .strideSM) {
            Button("Reset All Data") {
                showResetAllConfirm = true
            }
            .buttonStyle(StrideGhostButtonStyle())
            .foregroundStyle(Color.stride.coral)
        }
    }

    // MARK: - App Info Footer

    private var appInfoFooter: some View {
        VStack(spacing: 4) {
            Text("Stride")
                .font(Font.stride.bodyMedium.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text("Built for runners, by runners")
                .font(Font.stride.caption)
                .foregroundStyle(.quaternary)
            Text("v1.0")
                .font(Font.stride.caption)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .strideMD)
    }

    // MARK: - Actions

    private func regeneratePlan() {
        // Soft-delete old plan and regenerate
        if let oldPlan = profile.activePlan {
            oldPlan.isActive = false
        }
        let generator = TrainingPlanGenerator()
        let newPlan = generator.generate(from: profile)
        profile.activePlan = newPlan
        try? modelContext.save()
        viewModel.refresh()
    }

    private func resetAllData() {
        try? modelContext.delete(model: UserProfile.self)
        try? modelContext.save()
    }
}

// MARK: - Edit Running Profile Sheet

struct EditRunningProfileView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weeklyMiles: Double
    @State private var zone2Pace: Int
    @State private var longRunDay: Weekday
    @State private var restDays: [Weekday]
    @State private var injuryRegion: InjuryRegion
    @State private var doesStrength: Bool
    @State private var experience: RunningExperience

    init(profile: UserProfile) {
        self.profile = profile
        self._weeklyMiles = State(initialValue: profile.currentWeeklyMiles)
        self._zone2Pace = State(initialValue: profile.zone2PaceSecondsPerMile)
        self._longRunDay = State(initialValue: profile.preferredLongRunDay)
        self._restDays = State(initialValue: profile.restDays)
        self._injuryRegion = State(initialValue: profile.currentInjuryRegion)
        self._doesStrength = State(initialValue: profile.doesStrengthTraining)
        self._experience = State(initialValue: profile.runningExperience)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {

                        // Experience
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Running Experience")
                                    .font(Font.stride.headingSmall)

                                ForEach(RunningExperience.allCases, id: \.self) { exp in
                                    Button {
                                        experience = exp
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(exp.rawValue)
                                                    .font(Font.stride.bodyMedium.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                Text(exp.description)
                                                    .font(Font.stride.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if experience == exp {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.stride.lavenderDeep)
                                            }
                                        }
                                        .padding(.vertical, .strideXS)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Weekly Mileage
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Current Weekly Mileage")
                                    .font(Font.stride.headingSmall)

                                HStack {
                                    Text("\(Int(weeklyMiles))")
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.stride.lavenderDeep)
                                    Text(profile.unitPreference.shortLabel + "/week")
                                        .font(Font.stride.bodyMedium)
                                        .foregroundStyle(.secondary)
                                }

                                Slider(value: $weeklyMiles, in: 5...80, step: 1)
                                    .tint(Color.stride.lavender)
                            }
                        }

                        // Zone 2 Pace
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Zone 2 (Easy) Pace")
                                    .font(Font.stride.headingSmall)

                                Text("Your comfortable conversational pace")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Text(zone2Pace > 0
                                        ? zone2Pace.formattedPace(unit: profile.unitPreference)
                                        : "Not set"
                                    )
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.stride.lavenderDeep)
                                    Spacer()
                                }

                                // Simple stepper-style controls
                                HStack(spacing: .strideMD) {
                                    Button {
                                        if zone2Pace == 0 { zone2Pace = 600 }
                                        zone2Pace = max(300, zone2Pace - 15)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundStyle(Color.stride.lavenderDeep)
                                    }

                                    Text("Faster")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Text("Slower")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)

                                    Button {
                                        if zone2Pace == 0 { zone2Pace = 600 }
                                        zone2Pace = min(900, zone2Pace + 15)
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundStyle(Color.stride.lavenderDeep)
                                    }
                                }
                            }
                        }

                        // Schedule
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Schedule")
                                    .font(Font.stride.headingSmall)

                                // Long run day
                                VStack(alignment: .leading, spacing: .strideXS) {
                                    Text("Long Run Day")
                                        .font(Font.stride.bodyMedium)
                                        .foregroundStyle(.secondary)

                                    HStack(spacing: .strideXS) {
                                        ForEach(Weekday.allCases, id: \.self) { day in
                                            Button {
                                                longRunDay = day
                                            } label: {
                                                Text(day.shortName)
                                                    .font(.system(size: 13, weight: longRunDay == day ? .bold : .medium))
                                                    .foregroundStyle(longRunDay == day ? .white : .primary)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 36)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: .strideRadiusSM)
                                                            .fill(longRunDay == day ? Color.stride.lavenderDeep : Color.stride.lavenderLight)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                // Rest days
                                VStack(alignment: .leading, spacing: .strideXS) {
                                    Text("Rest Days")
                                        .font(Font.stride.bodyMedium)
                                        .foregroundStyle(.secondary)

                                    HStack(spacing: .strideXS) {
                                        ForEach(Weekday.allCases, id: \.self) { day in
                                            let isSelected = restDays.contains(day)
                                            Button {
                                                if isSelected {
                                                    restDays.removeAll { $0 == day }
                                                } else {
                                                    restDays.append(day)
                                                }
                                            } label: {
                                                Text(day.shortName)
                                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                                    .foregroundStyle(isSelected ? .white : .primary)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 36)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: .strideRadiusSM)
                                                            .fill(isSelected ? Color.stride.lavenderDeep : Color.stride.lavenderLight)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        // Injury + Strength
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Health & Training")
                                    .font(Font.stride.headingSmall)

                                // Injury
                                VStack(alignment: .leading, spacing: .strideXS) {
                                    Text("Current Injury / Concern")
                                        .font(Font.stride.bodyMedium)
                                        .foregroundStyle(.secondary)

                                    Picker("Injury Region", selection: $injuryRegion) {
                                        ForEach(InjuryRegion.allCases, id: \.self) { region in
                                            Text(region.rawValue).tag(region)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Color.stride.lavenderDeep)
                                }

                                Divider()

                                // Strength training
                                Toggle(isOn: $doesStrength) {
                                    HStack {
                                        Image(systemName: "dumbbell.fill")
                                            .foregroundStyle(Color.stride.lavenderDeep)
                                        Text("Strength Training")
                                            .font(Font.stride.bodyMedium)
                                    }
                                }
                                .tint(Color.stride.lavender)
                            }
                        }

                        Button("Save Changes") { save() }
                            .buttonStyle(StridePrimaryButtonStyle())
                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    private func save() {
        profile.runningExperience = experience
        profile.currentWeeklyMiles = weeklyMiles
        profile.zone2PaceSecondsPerMile = zone2Pace
        profile.preferredLongRunDay = longRunDay
        profile.restDays = restDays
        profile.currentInjuryRegion = injuryRegion
        profile.doesStrengthTraining = doesStrength
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Settings View

struct SettingsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var unitPreference: UnitSystem

    init(profile: UserProfile) {
        self.profile = profile
        var components = DateComponents()
        components.hour = profile.dailyReminderHour
        components.minute = profile.dailyReminderMinute
        let time = Calendar.current.date(from: components) ?? Date()
        self._reminderEnabled = State(initialValue: profile.notificationsEnabled)
        self._reminderTime = State(initialValue: time)
        self._unitPreference = State(initialValue: profile.unitPreference)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {

                        // Notifications
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Notifications")
                                    .font(Font.stride.headingSmall)

                                Toggle("Daily Reminder", isOn: $reminderEnabled)
                                    .tint(Color.stride.lavender)

                                if reminderEnabled {
                                    DatePicker("Reminder Time", selection: $reminderTime,
                                               displayedComponents: .hourAndMinute)
                                        .tint(Color.stride.lavender)
                                }
                            }
                        }

                        // Units
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Distance Units")
                                    .font(Font.stride.headingSmall)

                                Picker("Units", selection: $unitPreference) {
                                    ForEach(UnitSystem.allCases, id: \.self) { unit in
                                        Text(unit.rawValue).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        Button("Save") { save() }
                            .buttonStyle(StridePrimaryButtonStyle())
                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    private func save() {
        let hour = Calendar.current.component(.hour, from: reminderTime)
        let minute = Calendar.current.component(.minute, from: reminderTime)
        profile.notificationsEnabled = reminderEnabled
        profile.dailyReminderHour = hour
        profile.dailyReminderMinute = minute
        profile.unitPreference = unitPreference
        try? modelContext.save()
        NotificationManager.shared.scheduleAll(for: profile)
        dismiss()
    }
}
