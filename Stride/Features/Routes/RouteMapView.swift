import SwiftUI
import MapKit

struct RouteMapView: View {
    let locationManager: LocationManager
    var unitSystem: UnitSystem = .kilometers
    var editingRoute: Route?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var hasInitiallyCentered = false
    @State var viewModel = RouteCreationViewModel()
    @State private var showInfoPanel = false
    @State private var showSaveConfirmation = false
    @State private var showSaveAsNewPrompt = false
    @State private var saveAsNewName = ""
    @State private var showCancelConfirmation = false
    @State private var showDiscardAlert = false
    @FocusState private var isSearchFocused: Bool

    private let routeService = RouteService()

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()

                    // Waypoint annotations
                    ForEach(viewModel.waypoints) { waypoint in
                        Annotation(
                            "",
                            coordinate: CLLocationCoordinate2D(
                                latitude: waypoint.latitude,
                                longitude: waypoint.longitude
                            )
                        ) {
                            DraggableWaypointMarker(
                                waypoint: waypoint,
                                isDraggingEnabled: viewModel.isEditing,
                                mapProxy: proxy,
                                onDragEnd: { newCoord in
                                    viewModel.moveWaypoint(id: waypoint.id, to: newCoord)
                                },
                                onRemove: viewModel.waypoints.count > 2 ? {
                                    withAnimation {
                                        viewModel.removeWaypoint(id: waypoint.id)
                                    }
                                } : nil
                            )
                        }
                    }

                    // Road-snapped polyline segments
                    ForEach(Array(viewModel.polylineCoordinates.enumerated()), id: \.offset) { _, segment in
                        if segment.count >= 2 {
                            MapPolyline(coordinates: segment)
                                .stroke(Color.stride.lavenderDeep, lineWidth: 4)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapScaleView()
                    MapCompass()
                }
                .onTapGesture { screenPoint in
                    guard viewModel.isCreating, !showInfoPanel,
                          let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    viewModel.addWaypoint(at: coordinate)
                }
            }
            .onAppear {
                locationManager.requestAuthorisation()
                locationManager.startTracking()
                if let editingRoute, !viewModel.isEditing {
                    viewModel.loadRoute(editingRoute)
                    zoomToFitRoute(editingRoute)
                }
            }
            .onDisappear {
                locationManager.stopTracking()
            }
            .onChange(of: locationManager.currentLocation) { _, newLocation in
                guard !hasInitiallyCentered, let location = newLocation else { return }
                hasInitiallyCentered = true
                withAnimation {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: location.coordinate,
                            latitudinalMeters: 1000,
                            longitudinalMeters: 1000
                        )
                    )
                }
            }

            // Bottom controls overlay
            if viewModel.isCreating {
                if viewModel.isEditing {
                    editControls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    creationControls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: .strideSM) {
                recentreButton
                if !viewModel.isEditing {
                    createRouteToggle
                }
            }
            .padding(.trailing, .strideMD)
            .padding(.top, viewModel.isCreating ? 60 : 72)
        }
        .overlay(alignment: .top) {
            if viewModel.isCreating {
                addressSearchOverlay
            }
        }
        .overlay(alignment: .top) {
            if locationManager.isDenied {
                locationDeniedBanner
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.waypoints.count)
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isLoopClosed)
        .navigationTitle(viewModel.isEditing ? "Edit Route" : "Routes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isCreating)
        .toolbar {
            if viewModel.isCreating {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if viewModel.waypoints.isEmpty {
                            viewModel.stopCreating()
                            dismiss()
                        } else {
                            showDiscardAlert = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                        }
                    }
                }
            }
        }
        .alert("Discard Route?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                showInfoPanel = false
                viewModel.stopCreating()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have an unsaved route in progress. Going back will discard it.")
        }
        .sheet(isPresented: $showInfoPanel) {
            RouteInfoPanel(
                distanceMeters: viewModel.totalDistanceMeters,
                waypointCount: viewModel.waypoints.count,
                elevationGain: viewModel.elevationGain,
                isLoadingElevation: viewModel.isLoadingElevation,
                unitSystem: unitSystem,
                isLoading: viewModel.isLoadingSegment,
                onSave: saveRoute
            )
            .presentationDetents([.fraction(0.3), .medium])
            .presentationDragIndicator(.hidden)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.3)))
            .presentationBackground(.ultraThinMaterial)
            .task {
                await viewModel.fetchElevation()
            }
        }
        .sensoryFeedback(.success, trigger: showSaveConfirmation)
        .overlay {
            if showSaveConfirmation {
                saveConfirmationOverlay
            }
        }
    }

    // MARK: - Create Route Toggle

    private var createRouteToggle: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if viewModel.isCreating {
                    viewModel.stopCreating()
                } else {
                    viewModel.startCreating()
                }
            }
        } label: {
            Image(systemName: viewModel.isCreating ? "xmark" : "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(viewModel.isCreating ? Color.stride.coral : Color.stride.lavenderDeep)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .accessibilityLabel(viewModel.isCreating ? "Stop creating route" : "Create new route")
    }

    // MARK: - Creation Controls

    private var creationControls: some View {
        VStack(spacing: .strideSM) {
            // Distance & elevation display
            if !viewModel.waypoints.isEmpty {
                VStack(spacing: 4) {
                    HStack(spacing: .strideSM) {
                        Text(viewModel.formattedDistance)
                            .font(Font.stride.headingMedium)
                            .foregroundStyle(Color.stride.lavenderDeep)
                            .contentTransition(.numericText())

                        if viewModel.isLoadingSegment {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.stride.lavenderDeep)
                        }
                    }

                    if !viewModel.formattedElevation.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mountain.2")
                                .font(.system(size: 11))
                            Text(viewModel.formattedElevation)
                        }
                        .font(Font.stride.caption)
                        .foregroundStyle(Color.stride.lavenderDeep.opacity(0.8))
                    }
                }
            }

            // Straight-line fallback notice
            if viewModel.hasStraightLineFallback {
                Text("Some segments use straight-line distance")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }

            // Error message
            if let error = viewModel.routeError {
                Text(error)
                    .font(Font.stride.caption)
                    .foregroundStyle(Color.stride.coral)
            }

            HStack(spacing: 12) {
                // Undo
                controlButton(
                    icon: "arrow.uturn.backward",
                    label: "Undo",
                    disabled: !viewModel.canUndo
                ) {
                    withAnimation { viewModel.undoLastWaypoint() }
                }

                // Clear
                controlButton(
                    icon: "trash",
                    label: "Clear",
                    disabled: viewModel.waypoints.isEmpty
                ) {
                    withAnimation { viewModel.clearWaypoints() }
                }

                // Close Loop
                controlButton(
                    icon: "arrow.triangle.capsulepath",
                    label: "Close Loop",
                    disabled: !viewModel.canCloseLoop
                ) {
                    withAnimation { viewModel.closeLoop() }
                }

                // Save / Info
                controlButton(
                    icon: "square.and.arrow.down",
                    label: "Save",
                    disabled: viewModel.waypoints.count < 2
                ) {
                    showInfoPanel = true
                }
            }
        }
        .padding(.strideMD)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.stride.lavenderDeep.opacity(0.12), radius: 12, x: 0, y: 4)
        .padding(.horizontal, .strideMD)
        .padding(.bottom, .strideSM)
    }

    private func controlButton(
        icon: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(Font.stride.caption)
            }
            .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.stride.lavenderDeep))
            .frame(maxWidth: .infinity)
            .padding(.vertical, .strideSM)
        }
        .disabled(disabled)
    }

    // MARK: - Recentre Button

    private var recentreButton: some View {
        Button {
            guard let location = locationManager.currentLocation else { return }
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: 1000,
                        longitudinalMeters: 1000
                    )
                )
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.stride.lavenderDeep)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .accessibilityLabel("Recentre map on your location")
    }

    // MARK: - Edit Controls

    private var editControls: some View {
        VStack(spacing: .strideSM) {
            // Distance & elevation display
            VStack(spacing: 4) {
                HStack(spacing: .strideSM) {
                    Text(viewModel.formattedDistance)
                        .font(Font.stride.headingMedium)
                        .foregroundStyle(Color.stride.lavenderDeep)
                        .contentTransition(.numericText())

                    if viewModel.isLoadingSegment {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.stride.lavenderDeep)
                    }
                }

                if !viewModel.formattedElevation.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mountain.2")
                            .font(.system(size: 11))
                        Text(viewModel.formattedElevation)
                    }
                    .font(Font.stride.caption)
                    .foregroundStyle(Color.stride.lavenderDeep.opacity(0.8))
                }
            }

            if viewModel.hasStraightLineFallback {
                Text("Some segments use straight-line distance")
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.routeError {
                Text(error)
                    .font(Font.stride.caption)
                    .foregroundStyle(Color.stride.coral)
            }

            // Edit action buttons
            HStack(spacing: 12) {
                controlButton(
                    icon: "arrow.uturn.backward",
                    label: "Undo",
                    disabled: !viewModel.canUndo
                ) {
                    withAnimation { viewModel.undoLastWaypoint() }
                }

                controlButton(
                    icon: "trash",
                    label: "Clear",
                    disabled: viewModel.waypoints.isEmpty
                ) {
                    withAnimation { viewModel.clearWaypoints() }
                }

                controlButton(
                    icon: "arrow.triangle.capsulepath",
                    label: "Close Loop",
                    disabled: !viewModel.canCloseLoop
                ) {
                    withAnimation { viewModel.closeLoop() }
                }
            }

            // Save / Save as New / Cancel
            HStack(spacing: .strideSM) {
                Button("Cancel") {
                    showCancelConfirmation = true
                }
                .ghostStyle()
                .frame(maxWidth: .infinity, maxHeight: 48)

                Button("Save as New") {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMM d, yyyy"
                    saveAsNewName = "\(viewModel.editingRoute?.name ?? "Route") (copy)"
                    showSaveAsNewPrompt = true
                }
                .secondaryStyle()
                .frame(maxWidth: .infinity, maxHeight: 48)

                Button("Save") {
                    saveEditedRoute()
                }
                .primaryStyle()
                .frame(maxWidth: .infinity, maxHeight: 48)
            }
        }
        .padding(.strideMD)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.stride.lavenderDeep.opacity(0.12), radius: 12, x: 0, y: 4)
        .padding(.horizontal, .strideMD)
        .padding(.bottom, .strideSM)
        .alert("Discard Changes?", isPresented: $showCancelConfirmation) {
            Button("Discard", role: .destructive) {
                viewModel.stopCreating()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your unsaved changes will be lost.")
        }
        .alert("Save as New Route", isPresented: $showSaveAsNewPrompt) {
            TextField("Route name", text: $saveAsNewName)
            Button("Save") {
                Task {
                    await viewModel.fetchElevation()
                    let newRoute = viewModel.saveAsNewRoute(name: saveAsNewName, modelContext: modelContext)
                    newRoute.elevationGain = viewModel.elevationGain
                    showSaveAsNewPrompt = false
                    showSaveConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showSaveConfirmation = false
                            viewModel.stopCreating()
                            dismiss()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new route.")
        }
    }

    private func saveEditedRoute() {
        guard let route = viewModel.editingRoute else { return }

        Task {
            await viewModel.fetchElevation()
            viewModel.updateRoute(route)
            route.elevationGain = viewModel.elevationGain

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showSaveConfirmation = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showSaveConfirmation = false
                    viewModel.stopCreating()
                    dismiss()
                }
            }
        }
    }

    private func zoomToFitRoute(_ route: Route) {
        let wps = route.waypoints
        guard !wps.isEmpty else { return }
        let lats = wps.map(\.latitude)
        let lons = wps.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.4, 0.005)
        let lonDelta = max((maxLon - minLon) * 1.4, 0.005)

        hasInitiallyCentered = true
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                )
            )
        }
    }

    // MARK: - Save Route

    private func saveRoute(name: String) {
        let coordinates = viewModel.waypoints
            .sorted { $0.order < $1.order }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        // Estimate duration at ~5:30/km pace
        let paceSecondsPerMeter = 5.5 * 60.0 / 1000.0
        let estimatedDuration = viewModel.totalDistanceMeters * paceSecondsPerMeter

        let route = routeService.saveRoute(
            name: name,
            waypoints: coordinates,
            distance: viewModel.totalDistanceMeters,
            estimatedDuration: estimatedDuration,
            isLoop: viewModel.isLoopClosed,
            modelContext: modelContext
        )
        route.polylineCoordinates = viewModel.flatPolylineCoordinates.map {
            PolylineCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        route.segmentPolylines = viewModel.currentSegmentPolylines
        route.elevationGain = viewModel.elevationGain

        showInfoPanel = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSaveConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showSaveConfirmation = false
                viewModel.stopCreating()
            }
            dismiss()
        }
    }

    // MARK: - Address Search Overlay

    private var addressSearchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: .strideSM) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.stride.lavenderDeep)
                    .font(.system(size: 14, weight: .medium))

                TextField("Search address or place", text: Binding(
                    get: { viewModel.searchService.searchText },
                    set: { viewModel.searchService.updateSearch($0) }
                ))
                .focused($isSearchFocused)
                .font(Font.stride.bodyMedium)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()

                if !viewModel.searchService.searchText.isEmpty {
                    Button {
                        viewModel.searchService.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 16))
                    }
                }

                if viewModel.isResolvingSearch {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.stride.lavenderDeep)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)

            // Results list
            if !viewModel.searchService.results.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.searchService.results, id: \.self) { result in
                            Button {
                                isSearchFocused = false
                                Task {
                                    if let coord = await viewModel.selectSearchResult(result) {
                                        withAnimation {
                                            cameraPosition = .region(
                                                MKCoordinateRegion(
                                                    center: coord,
                                                    latitudinalMeters: 1000,
                                                    longitudinalMeters: 1000
                                                )
                                            )
                                        }
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(Font.stride.bodyMedium)
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(Font.stride.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if result != viewModel.searchService.results.last {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, .strideMD)
        .padding(.top, .strideSM)
        .contentShape(Rectangle())
        .onTapGesture { } // Consume taps so they don't pass through to the map
    }

    // MARK: - Save Confirmation Overlay

    private var saveConfirmationOverlay: some View {
        VStack(spacing: .strideSM) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.stride.mint)
            Text("Route Saved")
                .font(Font.stride.headingSmall)
        }
        .padding(.strideLG)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Location Denied Banner

    private var locationDeniedBanner: some View {
        HStack(spacing: .strideSM) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(Color.stride.coral)
            Text(locationManager.locationError ?? "Location access denied.")
                .font(Font.stride.bodyMedium)
            Spacer()
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(Font.stride.bodyMedium.weight(.semibold))
            .foregroundStyle(Color.stride.lavenderDeep)
        }
        .padding(.strideMD)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusMD))
        .padding(.horizontal, .strideMD)
        .padding(.top, .strideSM)
    }
}

// MARK: - Waypoint Marker

private struct WaypointMarker: View {
    let order: Int
    let isStart: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isStart ? Color.stride.mint : Color.stride.lavenderDeep)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)

            Text("\(order + 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Waypoint \(order + 1)\(isStart ? ", start point" : "")")
    }
}

// MARK: - Draggable Waypoint Marker

private struct DraggableWaypointMarker: View {
    let waypoint: RouteWaypoint
    let isDraggingEnabled: Bool
    let mapProxy: MapProxy
    let onDragEnd: (CLLocationCoordinate2D) -> Void
    let onRemove: (() -> Void)?

    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        WaypointMarker(order: waypoint.order, isStart: waypoint.type == .start)
            .scaleEffect(isDragging ? 1.3 : 1.0)
            .opacity(isDragging ? 0.8 : 1.0)
            .offset(dragOffset)
            .accessibilityHint(isDraggingEnabled ? "Drag to reposition. Long press for options." : "")
            .gesture(
                isDraggingEnabled
                ? DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        // Convert the current screen position to a map coordinate
                        let screenPoint = CGPoint(
                            x: value.startLocation.x + value.translation.width,
                            y: value.startLocation.y + value.translation.height
                        )
                        if let coordinate = mapProxy.convert(screenPoint, from: .local) {
                            onDragEnd(coordinate)
                        }
                        dragOffset = .zero
                    }
                : nil
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .contextMenu {
                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
    }
}
