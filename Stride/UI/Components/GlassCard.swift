import SwiftUI

// MARK: - Glass Card

/// The primary reusable card component for Stride.
/// Applies frosted glassmorphism with a subtle lavender tint.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat
    var padding: CGFloat
    var content: () -> Content

    init(
        cornerRadius: CGFloat = .strideRadiusLG,
        padding: CGFloat = .strideMD,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(glassBackground)
            .shadow(
                color: Color.stride.lavenderDeep.opacity(0.12),
                radius: 12, x: 0, y: 4
            )
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(gradientOverlay)
            .overlay(borderOverlay)
    }

    private var gradientOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient.glassOverlay)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
    }
}

// MARK: - Hero Glass Card

/// Larger variant used for Today's Workout and Race Countdown cards.
struct HeroGlassCard<Content: View>: View {
    var tint: Color
    var content: () -> Content

    init(tint: Color = Color.stride.lavender, @ViewBuilder content: @escaping () -> Content) {
        self.tint = tint
        self.content = content
    }

    var body: some View {
        GlassCard(cornerRadius: .strideRadiusHero, padding: .strideLG) {
            content()
        }
        .overlay(
            RoundedRectangle(cornerRadius: .strideRadiusHero, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.18), tint.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
    }
}

// MARK: - Convenience Modifier

extension View {
    func glassCard(
        cornerRadius: CGFloat = .strideRadiusLG,
        padding: CGFloat = .strideMD
    ) -> some View {
        GlassCard(cornerRadius: cornerRadius, padding: padding) { self }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient.strideBackground.ignoresSafeArea()
        VStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Easy Run").font(Font.stride.headingSmall)
                    Text("6.2 miles · ~58 min · Easy effort")
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HeroGlassCard(tint: Color.stride.lavender) {
                VStack(spacing: 4) {
                    Text("Race Day").font(Font.stride.label).foregroundStyle(.secondary)
                    Text("62").font(Font.stride.displayLarge)
                    Text("days to go").font(Font.stride.bodyMedium).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.strideMD)
    }
}
