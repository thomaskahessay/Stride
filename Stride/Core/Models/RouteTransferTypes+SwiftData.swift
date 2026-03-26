import Foundation

// MARK: - SwiftData-dependent extensions (main app target only)

extension RouteTransferData {
    init(from route: Route) {
        self.init(
            name: route.name,
            distance: route.distance,
            estimatedDurationSeconds: route.estimatedDurationSeconds,
            elevationGain: route.elevationGain,
            isLoop: route.isLoop,
            waypoints: route.waypoints,
            polylineCoordinates: route.polylineCoordinates,
            segmentPolylines: route.segmentPolylines,
            createdAt: route.createdAt
        )
    }

    func toRoute() -> Route {
        let route = Route(
            name: name,
            distance: distance,
            estimatedDurationSeconds: estimatedDurationSeconds,
            elevationGain: elevationGain,
            waypoints: waypoints,
            isLoop: isLoop
        )
        route.polylineCoordinates = polylineCoordinates
        route.segmentPolylines = segmentPolylines
        route.createdAt = createdAt
        return route
    }
}
