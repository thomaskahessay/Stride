import SwiftUI
import SwiftData
import MapKit

// MARK: - Log Mode

private enum LogMode: Equatable {
    case selectSource
    case pickFromHealthKit
    case manualEntry
}

// MARK: - LogWorkoutView

struct LogWorkoutView: View {
    let workoutDay: WorkoutDay?
    var units: UnitSystem = .kilometers
    var weeklyLoggedMiles: Double = 0
    var weeklyTargetMiles: Double = 0
    var isEditing: Bool = false
    var prefillHealthKitData: HealthKitWorkoutData? = nil
    var plan: TrainingPlan? = nil
    @Binding var showConfettiOnParent: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var savedRoutes: [Route]

    @State private var mode: LogMode = .selectSource
    @State private var selectedHKWorkout: HealthKitWorkoutData? = nil

    // Form state — distance stored internally as miles
    @State private var distanceMiles: Double = 0
    @State private var durationHours: Int = 0
    @State private var durationMinutes: Int = 0
    @State private var durationSeconds: Int = 0
    @State private var effortRating: Int = 5
    @State private var notes: String = ""
    @State private var heartRateText: String = ""
    @State private var paceText: String = ""       // "m:ss" — empty = use computed
    @State private var isSaving = false
    @State private var showAlreadyLoggedAlert = false
    @State private var distanceText: String = ""
    @FocusState private var isDistanceFocused: Bool

    // Strength day → run override
    @State private var logRunOnStrengthDay = false

    // Workout type override — pre-filled from planned type, changeable
    @State private var selectedWorkoutType: WorkoutType = .easyRun

    // Venue & route
    @State private var selectedVenue: RunVenue?         // nil = not yet chosen (legacy)
    @State private var selectedRoute: Route?
    @State private var showRoutePicker = false

    // Rest-day specific
    @State private var restDayActivityType: RestDayActivityType = .crossTraining

    // Swap state (for strength day "Also Log a Run" picker)
    @State private var showStrengthRunPicker = false
    @State private var swapSnapshots: (source: SwapSnapshot, target: SwapSnapshot)?
    @State private var swapPartnerDay: WorkoutDay?
    @State private var didSave = false
    private let swapService = WorkoutSwapService()

    private let healthKit = HealthKitManager.shared

    private var isRestDayLog: Bool {
        workoutDay?.workoutType == .restDay
    }

    private var isStrengthDayLog: Bool {
        workoutDay?.workoutType == .strengthDay && !logRunOnStrengthDay
    }

    private var isCrossTrainingLog: Bool {
        isRestDayLog && restDayActivityType == .crossTraining
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                Group {
                    if isStrengthDayLog {
                        strengthDayForm
                    } else {
                        switch mode {
                        case .selectSource:
                            LogSourcePickerView(
                                recentWorkoutCount: healthKit.recentWorkouts.count,
                                isRefreshing: healthKit.isRefreshing,
                                onHealthKit: { mode = .pickFromHealthKit },
                                onManual: {
                                    prefillFromWorkoutDay()
                                    mode = .manualEntry
                                },
                                onRefresh: {
                                    Task { await healthKit.fetchRecentWorkouts() }
                                }
                            )
                            .task { await healthKit.fetchRecentWorkouts() }

                        case .pickFromHealthKit:
                            HealthKitWorkoutPickerView(
                                workouts: healthKit.recentWorkouts,
                                units: units,
                                onSelect: { data in
                                    selectedHKWorkout = data
                                    applyHealthKitData(data)
                                    mode = .manualEntry
                                }
                            )

                        case .manualEntry:
                            manualEntryForm
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: mode)

            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(leadingLabel) { leadingAction() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
            .alert("Already Logged", isPresented: $showAlreadyLoggedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("You've already logged a workout for today. View or edit it from the workout detail screen.")
            }
            .onAppear {
                if isEditing, let log = workoutDay?.log {
                    prefillFromExistingLog(log)
                } else if let hkData = prefillHealthKitData {
                    selectedHKWorkout = hkData
                    applyHealthKitData(hkData)
                    mode = .manualEntry
                }
            }
            .onDisappear {
                revertSwapIfNeeded()
            }
            .sheet(isPresented: $showStrengthRunPicker) {
                if let workout = workoutDay, let plan = plan {
                    SwapWorkoutPickerView(
                        viewModel: SwapWorkoutPickerViewModel(
                            source: workout,
                            plan: plan,
                            runOnly: true,
                            showCustomRunOption: true
                        ),
                        units: units,
                        onSwapCompleted: { snapSource, snapTarget, targetDay in
                            swapSnapshots = (source: snapSource, target: snapTarget)
                            swapPartnerDay = targetDay
                            // The partner day received the strength workout, but the user
                            // already completed strength today — make it a rest day instead.
                            targetDay.workoutType = .restDay
                            targetDay.targetDistanceMiles = 0
                            targetDay.targetDurationMinutes = 0
                            targetDay.targetPaceSecPerMile = nil
                            targetDay.effortLevel = .easy
                            targetDay.workoutTitle = "Rest Day"
                            targetDay.coachingNote = "Rest is training. Your body adapts and gets stronger during recovery, not during the run. Sleep well, eat well, and keep your feet up where possible."
                            targetDay.stepsData = nil
                            logRunOnStrengthDay = true
                            mode = .selectSource
                        },
                        onCustomRun: {
                            logRunOnStrengthDay = true
                            mode = .selectSource
                        }
                    )
                }
            }
        }
    }

    // MARK: - Navigation helpers

    private var navigationTitle: String {
        if isStrengthDayLog { return isEditing ? "Edit Strength" : "Log Strength" }
        switch mode {
        case .selectSource: return isEditing ? "Edit Workout" : "Log Workout"
        case .pickFromHealthKit: return "Select Run"
        case .manualEntry: return selectedHKWorkout != nil ? "Confirm Import" : "Log Workout"
        }
    }

    private var leadingLabel: String {
        if isStrengthDayLog { return "Cancel" }
        switch mode {
        case .selectSource: return logRunOnStrengthDay ? "Back" : "Cancel"
        case .pickFromHealthKit: return "Back"
        case .manualEntry: return selectedHKWorkout != nil ? "Back" : (logRunOnStrengthDay ? "Back" : "Cancel")
        }
    }

    private func leadingAction() {
        if isStrengthDayLog { dismiss(); return }
        switch mode {
        case .selectSource:
            if logRunOnStrengthDay {
                logRunOnStrengthDay = false
            } else {
                dismiss()
            }
        case .pickFromHealthKit:
            mode = .selectSource
        case .manualEntry:
            if selectedHKWorkout != nil {
                selectedHKWorkout = nil
                mode = .pickFromHealthKit
            } else {
                mode = .selectSource
            }
        }
    }

    // MARK: - Strength Day Form

    private var strengthDayForm: some View {
        VStack(spacing: .strideMD) {
            Spacer()

            VStack(spacing: .strideMD) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.stride.sky)

                Text(workoutDay?.workoutTitle ?? "Strength Day")
                    .font(Font.stride.headingMedium)

                Text("Mark this strength session as complete")
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Optional notes
            GlassCard {
                VStack(alignment: .leading, spacing: .strideSM) {
                    Label("Notes (optional)", systemImage: "text.bubble")
                        .font(Font.stride.headingSmall)

                    TextField(
                        "Any thoughts on the session...",
                        text: $notes,
                        axis: .vertical
                    )
                    .font(Font.stride.bodyMedium)
                    .lineLimit(3...6)
                    .onChange(of: notes) {
                        if notes.count > 500 { notes = String(notes.prefix(500)) }
                    }
                }
            }
            .padding(.horizontal, .strideMD)

            Spacer()

            Button("Mark as Complete") { saveStrengthDay() }
                .buttonStyle(StridePrimaryButtonStyle())
                .padding(.horizontal, .strideMD)
                .disabled(isSaving)

            Button {
                if plan != nil {
                    showStrengthRunPicker = true
                } else {
                    logRunOnStrengthDay = true
                    mode = .selectSource
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                    Text("Also Log a Run")
                }
            }
            .buttonStyle(StrideSecondaryButtonStyle())
            .padding(.horizontal, .strideMD)
            .padding(.bottom, .strideMD)
        }
    }

    // MARK: - Swap Revert

    private func revertSwapIfNeeded() {
        guard !didSave,
              let snapshots = swapSnapshots,
              let workout = workoutDay,
              let partner = swapPartnerDay else { return }
        swapService.restoreSnapshot(snapshots.source, onto: workout)
        swapService.restoreSnapshot(snapshots.target, onto: partner)
        swapSnapshots = nil
        swapPartnerDay = nil
    }

    // MARK: - Manual Entry Form

    private var manualEntryForm: some View {
        ScrollView {
            VStack(spacing: .strideMD) {

                // Import confirmation banner
                if let hkData = selectedHKWorkout {
                    HKImportBanner(data: hkData, units: units)
                }

                // Workout type picker — lets user label what they actually did
                if !isRestDayLog && !isStrengthDayLog {
                    workoutTypePicker
                }

                // Venue picker — outdoor / treadmill / track
                if !isRestDayLog || (isRestDayLog && restDayActivityType.countsTowardRunningVolume) {
                    if !isStrengthDayLog {
                        venuePicker
                    }
                }

                // Route attachment (outdoor only, when venue is outdoor and routes exist)
                if !savedRoutes.isEmpty || selectedRoute != nil {
                    if selectedVenue == .outdoor && (!isRestDayLog || (isRestDayLog && restDayActivityType.countsTowardRunningVolume)) {
                        routeAttachmentCard
                    }
                }

                // Rest-day activity type selector
                if isRestDayLog {
                    restDayActivityPicker
                }

                // Mileage warning for rest-day runs
                if isRestDayLog && restDayActivityType.countsTowardRunningVolume {
                    mileageWarningBanner
                }

                // Hide running metrics for cross-training
                if !isCrossTrainingLog {
                    // Distance
                    GlassCard {
                        VStack(alignment: .leading, spacing: .strideSM) {
                            Label("Distance", systemImage: "road.lanes")
                                .font(Font.stride.headingSmall)

                            HStack(alignment: .firstTextBaseline) {
                                TextField(
                                    "0.0",
                                    text: $distanceText
                                )
                                .keyboardType(.decimalPad)
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .frame(maxWidth: 160)
                                .focused($isDistanceFocused)
                                .onChange(of: distanceText) {
                                    // Allow only digits and at most one decimal point with 1 decimal place
                                    var filtered = distanceText.filter { $0.isNumber || $0 == "." }
                                    // Remove extra decimal points
                                    let dotCount = filtered.filter { $0 == "." }.count
                                    if dotCount > 1 {
                                        var seenDot = false
                                        filtered = String(filtered.filter { c in
                                            if c == "." {
                                                if seenDot { return false }
                                                seenDot = true
                                            }
                                            return true
                                        })
                                    }
                                    // Limit to 1 decimal place
                                    if let dotIndex = filtered.firstIndex(of: ".") {
                                        let afterDot = filtered[filtered.index(after: dotIndex)...]
                                        if afterDot.count > 1 {
                                            filtered = String(filtered[...dotIndex]) + String(afterDot.prefix(1))
                                        }
                                    }
                                    if filtered != distanceText {
                                        distanceText = filtered
                                    }
                                    if !isDistanceFocused {
                                        syncDistanceFromText()
                                    }
                                }
                                .onSubmit { syncDistanceFromText() }
                                .onChange(of: isDistanceFocused) {
                                    if !isDistanceFocused {
                                        syncDistanceFromText()
                                    }
                                }

                                Text(units.shortLabel)
                                    .font(Font.stride.headingSmall)
                                    .foregroundStyle(.secondary)

                                if isDistanceFocused {
                                    Spacer()
                                    Button("Done") {
                                        isDistanceFocused = false
                                    }
                                    .font(Font.stride.bodyMedium.weight(.semibold))
                                    .foregroundStyle(Color.stride.lavenderDeep)
                                    .transition(.opacity)
                                }
                            }

                            Slider(value: distanceKmBinding, in: 0...80, step: 0.1)
                                .tint(Color.stride.lavender)
                                .onChange(of: distanceMiles) {
                                    if !isDistanceFocused {
                                        distanceText = String(format: "%.1f", units.convert(distanceMiles))
                                    }
                                }
                        }
                    }

                    // Duration
                    GlassCard {
                        VStack(alignment: .leading, spacing: .strideSM) {
                            Label("Duration", systemImage: "clock.fill")
                                .font(Font.stride.headingSmall)

                            HStack(spacing: 0) {
                                Spacer()
                                durationPicker(label: "h", binding: $durationHours, range: 0...8)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                durationPicker(label: "m", binding: $durationMinutes, range: 0...59)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                durationPicker(label: "s", binding: $durationSeconds, range: 0...59)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Performance — pace (computed) + optional HR
                    GlassCard {
                        VStack(alignment: .leading, spacing: .strideSM) {
                            Label("Performance", systemImage: "chart.xyaxis.line")
                                .font(Font.stride.headingSmall)

                            Divider()

                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Avg Pace")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 4) {
                                        TextField(computedPaceFormatted, text: $paceText)
                                            .keyboardType(.numbersAndPunctuation)
                                            .font(Font.stride.bodyMedium.weight(.semibold))
                                            .frame(width: 56)
                                            .onChange(of: paceText) {
                                                // Allow digits and one colon only
                                                let filtered = paceText.filter { $0.isNumber || $0 == ":" }
                                                if filtered != paceText { paceText = filtered }
                                            }
                                        Text("/ \(units.shortLabel)")
                                            .font(Font.stride.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Avg Heart Rate")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 4) {
                                        TextField("—", text: $heartRateText)
                                            .keyboardType(.numberPad)
                                            .font(Font.stride.bodyMedium.weight(.semibold))
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 52)
                                            .onChange(of: heartRateText) {
                                                heartRateText = String(
                                                    heartRateText.prefix(3).filter { $0.isNumber }
                                                )
                                            }
                                        Text("bpm")
                                            .font(Font.stride.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Effort Rating
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Label("Effort — RPE \(effortRating)", systemImage: "speedometer")
                            .font(Font.stride.headingSmall)

                        Text(rpeDescription)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)

                        RPESlider(value: $effortRating)
                    }
                }

                // Notes
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Label("Notes", systemImage: "text.bubble")
                            .font(Font.stride.headingSmall)

                        TextField(
                            "How did it go? Any aches, wins, or thoughts...",
                            text: $notes,
                            axis: .vertical
                        )
                        .font(Font.stride.bodyMedium)
                        .lineLimit(3...6)
                        .onChange(of: notes) {
                            if notes.count > 500 { notes = String(notes.prefix(500)) }
                        }
                    }
                }

                Spacer(minLength: 80)
            }
            .padding(.strideMD)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button("Save Workout") { save() }
                .buttonStyle(StridePrimaryButtonStyle())
                .padding(.strideMD)
                .background(.ultraThinMaterial)
                .disabled(isSaving || (!isCrossTrainingLog && !hasRequiredFields))
        }
    }

    // MARK: - Computed

    private var hasRequiredFields: Bool {
        distanceMiles > 0 && totalDurationSeconds > 0
    }

    private var distanceKmBinding: Binding<Double> {
        Binding(
            get: { distanceMiles * 1.60934 },
            set: { distanceMiles = $0 / 1.60934 }
        )
    }

    private var totalDurationSeconds: Int {
        durationHours * 3600 + durationMinutes * 60 + durationSeconds
    }

    /// Pace computed from the current distance + duration fields, in display units.
    private var computedPaceSecPerDisplayUnit: Int? {
        guard distanceMiles > 0, totalDurationSeconds > 0 else { return nil }
        let displayDist = units == .kilometers ? distanceMiles * 1.60934 : distanceMiles
        return Int(Double(totalDurationSeconds) / displayDist)
    }

    /// Formatted computed pace used as the text field placeholder.
    private var computedPaceFormatted: String {
        guard let pace = computedPaceSecPerDisplayUnit else { return "—" }
        return formatPace(pace)
    }

    private func formatPace(_ secPerUnit: Int) -> String {
        String(format: "%d:%02d", secPerUnit / 60, secPerUnit % 60)
    }

    /// Parse "m:ss" from paceText. Returns nil if blank or malformed.
    private func parsedPaceSecPerDisplayUnit() -> Int? {
        let trimmed = paceText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", maxSplits: 1).map { String($0) }
        guard parts.count == 2,
              let m = Int(parts[0]),
              let s = Int(parts[1]),
              s < 60 else { return nil }
        return m * 60 + s
    }

    /// Effective pace in sec/mile for storage — user entry takes priority, falls back to computed.
    private var effectivePaceSecPerMile: Int? {
        let secPerDisplayUnit = parsedPaceSecPerDisplayUnit() ?? computedPaceSecPerDisplayUnit
        guard let pace = secPerDisplayUnit else { return nil }
        return units == .kilometers ? Int(Double(pace) * 1.60934) : pace
    }

    private var parsedHeartRate: Double? {
        guard let bpm = Double(heartRateText), bpm > 0 else { return nil }
        return bpm
    }

    // MARK: - Venue Picker

    private var venuePicker: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Where did you run?", systemImage: "location.fill")
                    .font(Font.stride.headingSmall)

                HStack(spacing: 8) {
                    ForEach(RunVenue.allCases, id: \.self) { venue in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedVenue = venue
                                // Clear route if switching away from outdoor
                                if venue != .outdoor {
                                    selectedRoute = nil
                                }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: venue.sfSymbol)
                                    .font(.system(size: 18, weight: .semibold))
                                Text(venue.rawValue)
                                    .font(Font.stride.label)
                            }
                            .foregroundStyle(
                                selectedVenue == venue ? .white : Color.stride.lavenderDeep
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: .strideRadiusSM)
                                    .fill(
                                        selectedVenue == venue
                                            ? Color.stride.lavenderDeep
                                            : Color.stride.lavenderLight
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Route Attachment Card

    private var routeAttachmentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Route", systemImage: "map.fill")
                    .font(Font.stride.headingSmall)

                if let route = selectedRoute {
                    // Selected route preview
                    HStack(spacing: .strideSM) {
                        RouteThumbnail(
                            waypoints: route.waypoints,
                            polyline: route.polylineCoordinates,
                            isLoop: route.isLoop,
                            size: 56
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.name)
                                .font(Font.stride.bodyMedium.weight(.semibold))
                                .lineLimit(1)
                            Text(String(format: "%.1f km", route.distance / 1000))
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            withAnimation { selectedRoute = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        showRoutePicker = true
                    } label: {
                        HStack(spacing: .strideSM) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.stride.lavenderDeep)
                            Text("Attach a route")
                                .font(Font.stride.bodyMedium)
                                .foregroundStyle(Color.stride.lavenderDeep)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showRoutePicker) {
            RoutePickerView(
                targetDistanceMiles: workoutDay?.targetDistanceMiles ?? 0,
                selectedRoute: $selectedRoute
            )
        }
    }

    // MARK: - Workout Type Picker

    private static let runnableTypes: [WorkoutType] = [
        .easyRun, .longRun, .tempoRun, .intervalRun, .recoveryRun
    ]

    private var workoutTypePicker: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("What did you do?", systemImage: "figure.run")
                    .font(Font.stride.headingSmall)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.runnableTypes, id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedWorkoutType = type
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: type.sfSymbol)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(type.rawValue)
                                        .font(Font.stride.label)
                                }
                                .foregroundStyle(
                                    selectedWorkoutType == type
                                        ? .white
                                        : type.accentColor
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            selectedWorkoutType == type
                                                ? type.accentColor
                                                : type.accentColor.opacity(0.12)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rest Day Components

    private var restDayActivityPicker: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("What did you do?", systemImage: "figure.mixed.cardio")
                    .font(Font.stride.headingSmall)

                ForEach(RestDayActivityType.allCases, id: \.self) { activity in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            restDayActivityType = activity
                        }
                    } label: {
                        HStack(spacing: .strideSM) {
                            Image(systemName: activity.sfSymbol)
                                .font(.system(size: 18))
                                .frame(width: 28)
                                .foregroundStyle(
                                    restDayActivityType == activity
                                        ? Color.stride.lavenderDeep
                                        : .secondary
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.rawValue)
                                    .font(Font.stride.bodyMedium.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(activity.description)
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: restDayActivityType == activity
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundStyle(
                                    restDayActivityType == activity
                                        ? Color.stride.lavender
                                        : Color(.systemGray4)
                                )
                                .font(.system(size: 22))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    if activity != RestDayActivityType.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    private var mileageWarningBanner: some View {
        let projectedTotal = weeklyLoggedMiles + distanceMiles
        let overagePercent = weeklyTargetMiles > 0
            ? ((projectedTotal - weeklyTargetMiles) / weeklyTargetMiles) * 100
            : 0

        return Group {
            if projectedTotal > weeklyTargetMiles * 1.10 {
                GlassCard {
                    HStack(spacing: .strideSM) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Heads up — extra volume")
                                .font(Font.stride.bodyMedium.weight(.semibold))
                            Text("This puts you at \(String(format: "%.1f", units.convert(projectedTotal))) \(units.shortLabel) this week — \(Int(overagePercent))% above your plan. Overtraining increases injury risk.")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func syncDistanceFromText() {
        if let value = Double(distanceText), value >= 0 {
            let clamped = min(value, 80)
            distanceMiles = units == .kilometers ? clamped / 1.60934 : clamped
            distanceText = String(format: "%.1f", clamped)
        } else if distanceText.isEmpty {
            distanceMiles = 0
        }
    }

    private func prefillFromExistingLog(_ log: WorkoutLog) {
        distanceMiles = log.actualDistanceMiles
        distanceText = String(format: "%.1f", units.convert(log.actualDistanceMiles))
        let total = log.actualDurationSeconds
        durationHours = total / 3600
        durationMinutes = (total % 3600) / 60
        durationSeconds = total % 60
        effortRating = log.effortRating
        notes = log.notes
        if let hr = log.averageHeartRate {
            heartRateText = String(Int(hr.rounded()))
        }
        if let pace = log.averagePaceSecPerMile {
            let displayPace = units == .kilometers
                ? Int(Double(pace) / 1.60934)
                : pace
            paceText = formatPace(displayPace)
        }
        if let typeOverride = log.actualWorkoutType {
            selectedWorkoutType = typeOverride
        } else if let workout = workoutDay {
            selectedWorkoutType = workout.workoutType.isRun ? workout.workoutType : .easyRun
        }
        if log.strengthCompleted {
            logRunOnStrengthDay = true
        }
        if let activity = log.restDayActivityType {
            restDayActivityType = activity
        }
        selectedVenue = log.runVenue
        selectedRoute = log.route
        // For editing, skip source selection and go straight to manual entry
        // (unless it's a strength-only log with no run data)
        if workoutDay?.workoutType == .strengthDay && !log.strengthCompleted {
            // Stay on strength day form
        } else {
            mode = .manualEntry
        }
    }

    private func prefillFromWorkoutDay() {
        guard let workout = workoutDay else { return }
        distanceMiles = workout.targetDistanceMiles
        distanceText = String(format: "%.1f", units.convert(workout.targetDistanceMiles))
        selectedWorkoutType = workout.workoutType.isRun ? workout.workoutType : .easyRun
        // Prefill duration from target pace if available: time = distance × pace
        if let paceSecPerMile = workout.targetPaceSecPerMile, workout.targetDistanceMiles > 0 {
            let totalSeconds = Int(Double(paceSecPerMile) * workout.targetDistanceMiles)
            durationHours = totalSeconds / 3600
            durationMinutes = (totalSeconds % 3600) / 60
            durationSeconds = totalSeconds % 60
        } else {
            durationHours = 0
            durationMinutes = 0
            durationSeconds = 0
        }
    }

    private func applyHealthKitData(_ data: HealthKitWorkoutData) {
        distanceMiles = data.distanceMiles
        distanceText = String(format: "%.1f", units.convert(data.distanceMiles))
        let total = data.durationSeconds
        durationHours = total / 3600
        durationMinutes = (total % 3600) / 60
        durationSeconds = total % 60
        if let hr = data.averageHeartRate {
            heartRateText = String(Int(hr.rounded()))
        }
        // Pre-fill pace from HK data (in display units)
        if let paceSecPerMile = data.averagePaceSecPerMile {
            let displayPace = units == .kilometers
                ? Int(Double(paceSecPerMile) / 1.60934)
                : paceSecPerMile
            paceText = formatPace(displayPace)
        }
    }

    private func durationPicker(label: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            Picker("", selection: binding) {
                ForEach(range, id: \.self) { v in
                    Text(String(format: "%02d", v)).tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 80)
            .clipped()

            Text(label)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Save Strength Day

    private func saveStrengthDay() {
        guard let workout = workoutDay else { return }

        if workout.log != nil && !isEditing {
            showAlreadyLoggedAlert = true
            return
        }

        isSaving = true
        didSave = true

        if isEditing, let existing = workout.log {
            existing.notes = notes
            try? modelContext.save()
            dismiss()
            return
        }

        let log = WorkoutLog(
            actualDistanceMiles: 0,
            actualDurationSeconds: 0,
            effortRating: 5,
            notes: notes,
            sourceHealthKit: false,
            averageHeartRate: nil,
            averagePaceSecPerMile: nil,
            restDayActivityType: nil
        )

        modelContext.insert(log)
        workout.log = log
        workout.isCompleted = true
        try? modelContext.save()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showConfettiOnParent = true
        NotificationCenter.default.post(name: Notification.Name("workoutLogged"), object: nil)
        dismiss()
    }

    // MARK: - Save

    private func save() {
        guard let workout = workoutDay else { return }

        // Prevent overwriting an existing log (unless editing)
        if workout.log != nil && !isEditing {
            showAlreadyLoggedAlert = true
            return
        }

        isSaving = true
        didSave = true

        // Store actual workout type if it differs from the planned type
        let typeOverride: WorkoutType? = (selectedWorkoutType != workout.workoutType)
            ? selectedWorkoutType
            : nil

        if isEditing, let existing = workout.log {
            existing.actualDistanceMiles = distanceMiles
            existing.actualDurationSeconds = totalDurationSeconds
            existing.effortRating = effortRating
            existing.notes = notes
            existing.sourceHealthKit = selectedHKWorkout != nil
            existing.averageHeartRate = parsedHeartRate
            existing.averagePaceSecPerMile = effectivePaceSecPerMile
            existing.restDayActivityType = isRestDayLog ? restDayActivityType : nil
            existing.actualWorkoutType = typeOverride
            existing.strengthCompleted = logRunOnStrengthDay
            existing.runVenue = selectedVenue
            existing.route = selectedRoute
            try? modelContext.save()
            NotificationCenter.default.post(name: Notification.Name("workoutLogged"), object: nil)
            dismiss()
            return
        }

        let log = WorkoutLog(
            actualDistanceMiles: distanceMiles,
            actualDurationSeconds: totalDurationSeconds,
            effortRating: effortRating,
            notes: notes,
            sourceHealthKit: selectedHKWorkout != nil,
            averageHeartRate: parsedHeartRate,
            averagePaceSecPerMile: effectivePaceSecPerMile,
            restDayActivityType: isRestDayLog ? restDayActivityType : nil,
            actualWorkoutType: typeOverride,
            strengthCompleted: logRunOnStrengthDay,
            runVenue: selectedVenue,
            route: selectedRoute
        )

        modelContext.insert(log)
        workout.log = log
        workout.isCompleted = true
        try? modelContext.save()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showConfettiOnParent = true
        NotificationCenter.default.post(name: Notification.Name("workoutLogged"), object: nil)
        dismiss()
    }

    // MARK: - RPE Description

    private var rpeDescription: String {
        switch effortRating {
        case 1...3: return "Very easy — barely breaking a sweat"
        case 4...5: return "Easy to moderate — comfortable, sustainable"
        case 6...7: return "Moderately hard — working, but in control"
        case 8...9: return "Hard — very uncomfortable, short bursts"
        case 10:    return "Maximum — all out, unsustainable"
        default:    return ""
        }
    }
}

// MARK: - LogSourcePickerView

private struct LogSourcePickerView: View {
    let recentWorkoutCount: Int
    let isRefreshing: Bool
    let onHealthKit: () -> Void
    let onManual: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: .strideMD) {
            Text("How would you like to log?")
                .font(Font.stride.headingMedium)
                .multilineTextAlignment(.center)
                .padding(.top, .strideLG)

            // Apple Health option
            Button(action: onHealthKit) {
                GlassCard {
                    HStack(spacing: .strideMD) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: "heart.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import from Apple Health")
                                .font(Font.stride.bodyMedium.weight(.semibold))
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if isRefreshing {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("Syncing...")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(
                                        recentWorkoutCount > 0
                                            ? "\(recentWorkoutCount) recent run\(recentWorkoutCount == 1 ? "" : "s") available"
                                            : "No recent runs found"
                                    )
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.stride.lavenderDeep)
                        }
                        .disabled(isRefreshing)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(recentWorkoutCount == 0)
            .opacity(recentWorkoutCount == 0 ? 0.5 : 1)

            // Manual option
            Button(action: onManual) {
                GlassCard {
                    HStack(spacing: .strideMD) {
                        ZStack {
                            Circle()
                                .fill(Color.stride.lavender.opacity(0.2))
                                .frame(width: 52, height: 52)
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.stride.lavenderDeep)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Log Manually")
                                .font(Font.stride.bodyMedium.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Enter distance, time, pace, and effort")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.strideMD)
    }
}

// MARK: - HealthKitWorkoutPickerView

private struct HealthKitWorkoutPickerView: View {
    let workouts: [HealthKitWorkoutData]
    let units: UnitSystem
    let onSelect: (HealthKitWorkoutData) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: .strideSM) {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Recent Runs",
                        systemImage: "figure.run.circle",
                        description: Text("No running workouts found in the past 7 days.")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(workouts, id: \.workoutDate) { workout in
                        Button { onSelect(workout) } label: {
                            GlassCard {
                                HStack(spacing: .strideSM) {
                                    // Date column
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workout.workoutDate.formatted(.dateTime.weekday(.wide)))
                                            .font(Font.stride.bodyMedium.weight(.semibold))
                                        Text(workout.workoutDate.formatted(.dateTime.month().day().hour().minute()))
                                            .font(Font.stride.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    // Distance + duration
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(String(format: "%.1f %@",
                                             units.convert(workout.distanceMiles),
                                             units.shortLabel))
                                            .font(Font.stride.bodyMedium.weight(.semibold))
                                        Text(formattedDuration(workout.durationSeconds))
                                            .font(Font.stride.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    // Heart rate (if available)
                                    if let hr = workout.averageHeartRate {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            HStack(spacing: 2) {
                                                Image(systemName: "heart.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.red)
                                                Text("\(Int(hr.rounded()))")
                                                    .font(Font.stride.bodyMedium.weight(.semibold))
                                            }
                                            Text("bpm")
                                                .font(Font.stride.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.footnote)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.strideMD)
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }
}

// MARK: - HK Import Banner

private struct HKImportBanner: View {
    let data: HealthKitWorkoutData
    let units: UnitSystem

    var body: some View {
        GlassCard {
            HStack(spacing: .strideSM) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Imported from Apple Health")
                        .font(Font.stride.bodyMedium.weight(.semibold))
                    Text(
                        "\(data.workoutDate.formatted(.dateTime.weekday().month().day().hour().minute())) · Adjust below if needed"
                    )
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

// MARK: - RPE Slider

private struct RPESlider: View {
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...10, id: \.self) { i in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            value = i
                        }
                    } label: {
                        Circle()
                            .fill(i <= value ? Color.stride.lavender : Color.stride.lavenderLight)
                            .overlay(
                                Text("\(i)")
                                    .font(Font.stride.label)
                                    .foregroundStyle(i <= value ? .white : Color.stride.lavenderDeep)
                            )
                            .frame(height: 32)
                    }
                }
            }

            HStack {
                Text("Easy").font(Font.stride.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Max").font(Font.stride.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Confetti Overlay (Canvas particle system)

struct ConfettiOverlay: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var startDate: Date = .now

    private static let particleCount = 120
    private static let colors: [Color] = [
        .stride.lavender, .stride.lavenderDeep, .stride.lavenderLight,
        .stride.mint, .stride.sky, .white
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)

            Canvas { context, size in
                for particle in particles {
                    let age = elapsed - particle.delay
                    guard age > 0 else { continue }

                    let progress = min(age / particle.lifetime, 1.0)

                    // Physics: gravity + lateral drift + drag
                    let gravity: CGFloat = 420
                    let drag: CGFloat = 1.0 - (0.3 * progress)
                    let x = particle.startX * size.width
                        + particle.velocityX * CGFloat(age) * drag
                    let y = particle.startY
                        + particle.velocityY * CGFloat(age) * drag
                        + 0.5 * gravity * CGFloat(age * age)

                    // Fade out in final 40%
                    let opacity = progress < 0.6 ? 1.0 : max(0, 1.0 - (progress - 0.6) / 0.4)
                    guard opacity > 0, y < size.height + 20 else { continue }

                    // Spin
                    let angle = Angle.degrees(particle.spinRate * age)

                    var contextCopy = context
                    contextCopy.opacity = opacity
                    contextCopy.translateBy(x: x, y: y)
                    contextCopy.rotate(by: angle)

                    let rect = CGRect(
                        x: -particle.width / 2,
                        y: -particle.height / 2,
                        width: particle.width,
                        height: particle.height
                    )

                    switch particle.shape {
                    case .rectangle:
                        contextCopy.fill(
                            Path(roundedRect: rect, cornerRadius: 2),
                            with: .color(particle.color)
                        )
                    case .circle:
                        contextCopy.fill(
                            Path(ellipseIn: rect),
                            with: .color(particle.color)
                        )
                    case .strip:
                        contextCopy.fill(
                            Path(roundedRect: rect, cornerRadius: 1),
                            with: .color(particle.color)
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            startDate = .now
            particles = (0..<Self.particleCount).map { _ in
                ConfettiParticle.random(colors: Self.colors)
            }
        }
    }
}

// MARK: - Confetti Particle Model

private struct ConfettiParticle {
    enum Shape: CaseIterable { case rectangle, circle, strip }

    let startX: CGFloat      // 0...1 fraction of canvas width
    let startY: CGFloat      // absolute points (negative = above screen)
    let velocityX: CGFloat   // pts/sec lateral
    let velocityY: CGFloat   // pts/sec initial upward (negative)
    let width: CGFloat
    let height: CGFloat
    let color: Color
    let shape: Shape
    let spinRate: Double      // degrees/sec
    let delay: Double         // seconds before appearing
    let lifetime: Double      // total seconds alive

    static func random(colors: [Color]) -> ConfettiParticle {
        let shape = Shape.allCases.randomElement() ?? .rectangle
        let baseSize = CGFloat.random(in: 6...12)
        let width: CGFloat
        let height: CGFloat

        switch shape {
        case .rectangle:
            width = baseSize
            height = baseSize * CGFloat.random(in: 0.5...0.8)
        case .circle:
            width = baseSize * 0.8
            height = width
        case .strip:
            width = baseSize * 0.4
            height = baseSize * CGFloat.random(in: 1.2...2.0)
        }

        return ConfettiParticle(
            startX: CGFloat.random(in: 0.1...0.9),
            startY: CGFloat.random(in: -40...20),
            velocityX: CGFloat.random(in: -120...120),
            velocityY: CGFloat.random(in: -350 ... -100),
            width: width,
            height: height,
            color: colors.randomElement() ?? .white,
            shape: shape,
            spinRate: Double.random(in: -400...400),
            delay: Double.random(in: 0...1.0),
            lifetime: Double.random(in: 3.0...5.0)
        )
    }
}
