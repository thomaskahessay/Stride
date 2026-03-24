import Foundation
import CoreLocation
import SwiftData

final class RouteService {

    func saveRoute(
        name: String? = nil,
        waypoints: [CLLocationCoordinate2D],
        distance: Double,
        estimatedDuration: Double,
        modelContext: ModelContext
    ) -> Route {
        let routeWaypoints = waypoints.enumerated().map { index, coord in
            let type: WaypointType
            if index == 0 {
                type = .start
            } else if index == waypoints.count - 1 {
                type = .end
            } else {
                type = .via
            }
            return RouteWaypoint(
                latitude: coord.latitude,
                longitude: coord.longitude,
                order: index,
                type: type
            )
        }

        let route = Route(
            name: name,
            distance: distance,
            estimatedDurationSeconds: estimatedDuration,
            waypoints: routeWaypoints
        )
        modelContext.insert(route)
        return route
    }

    func fetchAllRoutes(modelContext: ModelContext) -> [Route] {
        let descriptor = FetchDescriptor<Route>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func deleteRoute(_ route: Route, modelContext: ModelContext) {
        modelContext.delete(route)
    }

    func toggleFavorite(_ route: Route) {
        route.isFavorite.toggle()
        route.updatedAt = Date()
    }
}
