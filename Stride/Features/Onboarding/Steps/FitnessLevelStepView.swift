import SwiftUI

struct ExperienceStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "figure.run.circle.fill",
                    title: "Your running background",
                    subtitle: "The more we know, the better we calibrate your plan."
                )

                // Running experience
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("How long have you been running?")
                            .font(Font.stride.headingSmall)

                        VStack(spacing: .strideXS) {
                            ForEach(RunningExperience.allCases, id: \.self) { level in
                                ExperienceRow(
                                    experience: level,
                                    isSelected: viewModel.selectedExperience == level
                                ) {
                                    viewModel.selectedExperience = level
                                }
                                if level != RunningExperience.allCases.last {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                // Prior races completed
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Races you've completed")
                                .font(Font.stride.headingSmall)
                            Text("Select all that apply.")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: .strideXS) {
                            ForEach(RaceType.allCases, id: \.self) { race in
                                let isChecked = viewModel.priorRacesCompleted.contains(race)
                                Button {
                                    if isChecked {
                                        viewModel.priorRacesCompleted.remove(race)
                                    } else {
                                        viewModel.priorRacesCompleted.insert(race)
                                    }
                                } label: {
                                    HStack {
                                        Text(race.displayName)
                                            .font(Font.stride.bodyMedium)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(isChecked ? Color.stride.lavender : Color(.systemGray3))
                                            .font(.system(size: 20))
                                    }
                                    .padding(.strideSM)
                                    .background(
                                        RoundedRectangle(cornerRadius: .strideRadiusSM)
                                            .fill(isChecked ? Color.stride.lavenderGlow : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                if race != RaceType.allCases.last {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                // Auto-suggested fitness level chip
                GlassCard {
                    HStack(spacing: .strideSM) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.stride.lavenderDeep)
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("We've placed you at \(viewModel.selectedFitnessLevel.rawValue)")
                                .font(Font.stride.bodyMedium.weight(.semibold))
                            Text(viewModel.selectedFitnessLevel.description)
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Experience Row

private struct ExperienceRow: View {
    let experience: RunningExperience
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: .strideSM) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(experience.rawValue)
                        .font(Font.stride.bodyMedium.weight(.semibold))
                    Text(experience.description)
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
