import SwiftUI

struct GoalSetupStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "flag.checkered.2.crossed",
                    title: "Your race goal",
                    subtitle: "Your goal shapes every workout we prescribe."
                )

                // Race distance
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Race Distance")
                            .font(Font.stride.headingSmall)

                        VStack(spacing: .strideSM) {
                            ForEach(RaceType.allCases, id: \.self) { race in
                                RaceTypeRow(
                                    race: race,
                                    isSelected: viewModel.selectedRaceType == race
                                ) {
                                    viewModel.selectedRaceType = race
                                    applyDefaultGoalTime(for: race)
                                }
                            }
                        }
                    }
                }

                // Race date
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Race Date")
                            .font(Font.stride.headingSmall)

                        DatePicker(
                            "Race Date",
                            selection: $viewModel.raceDate,
                            in: minRaceDate...maxRaceDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(Color.stride.lavender)

                        if !viewModel.canAdvance && viewModel.currentStep == .goalSetup {
                            Label("Race must be at least 4 weeks away.", systemImage: "exclamationmark.circle")
                                .font(Font.stride.caption)
                                .foregroundStyle(Color.stride.coral)
                        }
                    }
                }

                // Goal type
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("What's your goal?")
                            .font(Font.stride.headingSmall)

                        VStack(spacing: .strideXS) {
                            ForEach(GoalType.allCases, id: \.self) { goal in
                                GoalTypeRow(
                                    goal: goal,
                                    isSelected: viewModel.selectedGoalType == goal
                                ) {
                                    viewModel.selectedGoalType = goal
                                    if goal != .finishComfortably {
                                        viewModel.hasGoalFinishTime = true
                                    }
                                }
                            }
                        }
                    }
                }

                // Goal finish time
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goalTimeCardTitle)
                                    .font(Font.stride.headingSmall)
                                Text(goalTimeCardSubtitle)
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedGoalType == .finishComfortably {
                                Toggle("", isOn: $viewModel.hasGoalFinishTime)
                                    .tint(Color.stride.lavender)
                            }
                        }

                        if showsTimePicker {
                            Divider()

                            HStack(spacing: 0) {
                                Spacer()
                                goalTimePicker(label: "h", binding: $viewModel.goalFinishHours, range: 0...8)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                goalTimePicker(label: "m", binding: $viewModel.goalFinishMinutes, range: 0...59)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                goalTimePicker(label: "s", binding: $viewModel.goalFinishSecs, range: 0...59)
                                Spacer()
                            }

                            Text(paceHint)
                                .font(Font.stride.caption)
                                .foregroundStyle(Color.stride.lavenderDeep)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
        .onAppear {
            // Ensure time is expanded for competitive goals
            if viewModel.selectedGoalType != .finishComfortably {
                viewModel.hasGoalFinishTime = true
            }
        }
    }

    // MARK: - Computed helpers

    private var minRaceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: 4, to: Date()) ?? Date()
    }

    private var maxRaceDate: Date {
        Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    }

    private var showsTimePicker: Bool {
        viewModel.selectedGoalType != .finishComfortably || viewModel.hasGoalFinishTime
    }

    private var goalTimeCardTitle: String {
        switch viewModel.selectedGoalType {
        case .finishComfortably: return "Set a time goal"
        case .targetTime:        return "Target finish time"
        case .competitive:       return "Goal finish time"
        }
    }

    private var goalTimeCardSubtitle: String {
        switch viewModel.selectedGoalType {
        case .finishComfortably: return "Optional — helps calibrate your training paces."
        case .targetTime:        return "All your paces will be dialled in around this time."
        case .competitive:       return "Your target time anchors every workout pace."
        }
    }

    private var paceHint: String {
        let totalSecs = viewModel.goalFinishHours * 3600
            + viewModel.goalFinishMinutes * 60
            + viewModel.goalFinishSecs
        guard totalSecs > 0 else { return "" }
        let distanceKm = viewModel.selectedRaceType.distanceKm
        let paceSecsPerKm = Double(totalSecs) / distanceKm
        let paceMin = Int(paceSecsPerKm) / 60
        let paceSec = Int(paceSecsPerKm) % 60
        return String(format: "That's a %d:%02d /km average pace", paceMin, paceSec)
    }

    // MARK: - Private helpers

    private func applyDefaultGoalTime(for race: RaceType) {
        switch race {
        case .fiveK:        viewModel.goalFinishHours = 0; viewModel.goalFinishMinutes = 30; viewModel.goalFinishSecs = 0
        case .tenK:         viewModel.goalFinishHours = 1; viewModel.goalFinishMinutes = 0;  viewModel.goalFinishSecs = 0
        case .halfMarathon: viewModel.goalFinishHours = 2; viewModel.goalFinishMinutes = 15; viewModel.goalFinishSecs = 0
        case .fullMarathon: viewModel.goalFinishHours = 4; viewModel.goalFinishMinutes = 30; viewModel.goalFinishSecs = 0
        }
    }

    private func goalTimePicker(label: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
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

// MARK: - Race Type Row

private struct RaceTypeRow: View {
    let race: RaceType
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(race.displayName)
                        .font(Font.stride.bodyMedium.weight(.semibold))
                    Text(String(format: "%.1f km", race.distanceKm))
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.stride.lavender : Color(.systemGray3))
                    .font(.system(size: 22))
            }
            .padding(.strideSM)
            .background(
                RoundedRectangle(cornerRadius: .strideRadiusSM)
                    .fill(isSelected ? Color.stride.lavenderGlow : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Goal Type Row

private struct GoalTypeRow: View {
    let goal: GoalType
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: .strideSM) {
                Image(systemName: goal.sfSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.stride.lavenderDeep : Color(.systemGray3))
                    .frame(width: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.rawValue)
                        .font(Font.stride.bodyMedium.weight(.semibold))
                    Text(goal.description)
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.stride.lavender : Color(.systemGray3))
                    .font(.system(size: 22))
            }
            .padding(.strideSM)
            .background(
                RoundedRectangle(cornerRadius: .strideRadiusSM)
                    .fill(isSelected ? Color.stride.lavenderGlow : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
