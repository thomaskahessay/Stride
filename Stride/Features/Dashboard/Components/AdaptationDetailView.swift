import SwiftUI

struct AdaptationDetailView: View {
    let records: [AdaptationRecord]
    let workoutDays: [WorkoutDay]
    let units: UnitSystem
    let onDismiss: () -> Void
    let onUndo: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {
                        // Summary header
                        summaryHeader

                        // Individual change cards
                        ForEach(records, id: \.id) { record in
                            adaptationCard(for: record)
                        }

                        // Action buttons
                        actionButtons
                    }
                    .padding(.horizontal, .strideMD)
                    .padding(.vertical, .strideMD)
                }
            }
            .navigationTitle("Plan Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        GlassCard {
            HStack(spacing: .strideSM) {
                ZStack {
                    Circle()
                        .fill(Color.stride.warmOrange.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.stride.warmOrange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Coach")
                        .font(Font.stride.headingSmall)
                    Text("\(records.count) workout\(records.count == 1 ? "" : "s") adjusted based on your recent activity")
                        .font(Font.stride.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Individual Change Card

    private func adaptationCard(for record: AdaptationRecord) -> some View {
        let workout = workoutDays.first { $0.id == record.workoutDayID }

        return GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                // Date + adaptation type badge
                HStack {
                    if let workout {
                        Text(workout.effectiveDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(Font.stride.bodyMedium.weight(.semibold))
                    }
                    Spacer()
                    adaptationBadge(record.adaptationType)
                }

                // Before → After comparison
                HStack(spacing: .strideMD) {
                    // Before
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BEFORE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.8)

                        Text(record.originalWorkoutType.rawValue)
                            .font(Font.stride.bodyMedium.weight(.medium))
                            .foregroundStyle(.secondary)

                        if record.originalWorkoutType.isRun {
                            Text("\(String(format: "%.1f", units.convert(record.originalDistanceMiles))) \(units.shortLabel)")
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(record.originalEffortLevel.rawValue)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Arrow
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.stride.warmOrange)

                    // After
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AFTER")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.stride.warmOrange)
                            .tracking(0.8)

                        if let workout {
                            Text(workout.workoutType.rawValue)
                                .font(Font.stride.bodyMedium.weight(.semibold))

                            if workout.workoutType.isRun {
                                Text("\(String(format: "%.1f", units.convert(workout.targetDistanceMiles))) \(units.shortLabel)")
                                    .font(Font.stride.caption)
                            }

                            Text(workout.effortLevel.rawValue)
                                .font(Font.stride.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)

                // Reason
                Text(record.reason)
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }

    // MARK: - Adaptation Type Badge

    private func adaptationBadge(_ type: AdaptationType) -> some View {
        Text(type.displayLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(type.badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(type.badgeColor.opacity(0.12))
            )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: .strideSM) {
            Button {
                onDismiss()
                dismiss()
            } label: {
                Text("Got it")
                    .font(Font.stride.bodyMedium.weight(.semibold))
                    .foregroundStyle(Color.stride.warmOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: .strideRadiusSM, style: .continuous)
                            .fill(Color.stride.warmOrange.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            Button {
                onUndo()
                dismiss()
            } label: {
                Text("Undo All")
                    .font(Font.stride.bodyMedium.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: .strideRadiusSM, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, .strideSM)
    }
}

// MARK: - AdaptationType Helpers

extension AdaptationType {
    var displayLabel: String {
        switch self {
        case .downgraded: return "Downgraded"
        case .skippedByCoach: return "Skipped"
        case .progressionHeld: return "Held"
        case .recoveryInserted: return "Recovery"
        case .strengthSubstituted: return "Substituted"
        }
    }

    var badgeColor: Color {
        switch self {
        case .downgraded: return Color.stride.warmOrange
        case .skippedByCoach: return Color(.systemGray)
        case .progressionHeld: return Color.stride.lavenderDeep
        case .recoveryInserted: return Color.stride.mint
        case .strengthSubstituted: return Color(.systemIndigo)
        }
    }
}
