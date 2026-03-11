import SwiftUI

struct FitnessBenchmarkStepView: View {
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
                    title: "Where you are right now",
                    subtitle: "This anchors your training paces and weekly load."
                )

                // Weekly mileage
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

                // Easy / Zone 2 pace
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
                            timePicker(
                                label: "min",
                                binding: $viewModel.zone2PaceMinutes,
                                range: viewModel.selectedUnitSystem == .kilometers ? 3...15 : 5...25
                            )
                            Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                            timePicker(
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

                        Button {
                            viewModel.applyZone2Suggestion()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.stride.lavender)
                                Text("Suggested for your level: \(viewModel.suggestedZone2PaceLabel)")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Use")
                                    .font(Font.stride.caption.weight(.semibold))
                                    .foregroundStyle(Color.stride.lavender)
                            }
                        }
                        .buttonStyle(.plain)
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

                            // Race type picker
                            Picker("Race", selection: $viewModel.recentRaceType) {
                                ForEach(RaceType.allCases, id: \.self) { race in
                                    Text(race.shortDisplayName).tag(race)
                                }
                            }
                            .pickerStyle(.segmented)

                            // Time pickers
                            HStack(spacing: 0) {
                                Spacer()
                                timePicker(label: "h", binding: $viewModel.recentRaceHours, range: 0...8)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                timePicker(label: "m", binding: $viewModel.recentRaceMinutes, range: 0...59)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                timePicker(label: "s", binding: $viewModel.recentRaceSeconds, range: 0...59)
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

    private func timePicker(label: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
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
