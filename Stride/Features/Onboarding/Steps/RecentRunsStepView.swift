import SwiftUI

struct HealthSyncStepView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var showAddRun = false

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "heart.text.clipboard.fill",
                    title: "Connect Apple Health",
                    subtitle: "We'll import your last 3 months of runs to fill in your training history."
                )

                // What we do with the data
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("What Stride does with your data")
                            .font(Font.stride.headingSmall)
                        VStack(alignment: .leading, spacing: 10) {
                            HealthSyncBullet(
                                icon: "calendar",
                                text: "Past runs appear on your training calendar so you can see your full history."
                            )
                            HealthSyncBullet(
                                icon: "chart.line.uptrend.xyaxis",
                                text: "Your recent mileage is used to calibrate where your plan starts — no cold start."
                            )
                            HealthSyncBullet(
                                icon: "lock.fill",
                                text: "All data stays on your device. Stride never reads or writes to Health going forward without asking."
                            )
                        }
                    }
                }

                // HealthKit import card
                GlassCard {
                    VStack(spacing: .strideSM) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("Import from Apple Health")
                                .font(Font.stride.bodyMedium.weight(.semibold))
                            Spacer()
                            if viewModel.isLoadingHealthKitRuns {
                                ProgressView()
                            }
                        }
                        Text("Pulls your last 3 months of outdoor and indoor runs automatically — including pace, heart rate, and cadence where available.")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Connect Apple Health") {
                            Task { await viewModel.loadHealthKitRuns() }
                        }
                        .buttonStyle(StrideSecondaryButtonStyle())
                        .disabled(viewModel.isLoadingHealthKitRuns)
                    }
                }

                // Run list
                if viewModel.recentRuns.isEmpty {
                    GlassCard {
                        VStack(spacing: .strideSM) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.stride.lavender)
                            Text("No runs synced yet")
                                .font(Font.stride.bodyMedium)
                                .foregroundStyle(.secondary)
                            Text("Connect Apple Health to import 3 months of history, or add a recent run manually. You can also skip this — your calendar will be empty for past dates.")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .strideSM)
                    }
                } else {
                    GlassCard(padding: .strideXS) {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.recentRuns.enumerated()), id: \.element.id) { index, run in
                                RecentRunRow(run: run) {
                                    viewModel.recentRuns.remove(at: index)
                                }
                                if index < viewModel.recentRuns.count - 1 {
                                    Divider().padding(.leading, .strideLG + 8)
                                }
                            }
                        }
                    }
                }

                // Manual add
                Button {
                    showAddRun = true
                } label: {
                    Label("Add a run manually", systemImage: "plus.circle")
                        .font(Font.stride.bodyMedium.weight(.semibold))
                        .foregroundStyle(Color.stride.lavenderDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.strideSM)
                        .background(
                            RoundedRectangle(cornerRadius: .strideRadiusMD)
                                .strokeBorder(Color.stride.lavender, lineWidth: 1.5)
                        )
                }

                if !viewModel.recentRuns.isEmpty,
                   let longest = viewModel.recentRuns.max(by: { $0.distanceKm < $1.distanceKm }) {
                    GlassCard {
                        HStack(spacing: .strideSM) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.stride.mint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Longest run: \(String(format: "%.1f", longest.distanceKm)) km")
                                    .font(Font.stride.bodyMedium.weight(.semibold))
                                Text("We'll use this to calibrate your plan entry week.")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showAddRun) {
            AddRecentRunSheet { newRun in
                viewModel.addManualRun(newRun)
            }
        }
    }
}

// MARK: - Run Row

private struct RecentRunRow: View {
    let run: RecentRunEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: .strideSM) {
            Circle()
                .fill(run.workoutType.accentFill)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: run.workoutType.sfSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(run.workoutType.accentColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(run.workoutType.rawValue)
                        .font(Font.stride.bodyMedium.weight(.semibold))
                    if run.isFromHealthKit {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
                Text(run.date.formatted(date: .abbreviated, time: .omitted))
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f km", run.distanceKm))
                    .font(Font.stride.bodyMedium.weight(.semibold))
                Text("\(run.durationMinutes) min")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color(.systemGray3))
                    .font(.system(size: 18))
            }
        }
        .padding(.strideSM)
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

// MARK: - Add Run Sheet

struct AddRecentRunSheet: View {
    let onSave: (RecentRunEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workoutType: WorkoutType = .easyRun
    @State private var distanceKm: Double = 10
    @State private var durationMinutes: Int = 60
    @State private var date: Date = Date()

    private let runTypes: [WorkoutType] = [.easyRun, .longRun, .tempoRun, .intervalRun]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {

                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Workout Type")
                                    .font(Font.stride.headingSmall)
                                VStack(spacing: .strideXS) {
                                    ForEach(runTypes, id: \.self) { type in
                                        Button {
                                            workoutType = type
                                        } label: {
                                            HStack {
                                                Image(systemName: type.sfSymbol)
                                                    .foregroundStyle(type.accentColor)
                                                    .frame(width: 24)
                                                Text(type.rawValue)
                                                    .font(Font.stride.bodyMedium)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                if workoutType == type {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(Color.stride.lavender)
                                                }
                                            }
                                            .padding(.strideSM)
                                            .background(
                                                RoundedRectangle(cornerRadius: .strideRadiusSM)
                                                    .fill(workoutType == type ? Color.stride.lavenderGlow : Color.clear)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                HStack {
                                    Text("Distance")
                                        .font(Font.stride.headingSmall)
                                    Spacer()
                                    Text(String(format: "%.1f km", distanceKm))
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.stride.lavenderDeep)
                                }
                                Slider(value: $distanceKm, in: 0.5...50, step: 0.5)
                                    .tint(Color.stride.lavender)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                HStack {
                                    Text("Duration")
                                        .font(Font.stride.headingSmall)
                                    Spacer()
                                    Text("\(durationMinutes) min")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.stride.lavenderDeep)
                                }
                                Slider(value: Binding(
                                    get: { Double(durationMinutes) },
                                    set: { durationMinutes = Int($0) }
                                ), in: 5...300, step: 5)
                                    .tint(Color.stride.lavender)
                            }
                        }

                        GlassCard {
                            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                                .font(Font.stride.bodyMedium)
                                .tint(Color.stride.lavender)
                        }

                        Button("Save Run") {
                            let entry = RecentRunEntry(
                                date: date,
                                workoutType: workoutType,
                                distanceKm: distanceKm,
                                durationMinutes: durationMinutes,
                                isFromHealthKit: false
                            )
                            onSave(entry)
                            dismiss()
                        }
                        .buttonStyle(StridePrimaryButtonStyle())
                    }
                    .padding(.strideMD)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Recent Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }
}
