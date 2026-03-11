import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            LinearGradient.strideBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Animated progress bar
                OnboardingProgressBar(
                    progress: viewModel.currentStep.progress,
                    stepIndex: viewModel.currentStep.rawValue,
                    totalSteps: OnboardingStep.allCases.count
                )
                .padding(.horizontal, .strideMD)
                .padding(.top, .strideMD)

                // Step content
                Group {
                    switch viewModel.currentStep {
                    case .welcome:
                        WelcomeStepView(viewModel: viewModel)
                    case .healthSync:
                        HealthSyncStepView(viewModel: viewModel)
                    case .fitnessProfile:
                        FitnessProfileStepView(viewModel: viewModel)
                    case .goalSetup:
                        GoalSetupStepView(viewModel: viewModel)
                    case .schedule:
                        ScheduleStepView(viewModel: viewModel)
                    case .planPreview:
                        PlanPreviewStepView(viewModel: viewModel)
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: viewModel.isAnimatingForward ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .move(edge: viewModel.isAnimatingForward ? .leading : .trailing)
                            .combined(with: .opacity)
                    )
                )
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.currentStep)
                .frame(maxHeight: .infinity)

                // Navigation buttons
                VStack(spacing: .strideSM) {
                    if viewModel.currentStep == .planPreview {
                        Button("Start Training") {
                            Task {
                                await viewModel.complete(modelContext: modelContext)
                            }
                        }
                        .buttonStyle(StridePrimaryButtonStyle())
                        .disabled(!viewModel.canAdvance)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        Button("Continue") {
                            viewModel.advance()
                        }
                        .buttonStyle(StridePrimaryButtonStyle())
                        .disabled(!viewModel.canAdvance)
                    }

                    if viewModel.currentStep.rawValue > 0 {
                        Button("Back") {
                            viewModel.goBack()
                        }
                        .buttonStyle(StrideGhostButtonStyle())
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, .strideMD)
                .padding(.bottom, .strideXL)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.currentStep)
            }
        }
    }
}

// MARK: - Progress Bar

private struct OnboardingProgressBar: View {
    let progress: Double
    let stepIndex: Int
    let totalSteps: Int

    var body: some View {
        VStack(spacing: .strideXS) {
            // Step dots + connecting bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.stride.lavenderLight)
                        .frame(height: 4)

                    // Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.stride.lavender, Color.stride.lavenderDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 4)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 4)

            // Step indicator text
            HStack {
                Text("Step \(stepIndex + 1) of \(totalSteps)")
                    .font(Font.stride.caption)
                    .foregroundStyle(Color.stride.lavenderDeep)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: stepIndex)

                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .modelContainer(for: [UserProfile.self, TrainingPlan.self, WorkoutDay.self, WorkoutLog.self, HistoricalRun.self])
}
