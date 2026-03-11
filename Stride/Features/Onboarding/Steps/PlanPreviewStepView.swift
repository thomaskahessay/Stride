import SwiftUI

struct PlanPreviewStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "checkmark.seal.fill",
                    title: "Your plan is ready",
                    subtitle: "We've calculated the right starting point for you."
                )

                // Plan summary card
                HeroGlassCard(tint: Color.stride.lavender) {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.selectedRaceType.displayName.uppercased())
                                    .font(Font.stride.label)
                                    .foregroundStyle(Color.stride.lavenderDeep)
                                    .tracking(1.5)
                                Text("\(viewModel.totalPlanWeeks)-Week Plan")
                                    .font(Font.stride.headingMedium)
                                Text(viewModel.selectedGoalType.rawValue)
                                    .font(Font.stride.caption)
                                    .foregroundStyle(Color.stride.lavenderDeep)
                                    .padding(.horizontal, .strideSM)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.stride.lavenderGlow))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("RACE DAY")
                                    .font(Font.stride.label)
                                    .foregroundStyle(.secondary)
                                    .tracking(1.0)
                                Text(viewModel.raceDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(Font.stride.bodyMedium.weight(.semibold))
                            }
                        }

                        Divider()

                        HStack {
                            planStat(label: "Fitness", value: viewModel.selectedFitnessLevel.rawValue)
                            Spacer()
                            planStat(label: "Days/week", value: "\(viewModel.trainingDaysPerWeek)")
                            Spacer()
                            planStat(label: "Long run day", value: viewModel.preferredLongRunDay.shortName)
                        }

                        if viewModel.goalFinishTotalSeconds > 0 {
                            Divider()
                            HStack(spacing: .strideSM) {
                                Image(systemName: "stopwatch.fill")
                                    .foregroundStyle(Color.stride.lavenderDeep)
                                    .font(.system(size: 14))
                                Text("Goal Time")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(viewModel.formattedGoalTime)
                                    .font(Font.stride.bodyMedium.weight(.bold))
                            }
                        }
                    }
                }

                // Starting week (calendar-based, read-only)
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Your Starting Point")
                            .font(Font.stride.headingSmall)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Week \(viewModel.suggestedEntryWeek)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.stride.lavenderDeep)
                            Text("of \(viewModel.totalPlanWeeks)")
                                .font(Font.stride.headingSmall)
                                .foregroundStyle(.secondary)
                        }

                        Text(phaseLabel)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)

                        if !viewModel.recentRuns.isEmpty,
                           let longest = viewModel.recentRuns.max(by: { $0.distanceKm < $1.distanceKm }) {
                            Divider()
                            Label("Long runs calibrated from your \(String(format: "%.1f", longest.distanceKm)) km recent run",
                                  systemImage: "checkmark.circle.fill")
                                .font(Font.stride.caption)
                                .foregroundStyle(Color.stride.mint)
                        }
                    }
                }

                // Phases overview
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Plan Structure")
                            .font(Font.stride.headingSmall)

                        ForEach(planPhases, id: \.name) { phase in
                            HStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(phase.color)
                                    .frame(width: 4, height: 36)
                                VStack(alignment: .leading) {
                                    Text(phase.name).font(Font.stride.bodyMedium.weight(.semibold))
                                    Text(phase.description).font(Font.stride.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(phase.weeks).font(Font.stride.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if viewModel.currentInjuryRegion != .none,
                   let note = viewModel.currentInjuryRegion.planNote {
                    GlassCard {
                        HStack(alignment: .top, spacing: .strideSM) {
                            Image(systemName: "bandage.fill")
                                .foregroundStyle(Color.stride.sage)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Injury management active")
                                    .font(Font.stride.bodyMedium.weight(.semibold))
                                Text(note)
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                            }
                            Spacer()
                        }
                    }
                }

                if viewModel.isGeneratingPlan {
                    ProgressView("Building your plan...")
                        .tint(Color.stride.lavender)
                }
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
    }

    private func planStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Font.stride.headingSmall)
            Text(label).font(Font.stride.caption).foregroundStyle(.secondary)
        }
    }

    private var phaseLabel: String {
        let total = viewModel.totalPlanWeeks
        let week = viewModel.suggestedEntryWeek
        let base = Int(Double(total) * 0.30)
        let build = Int(Double(total) * 0.65)
        let peak = Int(Double(total) * 0.85)

        if week <= base { return "You'll enter in the Base phase — building your aerobic foundation." }
        else if week <= build { return "You'll enter in the Build phase — tempo runs and intervals begin." }
        else if week <= peak { return "You'll enter in the Peak phase — highest mileage, race-specific work." }
        else { return "You'll enter in the Taper phase — reducing volume before race day." }
    }

    private struct PlanPhaseInfo {
        let name: String
        let description: String
        let weeks: String
        let color: Color
    }

    private var planPhases: [PlanPhaseInfo] {
        let total = viewModel.totalPlanWeeks
        let baseEnd  = Int(Double(total) * 0.30)
        let buildEnd = Int(Double(total) * 0.65)
        let peakEnd  = Int(Double(total) * 0.85)

        let p1 = PlanPhaseInfo(name: "Base",  description: "Easy runs, build aerobic foundation",
                               weeks: "Wks 1–\(baseEnd)",            color: Color.stride.mint)
        let p2 = PlanPhaseInfo(name: "Build", description: "Tempo runs + intervals introduced",
                               weeks: "Wks \(baseEnd+1)–\(buildEnd)", color: Color.stride.lavender)
        let p3 = PlanPhaseInfo(name: "Peak",  description: "Highest mileage, race-pace work",
                               weeks: "Wks \(buildEnd+1)–\(peakEnd)", color: Color.stride.sage)
        let p4 = PlanPhaseInfo(name: "Taper", description: "Reduce volume, arrive fresh",
                               weeks: "Wks \(peakEnd+1)–\(total)",    color: Color.stride.sky)
        return [p1, p2, p3, p4]
    }
}
