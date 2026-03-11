import SwiftUI

struct HealthSyncStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "heart.text.clipboard.fill",
                    title: "Connect Apple Health",
                    subtitle: "If you've been running with Apple Watch, we can pick up right where you left off."
                )

                // What we do with the data
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("What Stride does with your data")
                            .font(Font.stride.headingSmall)
                        VStack(alignment: .leading, spacing: 10) {
                            HealthSyncBullet(
                                icon: "waveform.path.ecg",
                                text: "We analyse your recent runs to understand your fitness and fill in your profile automatically."
                            )
                            HealthSyncBullet(
                                icon: "chart.line.uptrend.xyaxis",
                                text: "Your mileage, pace, and schedule patterns are used to calibrate your plan — no cold start."
                            )
                            HealthSyncBullet(
                                icon: "lock.fill",
                                text: "All data stays on your device. Stride never writes to Health."
                            )
                        }
                    }
                }

                // Sync state card
                syncStateCard
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
    }

    @ViewBuilder
    private var syncStateCard: some View {
        switch viewModel.healthSyncState {
        case .notStarted:
            GlassCard {
                VStack(spacing: .strideMD) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.red.opacity(0.7))

                    Text("Connect Apple Health to import your running history and auto-fill your fitness profile.")
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Connect Apple Health") {
                        Task { await viewModel.syncHealthKit() }
                    }
                    .buttonStyle(StrideSecondaryButtonStyle())

                    Button("Skip for now") {
                        viewModel.skipHealthSync()
                    }
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(Color.stride.lavenderDeep)
                }
                .frame(maxWidth: .infinity)
            }

        case .loading:
            GlassCard {
                VStack(spacing: .strideMD) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color.stride.lavender)

                    Text("Analysing your running history...")
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)

                    Text("We're looking at your pace, mileage, and schedule patterns to build your profile.")
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, .strideMD)
            }

        case .success(let count):
            GlassCard {
                VStack(spacing: .strideSM) {
                    HStack(spacing: .strideSM) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.stride.mint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("We found \(count) runs")
                                .font(Font.stride.headingSmall)
                            Text("Your fitness profile has been pre-filled from your history.")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .skipped:
            GlassCard {
                HStack(spacing: .strideSM) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.stride.lavender)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skipped — no problem")
                            .font(Font.stride.bodyMedium.weight(.semibold))
                        Text("You'll fill in your fitness details on the next step.")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

        case .notEnoughData:
            GlassCard {
                HStack(spacing: .strideSM) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.stride.sky)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not enough run data")
                            .font(Font.stride.bodyMedium.weight(.semibold))
                        Text("We found fewer than 5 runs. You'll enter your details manually on the next step.")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Health Sync Bullet

private struct HealthSyncBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: .strideSM) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.stride.lavenderDeep)
                .frame(width: 20)
            Text(text)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
