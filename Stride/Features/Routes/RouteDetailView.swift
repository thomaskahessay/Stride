import SwiftUI
import MapKit

struct RouteDetailView: View {
    let route: Route
    let unitSystem: UnitSystem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RouteDetailViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showShareToast = false
    @State private var trackingVM: RunTrackingViewModel?
    @State private var startOverride = false

    private var locationManager: LocationManager { LocationManager.shared }

    private var startCoordinate: CLLocationCoordinate2D? {
        guard let wp = route.waypoints.sorted(by: { $0.order < $1.order }).first else { return nil }
        return CLLocationCoordinate2D(latitude: wp.latitude, longitude: wp.longitude)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        let polyline = route.polylineCoordinates
        if !polyline.isEmpty {
            return polyline.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        let sorted = route.waypoints.sorted { $0.order < $1.order }
        var coords = sorted.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        if route.isLoop, let first = coords.first {
            coords.append(first)
        }
        return coords
    }

    private var isTracking: Bool {
        trackingVM?.isTracking ?? false
    }

    var body: some View {
        ZStack {
            if isTracking {
                trackingLayout
            } else {
                defaultLayout
            }
        }
        .background(LinearGradient.strideBackground.ignoresSafeArea())
        .navigationTitle(isTracking ? "" : route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isTracking ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if !isTracking {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            viewModel.toggleFavorite(route)
                        }
                    } label: {
                        Image(systemName: route.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(Color.stride.lavenderDeep)
                    }
                }
            }
        }
        .alert("Delete Route?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.deleteRoute(route, modelContext: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This route will be permanently deleted.")
        }
        .overlay {
            if showShareToast {
                shareToast
            }
        }
        .sheet(item: summaryBinding) { summary in
            runSummarySheet(summary)
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            locationManager.requestAuthorisation()
            locationManager.startTracking()
            if trackingVM == nil {
                trackingVM = RunTrackingViewModel(
                    locationManager: locationManager,
                    routeDistance: route.distance,
                    unitSystem: unitSystem,
                    startCoordinate: startCoordinate,
                    isLoop: route.isLoop
                )
            }
        }
        .onDisappear {
            if let vm = trackingVM, vm.isTracking {
                vm.stopRun()
            }
            locationManager.stopTracking()
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            guard let location = newLocation else { return }
            trackingVM?.locationDidUpdate(location)
        }
    }

    // MARK: - Default Layout (not tracking)

    private var defaultLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                mapSection
                VStack(spacing: .strideMD) {
                    statsSection
                    startRunSection
                    actionsSection
                }
                .padding(.strideMD)
            }
        }
    }

    // MARK: - Tracking Layout

    private var trackingLayout: some View {
        ZStack(alignment: .bottom) {
            trackingMapSection
            trackingPanel
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Map Section (default — shows user dot)

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.stride.lavenderDeep, lineWidth: 4)
            }

            ForEach(route.waypoints.sorted(by: { $0.order < $1.order })) { wp in
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

            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous))
        .padding(.horizontal, .strideMD)
        .padding(.top, .strideSM)
        .allowsHitTesting(false)
    }

    // MARK: - Tracking Map (full screen, follows user)

    private var trackingMapSection: some View {
        Map(position: $cameraPosition) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.stride.lavenderDeep, lineWidth: 4)
            }

            ForEach(route.waypoints.sorted(by: { $0.order < $1.order })) { wp in
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

            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onAppear {
            cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
        }
    }

    // MARK: - Tracking Panel

    private var trackingPanel: some View {
        VStack(spacing: .strideMD) {
            // Stats row
            HStack(spacing: 0) {
                trackingStat(
                    value: trackingVM?.formattedElapsed ?? "0:00",
                    label: "Time"
                )
                Divider().frame(height: 40)
                trackingStat(
                    value: trackingVM?.formattedDistance ?? "0.00",
                    label: "Distance"
                )
                Divider().frame(height: 40)
                trackingStat(
                    value: trackingVM?.formattedPace ?? "--:--",
                    label: "Pace"
                )
            }

            // Progress
            if let vm = trackingVM {
                Text(vm.progressText)
                    .font(Font.stride.bodyMedium)
                    .foregroundStyle(.secondary)
            }

            // Stop button
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    trackingVM?.stopRun()
                    cameraPosition = .automatic
                }
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop Run")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(StopRunButtonStyle())
        }
        .padding(.strideMD)
        .padding(.bottom, .strideSM)
        .background(
            RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous)
                        .fill(Color.stride.lavenderLight.opacity(0.3))
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func trackingStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Font.stride.headingMedium)
                .monospacedDigit()
            Text(label)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Start Run Section

    @ViewBuilder
    private var startRunSection: some View {
        if let vm = trackingVM, vm.needsNavigateToStart && !startOverride {
            navigateToStartCard(vm: vm)
        } else {
            startRunButton
        }
    }

    private func navigateToStartCard(vm: RunTrackingViewModel) -> some View {
        GlassCard {
            VStack(spacing: .strideSM) {
                HStack(spacing: .strideSM) {
                    Image(systemName: "location.circle")
                        .font(.title3)
                        .foregroundStyle(Color.stride.lavenderDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're not at the start")
                            .font(Font.stride.bodyMedium.weight(.semibold))
                        Text(vm.formattedDistanceToStart)
                            .font(Font.stride.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Button {
                    vm.openDirectionsToStart()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        Text("Get Directions")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(StridePrimaryButtonStyle())

                Button {
                    startOverride = true
                } label: {
                    Text("Start Anyway")
                        .frame(maxWidth: .infinity)
                }
                .ghostStyle()
            }
        }
    }

    private var startRunButton: some View {
        Button {
            guard let vm = trackingVM else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                vm.startRun()
            }
        } label: {
            HStack {
                Image(systemName: "figure.run")
                Text("Start Run")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(StridePrimaryButtonStyle())
        .disabled(!locationManager.isAuthorized)
    }

    // MARK: - Stats Section

    private var formattedElevation: String {
        guard let gain = route.elevationGain else { return "—" }
        switch unitSystem {
        case .kilometers:
            return String(format: "%.0f m", gain)
        case .miles:
            let feet = gain * 3.28084
            return String(format: "%.0f ft", feet)
        }
    }

    private var statsSection: some View {
        GlassCard {
            HStack(spacing: 0) {
                statItem(
                    icon: "ruler",
                    value: viewModel.formattedDistance(route.distance, unit: unitSystem),
                    label: "Distance"
                )

                Divider().frame(height: 40)

                statItem(
                    icon: "clock",
                    value: viewModel.formattedDuration(route.estimatedDurationSeconds),
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

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: .strideSM) {
            NavigationLink {
                RouteMapView(
                    locationManager: LocationManager.shared,
                    unitSystem: unitSystem,
                    editingRoute: route
                )
            } label: {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit Route")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(StridePrimaryButtonStyle())

            Button {
                showShareToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showShareToast = false }
                }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Route")
                }
                .frame(maxWidth: .infinity)
            }
            .secondaryStyle()

            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Route")
                }
                .frame(maxWidth: .infinity)
            }
            .ghostStyle()
        }
    }

    // MARK: - Run Summary Sheet

    private var summaryBinding: Binding<RunSummary?> {
        Binding(
            get: {
                guard let vm = trackingVM, vm.showSummary else { return nil }
                return RunSummary(
                    distance: vm.formattedSummaryDistance,
                    duration: vm.formattedSummaryDuration,
                    pace: vm.formattedSummaryPace
                )
            },
            set: { newValue in
                if newValue == nil {
                    trackingVM?.dismissSummary()
                    trackingVM = nil
                }
            }
        )
    }

    private func runSummarySheet(_ summary: RunSummary) -> some View {
        VStack(spacing: .strideLG) {
            Text("Run Complete")
                .font(Font.stride.headingMedium)

            HStack(spacing: 0) {
                summaryItem(value: summary.distance, label: "Distance")
                Divider().frame(height: 44)
                summaryItem(value: summary.duration, label: "Duration")
                Divider().frame(height: 44)
                summaryItem(value: summary.pace, label: "Avg Pace")
            }

            Button {
                trackingVM?.dismissSummary()
                trackingVM = nil
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StridePrimaryButtonStyle())
        }
        .padding(.strideLG)
    }

    private func summaryItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Font.stride.headingSmall)
                .monospacedDigit()
            Text(label)
                .font(Font.stride.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Share Toast

    private var shareToast: some View {
        VStack {
            Spacer()
            Text("Coming soon")
                .font(Font.stride.bodyMedium.weight(.medium))
                .padding(.horizontal, .strideLG)
                .padding(.vertical, .strideSM)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                .padding(.bottom, .strideXL)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Run Summary (Identifiable for sheet binding)

private struct RunSummary: Identifiable {
    let id = UUID()
    let distance: String
    let duration: String
    let pace: String
}

// MARK: - Stop Run Button Style

private struct StopRunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.stride.bodyLarge.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: .strideRadiusMD, style: .continuous)
                    .fill(Color.stride.coral)
                    .shadow(
                        color: Color.stride.coral.opacity(0.3),
                        radius: 8, x: 0, y: 4
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
