import SwiftUI
import SwiftData
import MapKit

struct RouteImportView: View {
    let url: URL

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RouteImportViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] {
        guard let data = viewModel.routeData else { return [] }
        return data.polylineCoordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var waypoints: [RouteWaypoint] {
        viewModel.routeData?.waypoints ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                if let error = viewModel.errorMessage {
                    errorContent(error)
                } else if viewModel.routeData != nil {
                    importContent
                } else {
                    ProgressView("Loading route...")
                }
            }
            .navigationTitle("Import Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            viewModel.loadRoute(from: url)
        }
        .onChange(of: viewModel.didSave) { _, saved in
            if saved { dismiss() }
        }
    }

    // MARK: - Import Content

    private var importContent: some View {
        ScrollView {
            VStack(spacing: .strideMD) {
                mapPreview
                statsCard
                nameField
                saveButton
            }
            .padding(.strideMD)
        }
    }

    // MARK: - Map Preview

    private var mapPreview: some View {
        Map(position: $cameraPosition) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.stride.lavenderDeep, lineWidth: 4)
            }

            ForEach(waypoints.sorted(by: { $0.order < $1.order })) { wp in
                let coord = CLLocationCoordinate2D(latitude: wp.latitude, longitude: wp.longitude)
                if wp.type == .start {
                    Annotation("Start", coordinate: coord) {
                        Circle()
                            .fill(Color.stride.mint)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                } else if wp.type == .end {
                    Annotation("End", coordinate: coord) {
                        Circle()
                            .fill(Color.stride.coral)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Stats

    private var statsCard: some View {
        GlassCard {
            HStack(spacing: 0) {
                statItem(
                    icon: "ruler",
                    value: formattedDistance,
                    label: "Distance"
                )
                Divider().frame(height: 40)
                statItem(
                    icon: "clock",
                    value: formattedDuration,
                    label: "Est. Time"
                )
                Divider().frame(height: 40)
                statItem(
                    icon: "mountain.2",
                    value: formattedElevation,
                    label: "Elevation"
                )
            }
        }
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.stride.lavenderDeep)
            Text(value)
                .font(Font.stride.headingSmall)
            Text(label)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Name Field

    private var nameField: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: .strideSM) {
                Text("Route Name")
                    .font(Font.stride.bodyMedium.weight(.semibold))
                TextField("Route name", text: $viewModel.routeName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            viewModel.saveRoute(modelContext: modelContext)
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Save Route")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(StridePrimaryButtonStyle())
    }

    // MARK: - Error

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: .strideMD) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.stride.coral)
            Text("Could not import route")
                .font(Font.stride.headingSmall)
            Text(message)
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Dismiss") { dismiss() }
                .ghostStyle()
        }
        .padding(.strideLG)
    }

    // MARK: - Formatting

    private var formattedDistance: String {
        guard let data = viewModel.routeData else { return "—" }
        return String(format: "%.2f km", data.distance / 1000)
    }

    private var formattedDuration: String {
        guard let data = viewModel.routeData else { return "—" }
        let minutes = Int(data.estimatedDurationSeconds) / 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return "\(minutes) min"
    }

    private var formattedElevation: String {
        guard let gain = viewModel.routeData?.elevationGain else { return "—" }
        return String(format: "%.0f m", gain)
    }
}
