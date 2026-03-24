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

    private var coordinates: [CLLocationCoordinate2D] {
        route.waypoints
            .sorted { $0.order < $1.order }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Map
                mapSection

                // Info cards
                VStack(spacing: .strideMD) {
                    statsSection
                    actionsSection
                }
                .padding(.strideMD)
            }
        }
        .background(LinearGradient.strideBackground.ignoresSafeArea())
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
    }

    // MARK: - Map Section

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
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: 2)
                            )
                    }
                } else if wp.type == .end {
                    Annotation("End", coordinate: coord) {
                        Circle()
                            .fill(Color.stride.coral)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: 2)
                            )
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusLG, style: .continuous))
        .padding(.horizontal, .strideMD)
        .padding(.top, .strideSM)
        .allowsHitTesting(false)
    }

    // MARK: - Stats Section

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
                    icon: "mappin.and.ellipse",
                    value: "\(route.waypoints.count)",
                    label: "Waypoints"
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
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: .strideSM) {
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
