import SwiftUI

struct AdaptationBannerCard: View {
    let records: [AdaptationRecord]
    let onDismiss: () -> Void
    let onUndo: () -> Void

    private var aggregatedReason: String {
        guard let first = records.first else { return "" }
        if records.count == 1 {
            return first.reason
        }
        return "Your plan has been adjusted based on recent activity (\(records.count) changes)."
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                HStack(spacing: .strideSM) {
                    ZStack {
                        Circle()
                            .fill(Color.stride.warmOrange.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.stride.warmOrange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan adjusted")
                            .font(Font.stride.bodyMedium.weight(.semibold))
                        Text(aggregatedReason)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                }

                HStack(spacing: .strideSM) {
                    Button(action: onDismiss) {
                        Text("Got it")
                            .font(Font.stride.bodyMedium.weight(.semibold))
                            .foregroundStyle(Color.stride.warmOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: .strideRadiusSM, style: .continuous)
                                    .fill(Color.stride.warmOrange.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onUndo) {
                        Text("Undo")
                            .font(Font.stride.bodyMedium.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: .strideRadiusSM, style: .continuous)
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
