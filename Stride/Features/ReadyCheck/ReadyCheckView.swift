import SwiftUI
import SwiftData

struct ReadyCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: ReadyCheckViewModel

    init(profile: UserProfile, modelContext: ModelContext) {
        self._viewModel = State(initialValue: ReadyCheckViewModel(
            profile: profile,
            modelContext: modelContext
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                if viewModel.hasEvaluated, let result = viewModel.result {
                    GeometryReader { geo in
                        ScrollView {
                            resultSection(result: result)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, .strideMD)
                                .padding(.vertical, .strideMD)
                                .frame(minHeight: geo.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    ScrollView {
                        VStack(spacing: .strideLG) {
                            headerSection
                            sleepSection
                            bodySection
                            mindSection
                            evaluateButton
                        }
                        .padding(.horizontal, .strideMD)
                        .padding(.vertical, .strideMD)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.hasEvaluated)
            .navigationTitle("Ready Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
            .task {
                await viewModel.fetchSleepData()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: .strideSM) {
            if let workout = viewModel.todayWorkout, workout.workoutType != .restDay {
                HStack(spacing: .strideSM) {
                    Image(systemName: workout.workoutType.sfSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(workout.workoutType.accentColor)
                    Text(workout.workoutTitle)
                        .font(Font.stride.headingSmall)
                }
                Text("How are you feeling before today's workout?")
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("How are you feeling today?")
                    .font(Font.stride.headingMedium)
                Text("Rest days count too. Let's check in.")
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, .strideSM)
    }

    // MARK: - Sleep Section

    private var sleepSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideMD) {
                HStack {
                    Label("Sleep", systemImage: "moon.fill")
                        .font(Font.stride.headingSmall)
                        .foregroundStyle(Color.stride.lavenderDeep)
                    Spacer()
                    if viewModel.isFetchingSleep {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                // HealthKit sleep data banner
                if let sleepHours = viewModel.sleepHoursFormatted {
                    HStack(spacing: .strideMD) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sleepHours)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("last night")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let efficiency = viewModel.sleepEfficiencyFormatted {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 1, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(efficiency)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Text("efficiency")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.stride.lavender)
                    }
                    .padding(.strideSM)
                    .background(
                        RoundedRectangle(cornerRadius: .strideRadiusSM, style: .continuous)
                            .fill(Color.stride.lavenderGlow.opacity(0.5))
                    )

                    // Override toggle
                    HStack {
                        Text("Doesn't feel right?")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Override", isOn: $viewModel.useSleepOverride)
                            .labelsHidden()
                            .scaleEffect(0.8)
                    }
                }

                // Manual slider (always shown — primary input if no HK data, override if HK data exists)
                if viewModel.sleepData == nil || viewModel.useSleepOverride {
                    ReadinessSlider(
                        label: "How'd you sleep?",
                        value: $viewModel.sleepQuality,
                        lowLabel: "Terrible",
                        highLabel: "Amazing"
                    )
                }
            }
        }
    }

    // MARK: - Body Section

    private var bodySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideMD) {
                Label("Body", systemImage: "figure.run")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)

                ReadinessSlider(
                    label: "Muscle soreness",
                    value: $viewModel.muscleSoreness,
                    lowLabel: "Very sore",
                    highLabel: "Fresh"
                )

                ReadinessSlider(
                    label: "Energy level",
                    value: $viewModel.energyLevel,
                    lowLabel: "Drained",
                    highLabel: "Energised"
                )
            }
        }
    }

    // MARK: - Mind Section

    private var mindSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideMD) {
                Label("Mind", systemImage: "brain.head.profile.fill")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)

                ReadinessSlider(
                    label: "Motivation to run",
                    value: $viewModel.motivation,
                    lowLabel: "Not feeling it",
                    highLabel: "Let's go"
                )
            }
        }
    }

    // MARK: - Evaluate Button

    private var evaluateButton: some View {
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                viewModel.evaluate()
            }
        } label: {
            HStack(spacing: .strideSM) {
                Image(systemName: "waveform.path.ecg")
                Text("Check My Readiness")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                    .fill(Color.stride.lavenderDeep)
            )
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.hasEvaluated)
    }

    // MARK: - Result Section

    private func resultSection(result: ReadinessEngine.Result) -> some View {
        VStack(spacing: .strideMD) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(Color.stride.lavenderLight, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: result.score / 100.0)
                    .stroke(
                        resultColor(for: result.recommendation),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: result.score)

                VStack(spacing: 2) {
                    Text("\(Int(result.score))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("readiness")
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            // Recommendation card
            HeroGlassCard(tint: resultColor(for: result.recommendation)) {
                VStack(spacing: .strideSM) {
                    HStack(spacing: .strideSM) {
                        Image(systemName: result.recommendation.sfSymbol)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(resultColor(for: result.recommendation))
                        Text(result.recommendation.rawValue)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }

                    Text(result.recommendation.description)
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            // Action buttons — two paths when recommendation isn't sendIt
            if result.recommendation == .sendIt {
                Button {
                    viewModel.accept()
                    dismiss()
                } label: {
                    HStack(spacing: .strideSM) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Got It")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                            .fill(resultColor(for: result.recommendation))
                    )
                }
                .sensoryFeedback(.success, trigger: true)
            } else {
                // Advisory — acknowledge the recommendation
                Button {
                    viewModel.acceptWithoutAdaptation()
                    dismiss()
                } label: {
                    HStack(spacing: .strideSM) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Got it, thanks")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                            .fill(resultColor(for: result.recommendation))
                    )
                }
                .sensoryFeedback(.success, trigger: true)
            }

            // Re-evaluate option
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    viewModel.hasEvaluated = false
                    viewModel.result = nil
                }
            } label: {
                Text("Adjust & Re-check")
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(Color.stride.lavenderDeep)
            }
            .padding(.bottom, .strideLG)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Helpers

    private func resultColor(for recommendation: ReadinessRecommendation) -> Color {
        switch recommendation {
        case .sendIt: return Color.stride.mint
        case .dialBack: return Color.stride.lavenderDeep
        case .swapRecovery: return Color.stride.warmOrange
        case .restToday: return Color.stride.coral
        }
    }
}

// MARK: - Readiness Slider

struct ReadinessSlider: View {
    let label: String
    @Binding var value: Int
    let lowLabel: String
    let highLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: .strideSM) {
            Text(label)
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)

            HStack(spacing: .strideSM) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            value = level
                        }
                    } label: {
                        Circle()
                            .fill(level <= value ? Color.stride.lavenderDeep : Color.stride.lavenderLight)
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text("\(level)")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(level <= value ? .white : .secondary)
                            }
                            .scaleEffect(level == value ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: value)
                }
            }
            .frame(maxWidth: .infinity)

            HStack {
                Text(lowLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(highLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
