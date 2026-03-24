import Foundation
import MapKit

@Observable
final class RouteCreationViewModel {

    // MARK: - State

    var waypoints: [RouteWaypoint] = []
    var isCreating = false
    var isLoopClosed = false
    var isLoadingSegment = false
    var routeError: String?

    // MARK: - Segment Cache

    /// Cached MKRoute for each segment (keyed by "fromOrder-toOrder").
    /// When the loop is closed, the closing segment uses key "loop".
    private var segmentRoutes: [String: MKRoute] = [:]

    /// Tracks whether a segment fell back to straight-line.
    private var straightLineFallbacks: Set<String> = []

    /// Debounce work item for directions requests.
    private var pendingDirectionsWork: DispatchWorkItem?

    // MARK: - Computed — Polyline Coordinates

    /// Returns the full set of coordinates for display, preferring road-snapped
    /// segments where available, falling back to straight lines.
    var polylineCoordinates: [[CLLocationCoordinate2D]] {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return [] }

        var segments: [[CLLocationCoordinate2D]] = []

        for i in 1..<sorted.count {
            let key = segmentKey(from: sorted[i - 1].order, to: sorted[i].order)
            if let route = segmentRoutes[key] {
                segments.append(route.polyline.coordinates)
            } else {
                // Straight-line fallback
                let from = CLLocationCoordinate2D(latitude: sorted[i - 1].latitude, longitude: sorted[i - 1].longitude)
                let to = CLLocationCoordinate2D(latitude: sorted[i].latitude, longitude: sorted[i].longitude)
                segments.append([from, to])
            }
        }

        if isLoopClosed, let first = sorted.first, let last = sorted.last {
            let key = "loop"
            if let route = segmentRoutes[key] {
                segments.append(route.polyline.coordinates)
            } else {
                let from = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
                let to = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
                segments.append([from, to])
            }
        }

        return segments
    }

    /// Flat list of all coordinates for simple polyline rendering.
    var flatPolylineCoordinates: [CLLocationCoordinate2D] {
        polylineCoordinates.flatMap { $0 }
    }

    // MARK: - Computed — Distance

    var totalDistanceMeters: Double {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return 0 }

        var total: Double = 0

        for i in 1..<sorted.count {
            let key = segmentKey(from: sorted[i - 1].order, to: sorted[i].order)
            if let route = segmentRoutes[key] {
                total += route.distance
            } else {
                let from = CLLocation(latitude: sorted[i - 1].latitude, longitude: sorted[i - 1].longitude)
                let to = CLLocation(latitude: sorted[i].latitude, longitude: sorted[i].longitude)
                total += from.distance(from: to)
            }
        }

        if isLoopClosed, let first = sorted.first, let last = sorted.last {
            if let route = segmentRoutes["loop"] {
                total += route.distance
            } else {
                let from = CLLocation(latitude: last.latitude, longitude: last.longitude)
                let to = CLLocation(latitude: first.latitude, longitude: first.longitude)
                total += from.distance(from: to)
            }
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

    var hasStraightLineFallback: Bool {
        !straightLineFallbacks.isEmpty
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
        segmentRoutes = [:]
        straightLineFallbacks = []
        routeError = nil
    }

    func stopCreating() {
        isCreating = false
        waypoints = []
        isLoopClosed = false
        segmentRoutes = [:]
        straightLineFallbacks = []
        routeError = nil
        pendingDirectionsWork?.cancel()
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

        // Request directions for the new segment (if we have at least 2 waypoints)
        if waypoints.count >= 2 {
            let fromWaypoint = waypoints[waypoints.count - 2]
            let toWaypoint = waypoint
            let key = segmentKey(from: fromWaypoint.order, to: toWaypoint.order)
            requestDirectionsDebounced(
                from: CLLocationCoordinate2D(latitude: fromWaypoint.latitude, longitude: fromWaypoint.longitude),
                to: CLLocationCoordinate2D(latitude: toWaypoint.latitude, longitude: toWaypoint.longitude),
                key: key
            )
        }
    }

    func undoLastWaypoint() {
        guard !waypoints.isEmpty else { return }
        if isLoopClosed {
            isLoopClosed = false
            segmentRoutes.removeValue(forKey: "loop")
            straightLineFallbacks.remove("loop")
            return
        }

        let removed = waypoints.removeLast()
        // Remove the segment that connected to this waypoint
        if !waypoints.isEmpty {
            let key = segmentKey(from: waypoints.last?.order ?? 0, to: removed.order)
            segmentRoutes.removeValue(forKey: key)
            straightLineFallbacks.remove(key)
        }
        routeError = nil
    }

    func clearWaypoints() {
        waypoints = []
        isLoopClosed = false
        segmentRoutes = [:]
        straightLineFallbacks = []
        routeError = nil
        pendingDirectionsWork?.cancel()
    }

    func closeLoop() {
        guard canCloseLoop else { return }
        isLoopClosed = true

        guard let first = waypoints.first, let last = waypoints.last else { return }
        requestDirectionsDebounced(
            from: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
            to: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
            key: "loop"
        )
    }

    // MARK: - MKDirections

    private func segmentKey(from: Int, to: Int) -> String {
        "\(from)-\(to)"
    }

    private func requestDirectionsDebounced(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        key: String
    ) {
        pendingDirectionsWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchDirections(from: source, to: destination, key: key)
            }
        }
        pendingDirectionsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    @MainActor
    private func fetchDirections(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        key: String
    ) async {
        // Skip if already cached
        guard segmentRoutes[key] == nil else { return }

        isLoadingSegment = true
        routeError = nil

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            if let route = response.routes.first {
                segmentRoutes[key] = route
                straightLineFallbacks.remove(key)
            } else {
                straightLineFallbacks.insert(key)
            }
        } catch {
            straightLineFallbacks.insert(key)
            if let mkError = error as? MKError {
                switch mkError.code {
                case .directionsNotFound:
                    routeError = "No walking route found for this segment."
                case .placemarkNotFound:
                    routeError = "Could not locate one of the waypoints."
                default:
                    routeError = "Route unavailable — using straight line."
                }
            } else {
                routeError = "Network unavailable — using straight line."
            }
        }

        isLoadingSegment = false
    }
}

// MARK: - MKPolyline Coordinate Extraction

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
