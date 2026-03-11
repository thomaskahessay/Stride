import SwiftUI
import SwiftData

// NOTE: This is named StatsView intentionally — ProgressView conflicts with SwiftUI's built-in.
struct StatsView: View {
    let profile: UserProfile

    @State private var showAddTimeTrial = false

    private let estimator = FinishTimeEstimator()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {

                        // Projected finish time — top, full width
                        finishTimeCard

                        // Plan completion + race countdown row
                        HStack(spacing: .strideMD) {
                            overviewStat(
                                label: "Plan Complete",
                                value: "\(Int((profile.activePlan?.completionPercentage ?? 0) * 100))%",
                                icon: "checkmark.seal.fill",
                                color: Color.stride.lavender
                            )
                            overviewStat(
                                label: "Days to Race",
                                value: "\(daysToRace)",
                                icon: "flag.checkered.2.crossed",
                                color: Color.stride.sage
                            )
                            overviewStat(
                                label: "Total \(profile.unitPreference.shortLabel.capitalized)",
                                value: String(format: "%.0f", profile.unitPreference.convert(totalMilesLogged)),
                                icon: "road.lanes",
                                color: Color.stride.mint
                            )
                        }

                        // Weekly mileage chart
                        weeklyMileageChart

                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showAddTimeTrial) {
            AddTimeTrialView(profile: profile)
        }
    }

    // MARK: - Overview stat pill

    private func overviewStat(label: String, value: String, icon: String, color: Color) -> some View {
        GlassCard(cornerRadius: .strideRadiusMD, padding: .strideSM) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(label)
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Finish Time Card

    private var finishTimeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Label("Projected Finish Time", systemImage: "stopwatch.fill")
                    .font(Font.stride.headingSmall)
                    .foregroundStyle(Color.stride.lavenderDeep)

                if let raceTime = profile.recentRaceTime,
                   let projected = estimator.projectedTime(from: raceTime, for: profile.raceType) {
                    HStack(alignment: .firstTextBaseline, spacing: .strideXS) {
                        Text(estimator.formatted(seconds: projected))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.stride.lavenderDeep)

                        Text(profile.raceType.displayName)
                            .font(Font.stride.headingSmall)
                            .foregroundStyle(.secondary)
                    }

                    Text(estimator.sourceLabel(for: raceTime))
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)

                    Text("This estimate improves as you train.")
                        .font(Font.stride.caption)
                        .foregroundStyle(.tertiary)
                        .italic()

                    Button("Update Time Trial") { showAddTimeTrial = true }
                        .font(Font.stride.caption.weight(.semibold))
                        .foregroundStyle(Color.stride.lavenderDeep)
                } else {
                    Text("No time trial entered yet.")
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)

                    Button("Add a Recent Race Time") { showAddTimeTrial = true }
                        .buttonStyle(StrideSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Weekly Mileage Chart

    private var weeklyMileageChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("Weekly Mileage")
                    .font(Font.stride.headingSmall)

                let weeks = last8WeeksMileage
                let maxMiles = weeks.map(\.miles).max() ?? 1

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(weeks) { week in
                        VStack(spacing: 4) {
                            if week.miles > 0 {
                                Text(String(format: "%.0f", profile.unitPreference.convert(week.miles)))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.stride.lavenderDeep)
                            }

                            RoundedRectangle(cornerRadius: 4)
                                .fill(week.isCurrent ? Color.stride.lavender : Color.stride.lavenderLight)
                                .frame(
                                    height: max(4, 100 * CGFloat(week.miles) / CGFloat(maxMiles))
                                )

                            Text(week.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 130)

                Text("Last 8 weeks · \(profile.unitPreference.shortLabel)")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed data

    private struct WeekData: Identifiable {
        let id: Int
        let label: String
        let miles: Double
        let isCurrent: Bool
    }

    private var last8WeeksMileage: [WeekData] {
        guard let plan = profile.activePlan else { return [] }
        let cal = Calendar.current

        return (0..<8).reversed().map { weekOffset in
            let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: Date()) ?? Date()
            let weekStartDay = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)) ?? weekStart
            let weekEndDay = cal.date(byAdding: .day, value: 6, to: weekStartDay) ?? weekStartDay

            let miles = plan.workoutDays
                .filter { $0.date >= weekStartDay && $0.date <= weekEndDay }
                .compactMap { $0.log?.actualDistanceMiles }
                .reduce(0, +)

            let label = weekStartDay.formatted(.dateTime.month(.abbreviated).day())
            return WeekData(id: weekOffset, label: label, miles: miles, isCurrent: weekOffset == 0)
        }
    }

    private var daysToRace: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let components = Calendar.current.dateComponents([.day], from: today, to: profile.raceDate)
        return max(0, components.day ?? 0)
    }

    private var totalMilesLogged: Double {
        profile.activePlan?.workoutDays
            .compactMap { $0.log?.actualDistanceMiles }
            .reduce(0, +) ?? 0
    }
}

// MARK: - Add Time Trial Sheet

struct AddTimeTrialView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var raceType: RaceType = .fiveK
    @State private var hours: Int = 0
    @State private var minutes: Int = 28
    @State private var seconds: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                VStack(spacing: .strideMD) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: .strideSM) {
                            Text("Race Distance")
                                .font(Font.stride.headingSmall)

                            Picker("Race", selection: $raceType) {
                                ForEach(RaceType.allCases, id: \.self) { race in
                                    Text(race.displayName).tag(race)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: .strideSM) {
                            Text("Finish Time")
                                .font(Font.stride.headingSmall)

                            HStack(spacing: 0) {
                                timePicker(label: "h", binding: $hours, range: 0...8)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                timePicker(label: "m", binding: $minutes, range: 0...59)
                                Text(":").font(Font.stride.headingMedium).padding(.horizontal, 4)
                                timePicker(label: "s", binding: $seconds, range: 0...59)
                            }
                        }
                    }

                    Spacer()

                    Button("Save Time Trial") { save() }
                        .buttonStyle(StridePrimaryButtonStyle())
                        .padding(.horizontal, .strideMD)
                }
                .padding(.strideMD)
            }
            .navigationTitle("Add Race Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    private func save() {
        profile.recentRaceTime = RaceTime(
            raceDistance: raceType,
            finishTimeSeconds: hours * 3600 + minutes * 60 + seconds,
            raceDate: Date()
        )
        try? modelContext.save()
        dismiss()
    }

    private func timePicker(label: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            Picker("", selection: binding) {
                ForEach(range, id: \.self) { v in Text(String(format: "%02d", v)).tag(v) }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 80)
            .clipped()
            Text(label).font(Font.stride.caption).foregroundStyle(.secondary)
        }
    }
}
