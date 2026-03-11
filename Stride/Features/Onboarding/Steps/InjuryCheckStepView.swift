import SwiftUI

struct InjuryCheckStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    private let columns = Array(repeating: GridItem(.flexible()), count: 2)

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "bandage.fill",
                    title: "Any aches or pains?",
                    subtitle: "We factor this into your load management from day one."
                )

                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Where are you feeling it?")
                            .font(Font.stride.headingSmall)

                        LazyVGrid(columns: columns, spacing: .strideSM) {
                            ForEach(InjuryRegion.allCases, id: \.self) { region in
                                InjuryRegionButton(
                                    region: region,
                                    isSelected: viewModel.currentInjuryRegion == region
                                ) {
                                    viewModel.currentInjuryRegion = region
                                }
                            }
                        }
                    }
                }

                if viewModel.currentInjuryRegion != .none,
                   let note = viewModel.currentInjuryRegion.planNote {
                    GlassCard {
                        HStack(alignment: .top, spacing: .strideSM) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color.stride.sky)
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("How we'll adapt your plan")
                                    .font(Font.stride.bodyMedium.weight(.semibold))
                                Text(note)
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Injury Region Button

private struct InjuryRegionButton: View {
    let region: InjuryRegion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: .strideXS) {
                Image(systemName: region.sfSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.stride.lavenderDeep : Color(.systemGray3))
                    .frame(height: 24)
                Text(region.rawValue)
                    .font(Font.stride.caption)
                    .foregroundStyle(isSelected ? Color.stride.lavenderDeep : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .strideSM)
            .background(
                RoundedRectangle(cornerRadius: .strideRadiusSM)
                    .fill(isSelected ? Color.stride.lavenderGlow : Color.stride.lavenderLight.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: .strideRadiusSM)
                            .strokeBorder(
                                isSelected ? Color.stride.lavender : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
