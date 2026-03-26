import SwiftUI

// MARK: - SwapWorkoutPickerView

struct SwapWorkoutPickerView: View {
    @Bindable var viewModel: SwapWorkoutPickerViewModel
    var units: UnitSystem = .kilometers
    var onSwapCompleted: ((SwapSnapshot, SwapSnapshot, WorkoutDay) -> Void)?
    var onCustomRun: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {
                        headerSection

                        if viewModel.availableTargets.isEmpty {
                            emptyState
                        } else {
                            targetsSection
                        }

                        if viewModel.showCustomRunOption {
                            customRunButton
                        }
                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle("Swap Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Back-to-Back Hard Workouts",
                isPresented: $viewModel.showConsecutiveHardWarning
            ) {
                Button("Cancel", role: .cancel) {
                    viewModel.cancelHardDayWarning()
                }
                Button("Swap Anyway") {
                    if let result = viewModel.confirmHardDaySwap() {
                        onSwapCompleted?(result.source, result.target, result.targetDay)
                        dismiss()
                    }
                }
            } message: {
                Text("This swap places two hard workouts on consecutive days, which increases injury risk. Are you sure?")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: .strideXS) {
            Text("Select a workout to swap with")
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)

            currentWorkoutCard
        }
    }

    private var currentWorkoutCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: viewModel.source.workoutType.sfSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(viewModel.source.workoutType.accentColor)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(viewModel.source.workoutType.accentFill)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current: \(viewModel.source.workoutTitle)")
                        .font(Font.stride.bodyMedium.weight(.semibold))

                    Text(viewModel.source.effectiveDate.formatted(date: .abbreviated, time: .omitted))
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - Targets

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: .strideSM) {
            Text("Available Workouts")
                .font(Font.stride.label)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(viewModel.availableTargets, id: \.id) { target in
                targetRow(target)
            }
        }
    }

    private func targetRow(_ target: WorkoutDay) -> some View {
        Button {
            handleTargetSelection(target)
        } label: {
            GlassCard(padding: 12) {
                HStack(spacing: 12) {
                    Image(systemName: target.workoutType.sfSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(target.workoutType.accentColor)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(target.workoutType.accentFill)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.workoutTitle)
                            .font(Font.stride.bodyMedium.weight(.medium))
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            Text(target.effectiveDate.formatted(.dateTime.weekday(.wide)))
                                .font(Font.stride.caption)

                            Text(target.effectiveDate.formatted(date: .abbreviated, time: .omitted))
                                .font(Font.stride.caption)
                        }
                        .foregroundStyle(.secondary)

                        if viewModel.isOriginalWorkout(target) {
                            Text("Your original workout")
                                .font(Font.stride.label)
                                .foregroundStyle(Color.stride.lavenderDeep)
                        }
                    }

                    Spacer()

                    if target.workoutType.isRun && target.targetDistanceMiles > 0 {
                        Text(target.targetDistanceMiles.formattedDistance(unit: units))
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom Run

    private var customRunButton: some View {
        Button {
            onCustomRun?()
            dismiss()
        } label: {
            GlassCard(padding: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.stride.lavenderDeep)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.stride.lavenderDeep.opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Other (Custom Run)")
                            .font(Font.stride.bodyMedium.weight(.medium))
                            .foregroundStyle(.primary)

                        Text("Enter distance and pace manually")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "plus.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: .strideSM) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.stride.lavenderDeep.opacity(0.5))

            Text("No workouts available to swap")
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)

            Text("Workouts within 7 days that are incomplete and not skipped can be swapped.")
                .font(Font.stride.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, .strideXL)
    }

    // MARK: - Helpers

    private func handleTargetSelection(_ target: WorkoutDay) {
        if let result = viewModel.selectTarget(target) {
            onSwapCompleted?(result.source, result.target, target)
            dismiss()
        }
        // If nil, the consecutive hard day warning alert is shown
    }

}
