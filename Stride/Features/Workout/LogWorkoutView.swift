import SwiftUI
import SwiftData

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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var mode: LogMode = .selectSource
    @State private var selectedHKWorkout: HealthKitWorkoutData? = nil

    // Form state — distance stored internally as miles
    @State private var distanceMiles: Double = 0
    @State private var durationHours: Int = 0
    @State private var durationMinutes: Int = 30
    @State private var durationSeconds: Int = 0
    @State private var effortRating: Int = 5
    @State private var notes: String = ""
    @State private var heartRateText: String = ""
    @State private var paceText: String = ""       // "m:ss" — empty = use computed
    @State private var showConfetti = false
    @State private var isSaving = false

    private let healthKit = HealthKitManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                Group {
                    switch mode {
                    case .selectSource:
                        LogSourcePickerView(
                            recentWorkoutCount: healthKit.recentWorkouts.count,
                            onHealthKit: { mode = .pickFromHealthKit },
                            onManual: {
                                prefillFromWorkoutDay()
                                mode = .manualEntry
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
                .animation(.easeInOut(duration: 0.2), value: mode)

                if showConfetti {
                    ConfettiOverlay()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(leadingLabel) { leadingAction() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    // MARK: - Navigation helpers

    private var navigationTitle: String {
        switch mode {
        case .selectSource: return "Log Workout"
        case .pickFromHealthKit: return "Select Run"
        case .manualEntry: return selectedHKWorkout != nil ? "Confirm Import" : "Log Workout"
        }
    }

    private var leadingLabel: String {
        switch mode {
        case .selectSource: return "Cancel"
        case .pickFromHealthKit: return "Back"
        case .manualEntry: return selectedHKWorkout != nil ? "Back" : "Cancel"
        }
    }

    private func leadingAction() {
        switch mode {
        case .selectSource:
            dismiss()
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

    // MARK: - Manual Entry Form

    private var manualEntryForm: some View {
        ScrollView {
            VStack(spacing: .strideMD) {

                // Import confirmation banner
                if let hkData = selectedHKWorkout {
                    HKImportBanner(data: hkData, units: units)
                }

                // Distance
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Label("Distance", systemImage: "road.lanes")
                            .font(Font.stride.headingSmall)

                        HStack {
                            Text(String(format: "%.1f", units.convert(distanceMiles)))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                            Text(units.shortLabel)
                                .font(Font.stride.headingSmall)
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: distanceKmBinding, in: 0...80, step: 0.1)
                            .tint(Color.stride.lavender)
                    }
                }

                // Duration
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Label("Duration", systemImage: "clock.fill")
                            .font(Font.stride.headingSmall)

                        HStack(spacing: 0) {
                            durationPicker(label: "h", binding: $durationHours, range: 0...8)
                            Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                            durationPicker(label: "m", binding: $durationMinutes, range: 0...59)
                            Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                            durationPicker(label: "s", binding: $durationSeconds, range: 0...59)
                        }
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
        .safeAreaInset(edge: .bottom) {
            Button("Save Workout") { save() }
                .buttonStyle(StridePrimaryButtonStyle())
                .padding(.strideMD)
                .background(.ultraThinMaterial)
                .disabled(isSaving)
        }
    }

    // MARK: - Computed

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
        return units == .kilometers ? Int(Double(pace) / 1.60934) : pace
    }

    private var parsedHeartRate: Double? {
        guard let bpm = Double(heartRateText), bpm > 0 else { return nil }
        return bpm
    }

    // MARK: - Helpers

    private func prefillFromWorkoutDay() {
        guard let workout = workoutDay else { return }
        distanceMiles = workout.targetDistanceMiles
        durationMinutes = workout.targetDurationMinutes
    }

    private func applyHealthKitData(_ data: HealthKitWorkoutData) {
        distanceMiles = data.distanceMiles
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
                ? Int(Double(paceSecPerMile) * 1.60934)
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

    // MARK: - Save

    private func save() {
        guard let workout = workoutDay else { return }
        isSaving = true

        let log = WorkoutLog(
            actualDistanceMiles: distanceMiles,
            actualDurationSeconds: totalDurationSeconds,
            effortRating: effortRating,
            notes: notes,
            sourceHealthKit: selectedHKWorkout != nil,
            averageHeartRate: parsedHeartRate,
            averagePaceSecPerMile: effectivePaceSecPerMile
        )

        modelContext.insert(log)
        workout.log = log
        workout.isCompleted = true
        try? modelContext.save()

        let isLongRun = workout.workoutType == .longRun
        let isMilestone = [25, 50, 75, 100].contains(Int(distanceMiles.rounded()))

        if isLongRun || isMilestone {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { showConfetti = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { showConfetti = false }
                dismiss()
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
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
    let onHealthKit: () -> Void
    let onManual: () -> Void

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
                            Text(
                                recentWorkoutCount > 0
                                    ? "\(recentWorkoutCount) recent run\(recentWorkoutCount == 1 ? "" : "s") available"
                                    : "No recent runs found"
                            )
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

// MARK: - Confetti Overlay (placeholder)

struct ConfettiOverlay: View {
    var body: some View {
        ZStack {
            ForEach(0..<30, id: \.self) { i in
                ConfettiParticle(delay: Double(i) * 0.05)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct ConfettiParticle: View {
    let delay: Double
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 1

    private let colors: [Color] = [.stride.lavender, .stride.lavenderDeep, .white, Color(hex: "#FFD700")]
    private let size: CGFloat = CGFloat.random(in: 6...14)

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(colors.randomElement() ?? .stride.lavender)
            .frame(width: size, height: size * 0.5)
            .offset(offset)
            .opacity(opacity)
            .onAppear {
                let randomX = CGFloat.random(in: -200...200)
                withAnimation(.easeOut(duration: 2.0).delay(delay)) {
                    offset = CGSize(
                        width: randomX,
                        height: CGFloat.random(in: 300...700)
                    )
                    opacity = 0
                }
            }
            .position(
                x: CGFloat.random(in: 50...350),
                y: CGFloat.random(in: 0...100)
            )
    }
}
