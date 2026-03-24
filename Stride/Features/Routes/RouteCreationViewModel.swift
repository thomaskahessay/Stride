import Foundation
import MapKit

@Observable
final class RouteCreationViewModel {

    // MARK: - State

    var waypoints: [RouteWaypoint] = []
    var isCreating = false
    var isLoopClosed = false

    // MARK: - Computed

    var polylineCoordinates: [CLLocationCoordinate2D] {
        var coords = waypoints
            .sorted { $0.order < $1.order }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        if isLoopClosed, let first = coords.first {
            coords.append(first)
        }
        return coords
    }

    var totalDistanceMeters: Double {
        let coords = polylineCoordinates
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let from = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let to = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            total += from.distance(from: to)
        }
        return total
    }

    var formattedDistance: String {
        let km = totalDistanceMeters / 1000
        if km < 1 {
            return String(format: "%0.0f m", totalDistanceMeters)
        }
        return String(format: "%.2f km", km)
    }

    var canCloseLoop: Bool {
        waypoints.count >= 2 && !isLoopClosed
    }

    var canUndo: Bool {
        !waypoints.isEmpty
    }

    // MARK: - Actions

    func startCreating() {
        isCreating = true
        waypoints = []
        isLoopClosed = false
    }

    func stopCreating() {
        isCreating = false
        waypoints = []
        isLoopClosed = false
    }

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        guard isCreating, !isLoopClosed else { return }
        let type: WaypointType = waypoints.isEmpty ? .start : .via
        let waypoint = RouteWaypoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            order: waypoints.count,
            type: type
        )
        waypoints.append(waypoint)
    }

    func undoLastWaypoint() {
        guard !waypoints.isEmpty else { return }
        if isLoopClosed {
            isLoopClosed = false
            return
        }
        waypoints.removeLast()
    }

    func clearWaypoints() {
        waypoints = []
        isLoopClosed = false
    }

    func closeLoop() {
        guard canCloseLoop else { return }
        isLoopClosed = true
    }
}
