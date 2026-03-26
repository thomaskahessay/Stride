import SwiftUI
import SwiftData

struct RoutePickerView: View {
    let targetDistanceMiles: Double
    @Binding var selectedRoute: Route?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Route.updatedAt, order: .reverse) private var allRoutes: [Route]

    @State private var searchText = ""

    /// Routes whose distance is within ~25% of the target workout distance.
    private var suggestedRoutes: [Route] {
        guard targetDistanceMiles > 0 else { return [] }
        let targetMeters = targetDistanceMiles * 1609.34
        let tolerance = targetMeters * 0.25
        return filteredRoutes.filter { route in
            abs(route.distance - targetMeters) <= tolerance
        }
    }

    /// Routes that don't match the distance filter.
    private var otherRoutes: [Route] {
        let suggested = Set(suggestedRoutes.map(\.id))
        return filteredRoutes.filter { !suggested.contains($0.id) }
    }

    private var filteredRoutes: [Route] {
        guard !searchText.isEmpty else { return allRoutes }
        return allRoutes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.strideBackground.ignoresSafeArea()

                if allRoutes.isEmpty {
                    ContentUnavailableView(
                        "No Saved Routes",
                        systemImage: "map",
                        description: Text("Create a route first from the Routes tab, then attach it here.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: .strideMD) {
                            // Suggested section (distance-matched)
                            if !suggestedRoutes.isEmpty {
                                sectionHeader(
                                    "Suggested",
                                    subtitle: "Routes near your \(String(format: "%.1f", targetDistanceMiles * 1.60934)) km target"
                                )
                                ForEach(suggestedRoutes) { route in
                                    routeRow(route, isSuggested: true)
                                }
                            }

                            // All other routes
                            if !otherRoutes.isEmpty {
                                sectionHeader("All Routes")
                                ForEach(otherRoutes) { route in
                                    routeRow(route, isSuggested: false)
                                }
                            }
                        }
                        .padding(.strideMD)
                    }
                    .searchable(text: $searchText, prompt: "Search routes")
                }
            }
            .navigationTitle("Pick a Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.stride.lavenderDeep)
                }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Font.stride.headingSmall)
            if let subtitle {
                Text(subtitle)
                    .font(Font.stride.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, .strideSM)
    }

    // MARK: - Route Row

    private func routeRow(_ route: Route, isSuggested: Bool) -> some View {
        Button {
            selectedRoute = route
            dismiss()
        } label: {
            GlassCard {
                HStack(spacing: .strideSM) {
                    RouteThumbnail(
                        waypoints: route.waypoints,
                        polyline: route.polylineCoordinates,
                        isLoop: route.isLoop,
                        size: 48
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(route.name)
                                .font(Font.stride.bodyMedium.weight(.semibold))
                                .lineLimit(1)

                            if route.isFavorite {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.stride.coral)
                            }
                        }

                        HStack(spacing: 8) {
                            Text(String(format: "%.1f km", route.distance / 1000))
                                .font(Font.stride.caption)
                                .foregroundStyle(.secondary)

                            if route.isLoop {
                                Label("Loop", systemImage: "arrow.triangle.capsulepath")
                                    .font(Font.stride.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if isSuggested {
                        Text("Match")
                            .font(Font.stride.label)
                            .foregroundStyle(Color.stride.mint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.stride.mint.opacity(0.15))
                            )
                    }

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
