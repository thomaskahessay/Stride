import SwiftUI

struct WelcomeStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: .strideXL) {
            Spacer()

            // Icon
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.stride.lavender)

            // Title + subtitle
            VStack(spacing: .strideSM) {
                Text("Welcome to Stride")
                    .font(Font.stride.displayMedium)
                    .multilineTextAlignment(.center)

                Text("Let's build your personalised\ntraining plan.")
                    .font(Font.stride.bodyLarge)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Name input
            GlassCard {
                VStack(alignment: .leading, spacing: .strideSM) {
                    Text("First, what's your name?")
                        .font(Font.stride.headingSmall)

                    TextField("Your first name", text: $viewModel.firstName)
                        .font(Font.stride.bodyLarge)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .padding(.strideSM)
                        .background(
                            RoundedRectangle(cornerRadius: .strideRadiusSM)
                                .fill(Color.stride.lavenderGlow)
                        )
                }
            }
            .padding(.horizontal, .strideMD)

            // Unit preference
            GlassCard {
                VStack(alignment: .leading, spacing: .strideSM) {
                    Text("Preferred units")
                        .font(Font.stride.headingSmall)

                    HStack(spacing: .strideSM) {
                        ForEach(UnitSystem.allCases, id: \.self) { unit in
                            Button {
                                viewModel.selectedUnitSystem = unit
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
                                    )
                                    .foregroundStyle(viewModel.selectedUnitSystem == unit
                                                     ? .white
                                                     : Color.stride.lavenderDeep)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, .strideMD)

            Spacer()
        }
        .padding(.horizontal, .strideMD)
    }
}
