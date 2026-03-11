import SwiftUI

// MARK: - Shared step header used by all onboarding step views

@ViewBuilder
func stepHeader(icon: String, title: String, subtitle: String) -> some View {
    VStack(spacing: .strideSM) {
        Image(systemName: icon)
            .font(.system(size: 56))
            .foregroundStyle(Color.stride.lavender)
            .padding(.bottom, .strideXS)

        Text(title)
            .font(Font.stride.displayMedium)
            .multilineTextAlignment(.center)

        Text(subtitle)
            .font(Font.stride.bodyMedium)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    .padding(.top, .strideLG)
}
