import SwiftUI

struct LifestyleStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "sun.and.horizon.fill",
                    title: "Your daily life",
                    subtitle: "Your lifestyle affects how your body recovers between sessions."
                )

                // Sleep
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        HStack {
                            Text("Sleep per night")
                                .font(Font.stride.headingSmall)
                            Spacer()
                            Text(String(format: "%.0fh", viewModel.sleepHoursPerNight))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.stride.lavenderDeep)
                        }

                        Slider(value: $viewModel.sleepHoursPerNight, in: 4...10, step: 0.5)
                            .tint(Color.stride.lavender)

                        HStack {
                            Text("4h").font(Font.stride.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("10h").font(Font.stride.caption).foregroundStyle(.secondary)
                        }

                        if viewModel.sleepHoursPerNight < 6 {
                            Label("Under 6h slows recovery — we'll build in extra rest days.",
                                  systemImage: "moon.zzz.fill")
                                .font(Font.stride.caption)
                                .foregroundStyle(Color.stride.sage)
                        }
                    }
                }

                // Daily activity level
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Your typical day")
                            .font(Font.stride.headingSmall)

                        VStack(spacing: .strideXS) {
                            ForEach(ActivityLevel.allCases, id: \.self) { level in
                                ActivityLevelRow(
                                    level: level,
                                    isSelected: viewModel.selectedActivityLevel == level
                                ) {
                                    viewModel.selectedActivityLevel = level
                                }
                                if level != ActivityLevel.allCases.last {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                // Strength training
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Strength training")
                                .font(Font.stride.headingSmall)
                            Text(viewModel.doesStrengthTraining
                                 ? "We'll keep strength days complementary to your runs."
                                 : "We'll include bodyweight cues on your easy days.")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.doesStrengthTraining)
                            .tint(Color.stride.lavender)
                    }
                }
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Activity Level Row

private struct ActivityLevelRow: View {
    let level: ActivityLevel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: .strideSM) {
                Image(systemName: level.sfSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.stride.lavenderDeep : Color(.systemGray3))
                    .frame(width: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(level.rawValue)
                        .font(Font.stride.bodyMedium.weight(.semibold))
                    Text(level.description)
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.stride.lavender : Color(.systemGray3))
                    .font(.system(size: 22))
            }
            .padding(.vertical, .strideXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
