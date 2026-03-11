import SwiftUI

struct WelcomeStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    // MARK: - Animation state

    @State private var showLogo = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showNameCard = false
    @State private var showUnitCard = false
    @State private var logoPulse = false
    @State private var logoGlow = false
    @State private var typedSubtitle = ""
    @State private var isTypingComplete = false
    @FocusState private var nameFieldFocused: Bool

    private let fullSubtitle = "Let's build a plan that fits your life."

    var body: some View {
        ZStack {
            // Floating background particles
            FloatingParticlesView()
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: .strideXL) {
                        Spacer().frame(height: .strideLG)

                        // MARK: - Animated logo
                        logoSection

                        // MARK: - Title + typewriter subtitle
                        titleSection

                        // MARK: - Personalised greeting
                        if !viewModel.firstName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Let's go, \(viewModel.firstName.trimmingCharacters(in: .whitespaces)).")
                                .font(Font.stride.headingMedium)
                                .foregroundStyle(Color.stride.lavenderDeep)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        // MARK: - Name input card
                        nameInputCard
                            .id("nameField")

                        // MARK: - Unit preference card
                        unitPickerCard

                        Spacer().frame(height: .strideMD)
                    }
                    .padding(.horizontal, .strideMD)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: nameFieldFocused) { _, focused in
                    if focused {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("nameField", anchor: .center)
                        }
                    }
                }
            }
        }
        .onAppear(perform: startEntranceSequence)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.firstName)
    }

    // MARK: - Logo

    @State private var logoFloat = false

    private var logoSection: some View {
        ZStack {
            // Pulsing glow behind logo
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.stride.lavender.opacity(0.35),
                            Color.stride.lavender.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: logoGlow ? 100 : 75
                    )
                )
                .frame(width: 220, height: 160)
                .opacity(showLogo ? 1 : 0)

            // Stride logo PNG
            Image("StrideLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 120)
                // Sweep in from the left (matches the logo's flow direction)
                .offset(x: showLogo ? 0 : -120)
                .scaleEffect(showLogo ? (logoPulse ? 1.04 : 1.0) : 0.5)
                .opacity(showLogo ? 1 : 0)
                // Gentle floating hover
                .offset(y: logoFloat ? -6 : 6)
                .shadow(
                    color: Color.stride.lavender.opacity(logoGlow ? 0.4 : 0.15),
                    radius: logoGlow ? 20 : 10,
                    y: 4
                )
        }
        .onAppear {
            // Continuous float
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(1.0)) {
                logoFloat = true
            }
        }
    }

    // MARK: - Title & subtitle

    private var titleSection: some View {
        VStack(spacing: .strideSM) {
            Text("Welcome to Stride")
                .font(Font.stride.displayMedium)
                .multilineTextAlignment(.center)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 15)

            // Typewriter subtitle
            Text(typedSubtitle)
                .font(Font.stride.bodyLarge)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(showSubtitle ? 1 : 0)
                .frame(minHeight: 24)
        }
    }

    // MARK: - Name input

    private var nameInputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("First, what's your name?")
                    .font(Font.stride.headingSmall)

                TextField("Your first name", text: $viewModel.firstName)
                    .font(Font.stride.bodyLarge)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .focused($nameFieldFocused)
                    .padding(.strideSM)
                    .background(
                        RoundedRectangle(cornerRadius: .strideRadiusSM)
                            .fill(Color.stride.lavenderGlow)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: .strideRadiusSM)
                            .strokeBorder(
                                nameFieldFocused
                                    ? Color.stride.lavender
                                    : Color.clear,
                                lineWidth: 2
                            )
                            .animation(.easeInOut(duration: 0.2), value: nameFieldFocused)
                    )
            }
        }
        .opacity(showNameCard ? 1 : 0)
        .offset(y: showNameCard ? 0 : 30)
    }

    // MARK: - Unit picker

    private var unitPickerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("Preferred units")
                    .font(Font.stride.headingSmall)

                HStack(spacing: .strideSM) {
                    ForEach(UnitSystem.allCases, id: \.self) { unit in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                viewModel.selectedUnitSystem = unit
                            }
                        } label: {
                            Text(unit.rawValue)
                                .font(Font.stride.bodyMedium.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, .strideSM)
                                .background(
                                    RoundedRectangle(cornerRadius: .strideRadiusSM)
                                        .fill(viewModel.selectedUnitSystem == unit
                                              ? Color.stride.lavender
                                              : Color.stride.lavenderLight)
                                        .shadow(
                                            color: viewModel.selectedUnitSystem == unit
                                                ? Color.stride.lavender.opacity(0.4)
                                                : Color.clear,
                                            radius: 8, y: 2
                                        )
                                )
                                .foregroundStyle(viewModel.selectedUnitSystem == unit
                                                 ? .white
                                                 : Color.stride.lavenderDeep)
                                .scaleEffect(viewModel.selectedUnitSystem == unit ? 1.03 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .opacity(showUnitCard ? 1 : 0)
        .offset(y: showUnitCard ? 0 : 30)
    }

    // MARK: - Entrance sequence

    private func startEntranceSequence() {
        // Logo flies in
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.2)) {
            showLogo = true
        }

        // Start glow pulse loop
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(0.9)) {
            logoGlow = true
        }

        // Subtle logo pulse loop
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(1.0)) {
            logoPulse = true
        }

        // Title slides up
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.6)) {
            showTitle = true
        }

        // Subtitle appears then starts typewriter
        withAnimation(.easeOut(duration: 0.3).delay(0.9)) {
            showSubtitle = true
        }
        startTypewriterEffect(delay: 1.0)

        // Name card slides up
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(1.8)) {
            showNameCard = true
        }

        // Unit card slides up
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(2.1)) {
            showUnitCard = true
        }
    }

    // MARK: - Typewriter

    private func startTypewriterEffect(delay startDelay: Double) {
        let characters = Array(fullSubtitle)
        for (index, char) in characters.enumerated() {
            let charDelay = startDelay + Double(index) * 0.03
            DispatchQueue.main.asyncAfter(deadline: .now() + charDelay) {
                typedSubtitle.append(char)
                if index == characters.count - 1 {
                    isTypingComplete = true
                }
            }
        }
    }
}

// MARK: - Floating Particles Background

private struct FloatingParticlesView: View {
    @State private var animate = false

    private let particles: [Particle] = (0..<12).map { _ in
        Particle(
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            size: CGFloat.random(in: 6...20),
            opacity: Double.random(in: 0.06...0.18),
            duration: Double.random(in: 4...8)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles.indices, id: \.self) { i in
                let p = particles[i]
                Circle()
                    .fill(Color.stride.lavender)
                    .frame(width: p.size, height: p.size)
                    .opacity(p.opacity)
                    .position(
                        x: p.x * geo.size.width,
                        y: animate
                            ? p.y * geo.size.height - 40
                            : p.y * geo.size.height + 40
                    )
                    .blur(radius: p.size > 14 ? 3 : 1)
                    .animation(
                        .easeInOut(duration: p.duration)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.3),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

private struct Particle {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let duration: Double
}
