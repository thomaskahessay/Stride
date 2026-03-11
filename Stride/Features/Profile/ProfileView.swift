import SwiftUI
import SwiftData

struct ProfileView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @State private var showSettings = false
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {

                        // Profile header
                        GlassCard {
                            HStack(spacing: .strideMD) {
                                // Avatar placeholder
                                Circle()
                                    .fill(Color.stride.lavenderLight)
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Text(String(profile.firstName.prefix(1)).uppercased())
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundStyle(Color.stride.lavenderDeep)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.firstName)
                                        .font(Font.stride.headingMedium)
                                    Text("\(profile.fitnessLevel.rawValue) · \(profile.raceType.displayName)")
                                        .font(Font.stride.bodyMedium)
                                        .foregroundStyle(.secondary)
                                    Text("Race: \(profile.raceDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(Font.stride.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }

                        // Plan summary
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Training Plan")
                                    .font(Font.stride.headingSmall)

                                if let plan = profile.activePlan {
                                    profileRow(label: "Week", value: "Week \(plan.currentWeekNumber) of \(plan.totalWeeks)")
                                    Divider()
                                    profileRow(label: "Generated", value: plan.generatedAt.formatted(date: .abbreviated, time: .omitted))
                                    Divider()
                                    profileRow(label: "Completion", value: "\(Int(plan.completionPercentage * 100))%")
                                } else {
                                    Text("No active plan.")
                                        .font(Font.stride.bodyMedium)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Settings
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideXS) {
                                Text("Settings")
                                    .font(Font.stride.headingSmall)
                                    .padding(.bottom, .strideXS)

                                settingsButton(icon: "bell.fill", label: "Notifications") {
                                    showSettings = true
                                }
                                Divider()
                                settingsButton(icon: "ruler.fill", label: "Units: \(profile.unitPreference.rawValue)") {
                                    showSettings = true
                                }
                                Divider()
                                settingsButton(icon: "arrow.triangle.2.circlepath", label: "Regenerate Plan") {
                                    showSettings = true
                                }
                            }
                        }

                        // Danger zone
                        Button("Reset All Data") {
                            showResetConfirm = true
                        }
                        .buttonStyle(StrideGhostButtonStyle())
                        .foregroundStyle(Color.stride.coral)
                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Color.stride.lavenderDeep)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(profile: profile)
        }
        .confirmationDialog("Reset all data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete your training plan, all logs, and your profile. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(Font.stride.bodyMedium).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(Font.stride.bodyMedium.weight(.semibold))
        }
    }

    private func settingsButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.stride.lavenderDeep)
                    .frame(width: 24)
                Text(label).font(Font.stride.bodyMedium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.systemGray3))
            }
            .padding(.vertical, .strideXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resetAllData() {
        try? modelContext.delete(model: UserProfile.self)
        try? modelContext.save()
    }
}

// MARK: - Settings View

struct SettingsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var unitPreference: UnitSystem

    init(profile: UserProfile) {
        self.profile = profile
        var components = DateComponents()
        components.hour = profile.dailyReminderHour
        components.minute = profile.dailyReminderMinute
        let time = Calendar.current.date(from: components) ?? Date()
        self._reminderEnabled = State(initialValue: profile.notificationsEnabled)
        self._reminderTime = State(initialValue: time)
        self._unitPreference = State(initialValue: profile.unitPreference)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .strideMD) {

                        // Notifications
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Notifications")
                                    .font(Font.stride.headingSmall)

                                Toggle("Daily Reminder", isOn: $reminderEnabled)
                                    .tint(Color.stride.lavender)

                                if reminderEnabled {
                                    DatePicker("Reminder Time", selection: $reminderTime,
                                               displayedComponents: .hourAndMinute)
                                        .tint(Color.stride.lavender)
                                }
                            }
                        }

                        // Units
                        GlassCard {
                            VStack(alignment: .leading, spacing: .strideSM) {
                                Text("Distance Units")
                                    .font(Font.stride.headingSmall)

                                Picker("Units", selection: $unitPreference) {
                                    ForEach(UnitSystem.allCases, id: \.self) { unit in
                                        Text(unit.rawValue).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        Button("Save") { save() }
                            .buttonStyle(StridePrimaryButtonStyle())
                    }
                    .padding(.strideMD)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    private func save() {
        let hour = Calendar.current.component(.hour, from: reminderTime)
        let minute = Calendar.current.component(.minute, from: reminderTime)
        profile.notificationsEnabled = reminderEnabled
        profile.dailyReminderHour = hour
        profile.dailyReminderMinute = minute
        profile.unitPreference = unitPreference
        try? modelContext.save()
        NotificationManager.shared.scheduleAll(for: profile)
        dismiss()
    }
}
