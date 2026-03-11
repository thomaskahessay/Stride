import SwiftUI

struct ScheduleStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: .strideLG) {
                stepHeader(
                    icon: "calendar.badge.checkmark",
                    title: "Your weekly schedule",
                    subtitle: "We'll build your plan around the days that work for you."
                )

                // Training days per week
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        HStack {
                            Text("Training Days / Week")
                                .font(Font.stride.headingSmall)
                            Spacer()
                            Text("\(viewModel.trainingDaysPerWeek) days")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.stride.lavenderDeep)
                        }

                        HStack(spacing: .strideSM) {
                            ForEach([3, 4, 5], id: \.self) { days in
                                Button {
                                    viewModel.trainingDaysPerWeek = days
                                } label: {
                                    Text("\(days)")
                                        .font(Font.stride.headingSmall)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, .strideSM)
                                        .background(
                                            RoundedRectangle(cornerRadius: .strideRadiusSM)
                                                .fill(viewModel.trainingDaysPerWeek == days
                                                      ? Color.stride.lavender
                                                      : Color.stride.lavenderLight)
                                        )
                                        .foregroundStyle(viewModel.trainingDaysPerWeek == days ? .white : Color.stride.lavenderDeep)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Preferred long run day
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Long Run Day")
                            .font(Font.stride.headingSmall)
                        Text("Your longest run of the week is always on this day.")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: .strideSM) {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                Button {
                                    viewModel.preferredLongRunDay = day
                                    viewModel.selectedRestDays.remove(day)
                                } label: {
                                    Text(day.shortName)
                                        .font(Font.stride.label)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, .strideSM)
                                        .background(
                                            RoundedRectangle(cornerRadius: .strideRadiusSM)
                                                .fill(viewModel.preferredLongRunDay == day
                                                      ? Color.stride.lavender
                                                      : Color.stride.lavenderLight)
                                        )
                                        .foregroundStyle(viewModel.preferredLongRunDay == day ? .white : Color.stride.lavenderDeep)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Rest days
                GlassCard {
                    VStack(alignment: .leading, spacing: .strideSM) {
                        Text("Rest Days")
                            .font(Font.stride.headingSmall)
                        Text("No runs scheduled on these days.")
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: .strideSM) {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                let isLongRunDay = viewModel.preferredLongRunDay == day
                                let isRest = viewModel.selectedRestDays.contains(day)

                                Button {
                                    if !isLongRunDay {
                                        if isRest {
                                            viewModel.selectedRestDays.remove(day)
                                        } else {
                                            viewModel.selectedRestDays.insert(day)
                                        }
                                    }
                                } label: {
                                    Text(day.shortName)
                                        .font(Font.stride.label)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, .strideSM)
                                        .background(
                                            RoundedRectangle(cornerRadius: .strideRadiusSM)
                                                .fill(isLongRunDay ? Color(.systemGray5)
                                                      : isRest ? Color.stride.coral.opacity(0.2)
                                                      : Color.stride.lavenderLight)
                                        )
                                        .foregroundStyle(isLongRunDay ? Color(.systemGray3)
                                                         : isRest ? Color.stride.coral
                                                         : Color.stride.lavenderDeep)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLongRunDay)
                            }
                        }

                        // Validation error
                        if let error = viewModel.scheduleValidationError {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(Font.stride.caption)
                                .foregroundStyle(Color.stride.coral)
                        }
                    }
                }
            }
            .padding(.horizontal, .strideMD)
            .padding(.bottom, 120)
        }
    }
}
