import SwiftUI

struct RouteInfoPanel: View {
    let distanceMeters: Double
    let waypointCount: Int
    let unitSystem: UnitSystem
    let isLoading: Bool
    let onSave: (String) -> Void

    @State private var routeName: String = ""
    @State private var isShowingNamePrompt = false

    private var formattedDistance: String {
        switch unitSystem {
        case .kilometers:
            let km = distanceMeters / 1000
            return String(format: "%.2f km", km)
        case .miles:
            let mi = distanceMeters / 1609.344
            return String(format: "%.2f mi", mi)
        }
    }

    private var estimatedTime: String {
        // Default pace: 5:30/km
        let paceSecondsPerMeter = 5.5 * 60.0 / 1000.0
        let totalSeconds = distanceMeters * paceSecondsPerMeter
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%dh %02dm", hours, remainingMinutes)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: .strideMD) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, .strideSM)

            // Stats grid
            HStack(spacing: 0) {
                statItem(
                    icon: "ruler",
                    value: formattedDistance,
                    label: "Distance"
                )

                Divider()
                    .frame(height: 40)

                statItem(
                    icon: "clock",
                    value: estimatedTime,
                    label: "Est. Time"
                )

                Divider()
                    .frame(height: 40)

                statItem(
                    icon: "mappin.and.ellipse",
                    value: "\(waypointCount)",
                    label: "Waypoints"
                )

                Divider()
                    .frame(height: 40)

                statItem(
                    icon: "mountain.2",
                    value: "—",
                    label: "Elevation"
                )
            }

            // Save button
            Button {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy"
                routeName = "Run — \(formatter.string(from: Date()))"
                isShowingNamePrompt = true
            } label: {
                HStack(spacing: .strideSM) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text("Save Route")
                        .font(Font.stride.bodyLarge.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .primaryStyle()
            .disabled(isLoading)
            .padding(.horizontal, .strideSM)
            .padding(.bottom, .strideSM)
        }
        .background(.ultraThinMaterial)
        .background(Color.stride.lavenderLight.opacity(0.3))
        .alert("Route Name", isPresented: $isShowingNamePrompt) {
            TextField("Route name", text: $routeName)
            Button("Save") {
                onSave(routeName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for your route.")
        }
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.stride.lavenderDeep)

            Text(value)
                .font(Font.stride.headingSmall)
                .contentTransition(.numericText())

            Text(label)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
