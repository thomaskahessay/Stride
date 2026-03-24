import SwiftUI
import MapKit

struct RouteMapView: View {
    let locationManager: LocationManager

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var hasInitiallyCentered = false
    @State var viewModel = RouteCreationViewModel()

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
                            WaypointMarker(
                                order: waypoint.order,
                                isStart: waypoint.type == .start
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
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { screenPoint in
                    guard viewModel.isCreating,
                          let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    viewModel.addWaypoint(at: coordinate)
                }
            }
            .onAppear {
                locationManager.startTracking()
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
                creationControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: .strideSM) {
                recentreButton
                createRouteToggle
            }
            .padding(.trailing, .strideMD)
            .padding(.top, .strideSM)
        }
        .overlay(alignment: .top) {
            if locationManager.isDenied {
                locationDeniedBanner
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.waypoints.count)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    // MARK: - Creation Controls

    private var creationControls: some View {
        VStack(spacing: .strideSM) {
            // Distance display
            if !viewModel.waypoints.isEmpty {
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
            .foregroundStyle(disabled ? .tertiary : Color.stride.lavenderDeep)
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
    }

    // MARK: - Location Denied Banner

    private var locationDeniedBanner: some View {
        HStack(spacing: .strideSM) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(Color.stride.coral)
            Text(locationManager.locationError ?? "Location access denied.")
                .font(Font.stride.bodyMedium)
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
    }
}
