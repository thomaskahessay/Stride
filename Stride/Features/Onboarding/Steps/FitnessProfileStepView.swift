import SwiftUI

struct FitnessProfileStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    // Slider operates in km; viewModel stores miles internally
    private var kmBinding: Binding<Double> {
        Binding(
            get: { (viewModel.currentWeeklyMiles * 1.60934).rounded() },
            set: { viewModel.currentWeeklyMiles = $0 / 1.60934 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "figure.run",
                    title: viewModel.fitnessProfileHeader,
                    subtitle: viewModel.fitnessProfileCoachingLine
                )

                // Context cards (read-only) — shown when we have HealthKit data
                if viewModel.hasEnoughData {
                    contextCards
                }

                // Weekly mileage — editable
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        HStack {
                            Text("Weekly Distance")
                                .font(Font.stride.headingSmall)
                            Spacer()
                            Text(String(format: "%.0f km/wk", kmBinding.wrappedValue))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.stride.lavenderDeep)
                        }

                        Slider(value: kmBinding, in: 0...100, step: 1)
                            .tint(Color.stride.lavender)

                        HStack {
                            Text("Not running")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("100+ km/wk")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Easy / Zone 2 pace — editable
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Easy Running Pace")
                                .font(Font.stride.headingSmall)
                            Text("The pace you could hold for an hour while having a full conversation")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }

                        HStack(spacing: 0) {
                            Spacer()
                            pacePicker(
                                label: "min",
                                binding: $viewModel.zone2PaceMinutes,
                                range: viewModel.selectedUnitSystem == .kilometers ? 3...15 : 5...25
                            )
                            Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                            pacePicker(
                                label: "sec",
                                binding: $viewModel.zone2PaceSeconds,
                                range: 0...59
                            )
                            Text(" /\(viewModel.selectedUnitSystem.shortLabel)")
                                .font(Font.stride.bodyMedium.weight(.semibold))
                                .foregroundStyle(Color.stride.lavenderDeep)
                                .padding(.leading, 8)
                            Spacer()
                        }

                        if viewModel.hasEnoughData {
                            Label("Pre-filled from your HealthKit data", systemImage: "heart.fill")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Fitness level — editable override
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Fitness Level")
                            .font(Font.stride.headingSmall)

                        if let analysis = viewModel.fitnessAnalysis, analysis.hasEnoughData {
                            Text(analysis.fitnessExplanation)
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }

                        VStack(spacing: .strideXS) {
                            ForEach(FitnessLevel.allCases, id: \.self) { level in
                                Button {
                                    viewModel.selectedFitnessLevel = level
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(level.rawValue)
                                                .font(Font.stride.bodyMedium.weight(.semibold))
                                            Text(level.description)
                                                .font(Font.stride.caption)
                                                .foregroundStyle(.secondary)
                                                .lineSpacing(2)
                                        }
                                        Spacer()
                                        Image(systemName: viewModel.selectedFitnessLevel == level
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(viewModel.selectedFitnessLevel == level
                                                             ? Color.stride.lavender : Color(.systemGray3))
                                            .font(.system(size: 22))
                                    }
                                    .padding(.strideSM)
                                    .background(
                                        RoundedRectangle(cornerRadius: .strideRadiusSM)
                                            .fill(viewModel.selectedFitnessLevel == level
                                                  ? Color.stride.lavenderGlow : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Optional recent race time
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Recent Race Time")
                                    .font(Font.stride.headingSmall)
                                Text("Optional — used to project your finish time")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.hasRecentRaceTime)
                                .tint(Color.stride.lavender)
                        }

                        if viewModel.hasRecentRaceTime {
                            Divider()

                            Picker("Race", selection: $viewModel.recentRaceType) {
                                ForEach(RaceType.allCases, id: \.self) { race in
                                    Text(race.shortDisplayName).tag(race)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack(spacing: 0) {
                                Spacer()
                                pacePicker(label: "h", binding: $viewModel.recentRaceHours, range: 0...8)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                pacePicker(label: "m", binding: $viewModel.recentRaceMinutes, range: 0...59)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                pacePicker(label: "s", binding: $viewModel.recentRaceSeconds, range: 0...59)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Context Cards (read-only, shown with HealthKit data)

    @ViewBuilder
    private var contextCards: some View {
        GlassCard {
            HStack(spacing: .strideMD) {
                contextStat(
                    icon: "road.lanes",
                    label: "Longest Run",
                    value: String(format: "%.1f km", viewModel.longestRunMiles * 1.60934)
                )
                Spacer()
                contextStat(
                    icon: "calendar",
                    label: "Runs / Week",
                    value: String(format: "%.1f", viewModel.runsPerWeekDisplay)
                )
            }
        }
    }

    private func contextStat(icon: String, label: String, value: String) -> some View {
        HStack(spacing: .strideSM) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.stride.lavenderDeep)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(Font.stride.bodyMedium.weight(.bold))
                Text(label)
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pacePicker(label: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            Picker("", selection: binding) {
                ForEach(range, id: \.self) { v in
                    Text(String(format: "%02d", v)).tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 80)
            .clipped()
            Text(label).font(Font.stride.caption).foregroundStyle(.secondary)
        }
    }
}
