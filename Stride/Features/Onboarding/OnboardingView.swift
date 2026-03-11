import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            LinearGradient.strideBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                OnboardingProgressBar(progress: viewModel.currentStep.progress)
                    .padding(.horizontal, .strideMD)
                    .padding(.top, .strideMD)

                // Step content
                Group {
                    switch viewModel.currentStep {
                    case .welcome:
                        WelcomeStepView(viewModel: viewModel)
                    case .goalSetup:
                        GoalSetupStepView(viewModel: viewModel)
                    case .experience:
                        ExperienceStepView(viewModel: viewModel)
                    case .fitnessBenchmark:
                        FitnessBenchmarkStepView(viewModel: viewModel)
                    case .injuryCheck:
                        InjuryCheckStepView(viewModel: viewModel)
                    case .lifestyle:
                        LifestyleStepView(viewModel: viewModel)
                    case .schedule:
                        ScheduleStepView(viewModel: viewModel)
                    case .healthSync:
                        HealthSyncStepView(viewModel: viewModel)
                    case .planPreview:
                        PlanPreviewStepView(viewModel: viewModel)
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: viewModel.isAnimatingForward ? .trailing : .leading),
                        removal: .move(edge: viewModel.isAnimatingForward ? .leading : .trailing)
                    )
                    .combined(with: .opacity)
                )
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
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
                    }
                }
                .padding(.horizontal, .strideMD)
                .padding(.bottom, .strideXL)
            }
        }
    }
}

// MARK: - Progress Bar

private struct OnboardingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.stride.lavenderLight)
                    .frame(height: 6)

                Capsule()
                    .fill(Color.stride.lavender)
                    .frame(width: geo.size.width * progress, height: 6)
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .modelContainer(for: [UserProfile.self, TrainingPlan.self, WorkoutDay.self, WorkoutLog.self, HistoricalRun.self])
}
