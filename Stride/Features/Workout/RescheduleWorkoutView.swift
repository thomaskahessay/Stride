import SwiftUI

struct RescheduleWorkoutView: View {
    @Bindable var viewModel: WorkoutDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    init(viewModel: WorkoutDetailViewModel) {
        self.viewModel = viewModel
        _selectedDate = State(initialValue: viewModel.workout.effectiveDate)
    }

    private var conflictingWorkout: WorkoutDay? {
        viewModel.workout(on: selectedDate)
    }

    private var isSameDay: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: viewModel.workout.effectiveDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {
                        DatePicker(
                            "",
                            selection: $selectedDate,
                            in: Calendar.current.startOfDay(for: Date())...viewModel.raceDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(Color.stride.lavenderDeep)
                        .padding(.strideMD)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: .strideRadiusLG)
                        )
                        .padding(.horizontal, .strideMD)

                        if let conflict = conflictingWorkout {
                            swapBanner(conflict)
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, .strideMD)
                }

                // Pinned confirm button
                VStack {
                    Spacer()
                    confirmButton
                        .padding(.strideMD)
                        .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Move Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    // MARK: - Components

    private func swapBanner(_ conflict: WorkoutDay) -> some View {
        GlassCard {
            HStack(spacing: .strideSM) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.stride.lavenderDeep)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Swaps with \(conflict.workoutTitle)")
                        .font(Font.stride.bodyMedium.weight(.semibold))
                    Text("\(conflict.workoutTitle) will move to \(viewModel.workout.effectiveDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(.horizontal, .strideMD)
    }

    private var confirmButton: some View {
        Button(conflictingWorkout != nil ? "Swap Workouts" : "Move to This Day") {
            viewModel.reschedule(to: selectedDate)
            dismiss()
        }
        .buttonStyle(StridePrimaryButtonStyle())
        .disabled(isSameDay)
    }
}
