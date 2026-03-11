import SwiftUI

// MARK: - Button Style: Primary

struct StridePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.stride.bodyLarge.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                    .fill(Color.stride.lavender)
                    .shadow(
                        color: Color.stride.lavenderDeep.opacity(0.3),
                        radius: 8, x: 0, y: 4
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Button Style: Secondary

struct StrideSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.stride.bodyMedium.weight(.semibold))
            .foregroundStyle(Color.stride.lavenderDeep)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                    .fill(Color.stride.lavenderLight)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Button Style: Ghost (outline)

struct StrideGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.stride.bodyMedium.weight(.semibold))
            .foregroundStyle(Color.stride.lavenderDeep)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                    .strokeBorder(Color.stride.lavenderDeep, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Convenience Extensions

extension Button {
    func primaryStyle() -> some View {
        self.buttonStyle(StridePrimaryButtonStyle())
    }

    func secondaryStyle() -> some View {
        self.buttonStyle(StrideSecondaryButtonStyle())
    }

    func ghostStyle() -> some View {
        self.buttonStyle(StrideGhostButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient.strideBackground.ignoresSafeArea()
        VStack(spacing: 16) {
            Button("Start Today's Run") {}
                .buttonStyle(StridePrimaryButtonStyle())

            Button("View Plan") {}
                .buttonStyle(StrideSecondaryButtonStyle())

            Button("Skip Workout") {}
                .buttonStyle(StrideGhostButtonStyle())
        }
        .padding(.strideMD)
    }
}
