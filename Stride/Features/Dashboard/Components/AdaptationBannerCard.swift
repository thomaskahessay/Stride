import SwiftUI

struct CoachRecommendationCard: View {
    let recommendation: CoachRecommendation
    let onDismiss: () -> Void

    private var iconColor: Color {
        switch recommendation.severity {
        case .info: return Color.stride.lavenderDeep
        case .warning: return Color.stride.warmOrange
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                HStack(spacing: .strideSM) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "message.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendation.title)
                            .font(Font.stride.bodyMedium.weight(.semibold))
                        Text(recommendation.message)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }

                    Spacer(minLength: 0)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Got it")
                        .font(Font.stride.bodyMedium.weight(.semibold))
                        .foregroundStyle(iconColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: .strideRadiusSM, style: .continuous)
                                .fill(iconColor.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
