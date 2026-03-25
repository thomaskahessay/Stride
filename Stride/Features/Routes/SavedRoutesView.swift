import SwiftUI
import SwiftData

struct SavedRoutesView: View {
    let unitSystem: UnitSystem

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.updatedAt, order: .reverse) private var routes: [Route]
    @State private var viewModel = SavedRoutesViewModel()

    private var locationManager: LocationManager { LocationManager.shared }

    var body: some View {
        Group {
            if locationManager.isDenied {
                locationDeniedState
            } else if routes.isEmpty {
                emptyState
            } else {
                routeList
            }
        }
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RouteMapView(
                        locationManager: LocationManager.shared,
                        unitSystem: unitSystem
                    )
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.stride.lavenderDeep)
                        .accessibilityLabel("Create new route")
                }
                .disabled(locationManager.isDenied)
            }
        }
        .alert("Delete Route?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let route = viewModel.routeToDelete {
                    withAnimation {
                        viewModel.deleteRoute(route, modelContext: modelContext)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This route will be permanently deleted.")
        }
    }

    // MARK: - Route List

    private var routeList: some View {
        List {
            ForEach(routes) { route in
                ZStack {
                    NavigationLink(value: route) {
                        EmptyView()
                    }
                    .opacity(0)

                    routeRow(route)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: .strideSM / 2,
                    leading: .strideMD,
                    bottom: .strideSM / 2,
                    trailing: .strideMD
                ))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.confirmDelete(route)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        withAnimation {
                            viewModel.toggleFavorite(route)
                        }
                    } label: {
                        Label(
                            route.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: route.isFavorite ? "star.slash" : "star.fill"
                        )
                    }
                    .tint(Color.stride.lavenderDeep)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LinearGradient.strideBackground.ignoresSafeArea())
        .navigationDestination(for: Route.self) { route in
            RouteDetailView(route: route, unitSystem: unitSystem)
        }
    }

    // MARK: - Route Row

    private func routeRow(_ route: Route) -> some View {
        HStack(spacing: .strideMD) {
            RouteThumbnail(waypoints: route.waypoints, polyline: route.polylineCoordinates, isLoop: route.isLoop)

            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(Font.stride.bodyLarge.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: .strideSM) {
                    Text(viewModel.formattedDistance(route.distance, unit: unitSystem))
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(viewModel.relativeDate(route.createdAt))
                        .font(Font.stride.bodyMedium)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if route.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.stride.lavenderDeep)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .glassCard()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: .strideMD) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(Color.stride.lavenderDeep.opacity(0.5))

            Text("No Saved Routes")
                .font(Font.stride.headingSmall)

            Text("Create your first route by tapping the + button above.")
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.strideLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.strideBackground.ignoresSafeArea())
    }

    // MARK: - Location Denied State

    private var locationDeniedState: some View {
        VStack(spacing: .strideMD) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.stride.coral.opacity(0.6))

            Text("Location Access Required")
                .font(Font.stride.headingSmall)

            Text("Stride needs location access to plan running routes. Enable it in Settings to get started.")
                .font(Font.stride.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Open Settings")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(StridePrimaryButtonStyle())
            .padding(.horizontal, .strideXL)
        }
        .padding(.strideLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.strideBackground.ignoresSafeArea())
    }
}
